/// Plenara v0 — the AutomationRunner + Review Feed (Spec 04 §3.9 / §4.8,
/// Spec 01 §4.4, Spec 02 §7.5).
///
/// Automations bind a condition to a skill: JSON files in `[dataDir]/automations/`
/// with shape `{automationId, targetType, condition:{kind:"schedule"|"onWrite",
/// cronExpression|afterField}, skillId, pendingSkill?, description}` (Spec 01 §4.4).
/// The runner is the component that evaluates a condition, fires the skill through
/// the interpreter, and owns the pending-review surface — the DispatchOrchestrator
/// (Session) cannot, because an automation fires with no utterance and no user
/// watching (Spec 04 §3.9).
///
/// **The unattended-confirmation rule (Spec 02 §7.5), applied by the resolved
/// plan's shape:**
///   • empty action plan (READ-ONLY, e.g. an encouragement/summary) → the
///     formatted result is DELIVERED as a notification line, no approval;
///   • non-empty plan (WRITES) → HELD as a pending Review-Feed item — never
///     applied unattended; the user approves (fresh re-resolve, Spec 02 §4.2)
///     or declines;
///   • DESTRUCTIVE (delete_record anywhere / dangerLevel destructive) →
///     refused — rejected at registration when resolvable, re-checked at fire
///     time (Spec 01 §5.3 invariant).
///
/// **The onWrite seam (Spec 04 §4.8):** the hook lives at exactly one place —
/// [notifyWrites], called by the Session after `_dispatch` persists a plan's
/// writes. Fully deterministic, no timers: testable against an in-memory store
/// with a fixed clock (the reminders SEAM+FAKE pattern, minus even the fake —
/// nothing here touches the OS).
///
/// **Deferred:** `schedule`/cron conditions register as `deferred` (validated,
/// surfaced, never armed) — they need the OS timer seam (Spec 04 §3.13 /
/// NotificationScheduler) and belong to the follow-up; `onWrite` is the
/// offline-testable core shipped here.
///
/// **v0 deviation, deliberate:** an automation may carry its skill INLINE under
/// a `skill` key (an "automation-local skill") instead of a file in `skills/`.
/// Spec 01 §4.4 puts the skill in `skills/`, but v0's cloud cassette keys on the
/// routing inventory signature (replay_cloud.invSig = sorted skill ids), so a
/// new seed skill would force a full cassette re-record. An inline skill is
/// validated by the same static gate but never enters the routing inventory —
/// automations are fired by writes, not by voice, so it loses nothing in v0.
library;

import 'interpreter.dart';

/// Registration state of one automation, for the management/repair surface
/// (P2.8: an invalid or unresolved automation is surfaced, never dropped).
class AutomationStatus {
  final String automationId;

  /// `active` — armed for onWrite; `pending` — pendingSkill, inert until the
  /// skill is authored (then live, no re-registration needed); `deferred` —
  /// schedule/cron, valid but not armed in v0; `inert` — invalid/unresolved,
  /// surfaced for repair with [reason].
  final String state;
  final String? reason;
  const AutomationStatus(this.automationId, this.state, [this.reason]);

  @override
  String toString() => 'AutomationStatus($automationId: $state${reason == null ? '' : ' — $reason'})';
}

/// A read-only automation result, delivered without approval (Spec 02 §7.5:
/// "read-only result → deliver"). Surfaced via Session.pendingNudges and
/// drainable by a UI via [AutomationRunner.takeDeliveries].
class AutomationDelivery {
  final String automationId;
  final String skillId;
  final String text;
  final DateTime at;
  const AutomationDelivery(this.automationId, this.skillId, this.text, this.at);
}

/// One automation-produced plan HELD for the user's approval — a Review-Feed
/// item (Spec 04 §3.9). Its writes are never applied unattended.
class ReviewItem {
  final String id; // review-item handle (the executionId analogue)
  final String automationId;
  final String skillId;
  final String description; // why the automation exists — shown in the feed
  final DateTime firedAt; // the frozen clock; re-resolve reuses it (Spec 02 §4.4)
  final Map<String, dynamic> slots; // the frozen inputs the skill was fired with
  final int depth; // cascade depth of the triggering write (Spec 04 §4.8)
  final Map<String, dynamic> _skill;
  Plan plan; // the held ActionPlan; replaced when a re-resolve differs (§4.2)
  ReviewItem._(this.id, this.automationId, this.skillId, this.description, this.firedAt,
      this.slots, this.depth, this._skill, this.plan);

  /// The pending literal writes the user is approving — the review payload.
  List<Map<String, dynamic>> get pendingWrites => plan.writes;

  /// The skill's formatted description of what it would do.
  String? get preview => plan.confirmation;
}

/// Outcome of approving a review item: `applied` (executed + persisted, with
/// the confirmation text), `planChanged` (the data moved since it was held —
/// the item now carries the NEW plan and needs re-approval, Spec 02 §4.2),
/// `refused` (no longer resolvable / turned destructive; item removed), or
/// `notFound`.
class ReviewResolution {
  final String kind; // 'applied' | 'planChanged' | 'refused' | 'notFound'
  final String? message;
  const ReviewResolution(this.kind, [this.message]);
}

class _Registered {
  final Map<String, dynamic> def;
  String state = 'active';
  String? reason;
  Map<String, dynamic>? inlineSkill;
  _Registered(this.def);
}

class AutomationRunner {
  final Map<String, Map<String, dynamic>> types;

  /// The shared skill registry (the routing inventory). Skills referenced by
  /// `skillId` alone are resolved here AT FIRE TIME — so a `pendingSkill`
  /// automation goes live the moment its skill is authored (Spec 01 §4.4).
  final Map<String, Map<String, dynamic>> skills;
  final Map<String, Map<String, dynamic>> store;
  final DateTime Function() clock;

  /// Write-through persistence for APPROVED review-item writes (the Session
  /// passes `repo.persist`). Null → in-memory only (pure tests).
  final void Function(Map<String, dynamic> record)? persist;

  /// The cascade bound (Spec 04 §4.8): an approved automation write may itself
  /// fire onWrite hooks, at depth+1; hooks are suppressed (and surfaced) at the
  /// bound. Every hop past depth 0 requires a user approval, so a cascade is
  /// user-gated as well as bounded.
  static const int maxCascadeDepth = 3;

  final List<_Registered> _regs = [];
  final List<AutomationDelivery> _deliveries = [];
  final List<ReviewItem> _pending = [];

  /// Fire-time refusals and failures — the P2.8 surface (suppressed cascades,
  /// destructive refusals, skills that failed to resolve). Never silently empty
  /// when something went wrong; never breaks the user's turn.
  final List<String> refusals = [];
  int _seq = 0;

  AutomationRunner(
      {required this.types,
      required this.skills,
      required this.store,
      required this.clock,
      this.persist});

  /// Register a folder-load of automation defs (keyed by automationId, as
  /// StorageRepository.loadDefs returns them). Deterministic order. Invalid or
  /// unresolved defs register as `inert` with a reason — surfaced, never
  /// dropped and never a startup failure (Spec 01 §5.2 step 7).
  void register(Map<String, Map<String, dynamic>> defs) {
    for (final id in defs.keys.toList()..sort()) {
      _registerOne(defs[id]!);
    }
  }

  List<AutomationStatus> get statuses => [
        for (final r in _regs)
          AutomationStatus(r.def['automationId']?.toString() ?? '?', r.state, r.reason)
      ];

  /// The pending-review surface (Spec 04 §3.9) — automation plans awaiting the
  /// user's approval. Backs the `show_pending` command / review UI.
  List<ReviewItem> get pendingReview => List.unmodifiable(_pending);

  /// Delivered read-only results not yet drained by a UI.
  List<AutomationDelivery> get deliveries => List.unmodifiable(_deliveries);

  /// Drain the delivery outbox (a UI shows each once).
  List<AutomationDelivery> takeDeliveries() {
    final out = List<AutomationDelivery>.from(_deliveries);
    _deliveries.clear();
    return out;
  }

  void _registerOne(Map<String, dynamic> def) {
    final reg = _Registered(def);
    _regs.add(reg);
    void inert(String why) {
      reg.state = 'inert';
      reg.reason = why;
    }

    final id = def['automationId'], target = def['targetType'], skillId = def['skillId'];
    final cond = def['condition'], desc = def['description'];
    if (id is! String || id.isEmpty) return inert('missing automationId');
    if (target is! String || target.isEmpty) return inert('missing targetType');
    if (skillId is! String || skillId.isEmpty) return inert('missing skillId');
    if (desc is! String || desc.isEmpty) return inert('missing description (why this automation exists)');
    if (cond is! Map) return inert('missing condition');
    final kind = cond['kind'];
    if (kind == 'schedule') {
      if (cond['cronExpression'] is! String) return inert('schedule condition needs a cronExpression');
      reg.state = 'deferred';
      reg.reason = 'schedule/cron is deferred in v0 (needs the OS timer seam) — registered, not armed';
      return;
    }
    if (kind != 'onWrite') return inert("unknown condition kind '$kind' (schedule|onWrite)");
    final after = cond['afterField'];
    if (after is! String || after.isEmpty) return inert('onWrite condition needs an afterField');
    final td = types[target];
    if (td == null) return inert("unresolved targetType '$target' — inert until it exists");
    final attrs = (td['attributes'] as List?) ?? const [];
    if (!attrs.any((a) => a is Map && a['name'] == after)) {
      return inert("afterField '$after' is not an attribute of '$target'");
    }
    final inline = def['skill'];
    if (inline is Map) {
      final s = inline.cast<String, dynamic>();
      if (s['skillId'] != skillId) {
        return inert("inline skill's skillId ('${s['skillId']}') must match the automation's skillId ('$skillId')");
      }
      try {
        Interpreter(types, clock()).validateSkill(s); // same static gate as any skill
      } on ResolveError catch (e) {
        return inert('inline skill failed validation: ${e.message}');
      }
      reg.inlineSkill = s;
    }
    // Destructive skills never run unattended (Spec 02 §7.5; the Spec 01 §5.3
    // registration invariant). Enforced here when the skill is resolvable now,
    // and re-checked at fire time (the shared registry can change under us).
    final skill = reg.inlineSkill ?? skills[skillId];
    if (skill != null && _isDestructive(skill)) {
      return inert('destructive skill — forbidden for automations (Spec 02 §7.5)');
    }
    if (skill == null && def['pendingSkill'] != true) {
      return inert("skill '$skillId' not found in the registry (mark pendingSkill:true if it is not yet authored)");
    }
    if (skill == null) {
      reg.state = 'pending';
      reg.reason = "pendingSkill — inert until '$skillId' is authored";
    }
  }

  /// The onWrite hook (Spec 04 §4.8): called after a turn's writes are applied
  /// and persisted, with the written records. Matches each write against the
  /// registered onWrite automations (`targetType == typeId` and the record
  /// carries a non-null `afterField` value — v0's "that field was written")
  /// and fires each match. [depth] is the cascade depth of the triggering
  /// write (user-origin = 0).
  void notifyWrites(Iterable<Map<String, dynamic>> written, {int depth = 0}) {
    for (final rec in List.of(written)) {
      for (final reg in _regs) {
        if (reg.state != 'active' && reg.state != 'pending') continue;
        final cond = reg.def['condition'] as Map;
        if (cond['kind'] != 'onWrite') continue;
        if (reg.def['targetType'] != rec['typeId']) continue;
        if (rec[cond['afterField']] == null) continue; // afterField not written
        _fire(reg, rec, depth);
      }
    }
  }

  void _fire(_Registered reg, Map<String, dynamic> rec, int depth) {
    final autoId = reg.def['automationId'] as String;
    final skillId = reg.def['skillId'] as String;
    if (depth >= maxCascadeDepth) {
      refusals.add("automation '$autoId': onWrite suppressed at cascade depth $depth "
          '(bound $maxCascadeDepth, Spec 04 §4.8)');
      return;
    }
    final skill = reg.inlineSkill ?? skills[skillId];
    if (skill == null) return; // pendingSkill — stays inert until authored
    if (_isDestructive(skill)) {
      refusals.add("automation '$autoId': refused — destructive skills never run unattended (Spec 02 §7.5)");
      return;
    }
    final firedAt = clock(); // the frozen clock a re-resolve reuses (Spec 02 §4.4)
    final slots = <String, dynamic>{'recordId': rec['id']};
    final Plan plan;
    try {
      plan = Interpreter(types, firedAt).resolve(skill, slots, store);
    } catch (e) {
      // surfaced, never thrown into the user's turn (P2.8)
      refusals.add("automation '$autoId': skill '$skillId' failed to resolve — $e");
      return;
    }
    if (plan.deletes.isNotEmpty) {
      refusals.add("automation '$autoId': refused — the resolved plan deletes records "
          '(destructive is forbidden on the unattended path, Spec 02 §7.5)');
      return;
    }
    if (plan.writes.isEmpty) {
      // READ-ONLY → deliver the formatted result, no approval (Spec 02 §7.5).
      _deliveries.add(AutomationDelivery(
          autoId, skillId, plan.confirmation ?? '(the skill produced no text)', firedAt));
      return;
    }
    // WRITES → hold for review. NOT applied, NOT persisted (Spec 02 §7.5).
    _pending.add(ReviewItem._('review-${++_seq}', autoId, skillId,
        reg.def['description'] as String, firedAt, slots, depth, skill, plan));
  }

  /// Approve a held review item: re-resolve DETERMINISTICALLY (same frozen
  /// clock + slots, current data — Spec 02 §4.2's gated re-verify) and, if the
  /// fresh plan structurally matches the held one, execute + persist it. If
  /// the data moved and the plan differs, nothing executes on the stale
  /// approval — the item is updated with the new plan for re-approval.
  ReviewResolution approve(String reviewId) {
    final i = _pending.indexWhere((p) => p.id == reviewId);
    if (i < 0) return const ReviewResolution('notFound', 'no such pending review item');
    final item = _pending[i];
    final Plan fresh;
    try {
      fresh = Interpreter(types, item.firedAt).resolve(item._skill, item.slots, store);
    } catch (e) {
      _pending.removeAt(i);
      return ReviewResolution('refused', 'this plan no longer resolves against the current data — $e');
    }
    if (fresh.deletes.isNotEmpty) {
      _pending.removeAt(i);
      return const ReviewResolution(
          'refused', 'the re-resolved plan would delete records — forbidden on the unattended path');
    }
    if (!_samePlan(item.plan, fresh)) {
      item.plan = fresh; // the stale approval never executes (Spec 02 §4.2)
      return const ReviewResolution('planChanged',
          'the data changed since this was held — review the updated plan and approve again');
    }
    Interpreter(types, item.firedAt).execute(fresh, store);
    for (final w in fresh.writes) {
      persist?.call(w);
    }
    _pending.removeAt(i);
    // An approved automation write is itself a write: cascade at depth+1,
    // bounded — and every writing hop lands back in the review feed anyway.
    notifyWrites(fresh.writes, depth: item.depth + 1);
    return ReviewResolution('applied', fresh.confirmation);
  }

  /// Decline a held review item: reaped, nothing written.
  bool decline(String reviewId) {
    final i = _pending.indexWhere((p) => p.id == reviewId);
    if (i < 0) return false;
    _pending.removeAt(i);
    return true;
  }

  /// Destructive = declared (`dangerLevel: destructive`) or effective (any
  /// `delete_record` step on any path).
  static bool _isDestructive(Map<String, dynamic> skill) {
    if (skill['dangerLevel'] == 'destructive') return true;
    bool scan(dynamic steps) {
      if (steps is! List) return false;
      for (final s in steps) {
        if (s is! Map) continue;
        if (s['op'] == 'delete_record') return true;
        if (scan(s['then']) || scan(s['else']) || scan(s['body'])) return true;
      }
      return false;
    }

    return scan((skill['steps'] as Map?)?['main']);
  }

  /// Structural plan diff (Spec 02 §4.2): same ordered deletes; same ordered
  /// writes comparing op target + resolved field values, IGNORING
  /// interpreter-minted create ids (fresh each resolve) — including where a
  /// minted id feeds another write's entityRef field (normalized positionally).
  bool _samePlan(Plan held, Plan fresh) {
    if (held.deletes.length != fresh.deletes.length || held.writes.length != fresh.writes.length) {
      return false;
    }
    for (var i = 0; i < held.deletes.length; i++) {
      if (held.deletes[i] != fresh.deletes[i]) return false;
    }
    final ma = _mintMap(held), mb = _mintMap(fresh);
    for (var i = 0; i < held.writes.length; i++) {
      final wa = held.writes[i], wb = fresh.writes[i];
      final aCreate = ma.containsKey(wa['id']), bCreate = mb.containsKey(wb['id']);
      if (aCreate != bCreate) return false; // an update became a create, or vice versa
      if (!aCreate && wa['id'] != wb['id']) return false; // update targets must match
      final fa = _normalize(Map<String, dynamic>.of(wa)..remove('id'), ma);
      final fb = _normalize(Map<String, dynamic>.of(wb)..remove('id'), mb);
      if (!_deepEq(fa, fb)) return false;
    }
    return true;
  }

  // ids minted by this plan (not in the store) -> positional placeholder
  Map<String, String> _mintMap(Plan p) {
    final m = <String, String>{};
    for (var i = 0; i < p.writes.length; i++) {
      final id = p.writes[i]['id'];
      if (id is String && !store.containsKey(id)) m[id] = '<new-$i>';
    }
    return m;
  }

  static dynamic _normalize(dynamic v, Map<String, String> mints) {
    if (v is String) return mints[v] ?? v;
    if (v is Map) return {for (final e in v.entries) e.key: _normalize(e.value, mints)};
    if (v is List) return [for (final x in v) _normalize(x, mints)];
    return v;
  }

  static bool _deepEq(dynamic a, dynamic b) {
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final k in a.keys) {
        if (!b.containsKey(k) || !_deepEq(a[k], b[k])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEq(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}
