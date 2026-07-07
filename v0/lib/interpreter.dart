/// Plenara v0 — the Skill Interpreter (Spec 02), ported from the validated
/// Phase-0 spike. Two phases: [resolve] is pure over (skill, slots, store) and
/// returns a concrete plan without mutating the store; [execute] applies it.
/// [validateSkill] is the authoring-time static gate (Spec 02 §6.4, incl. G-17).
library;

import 'dart:math';

class ResolveError implements Exception {
  final String message;
  ResolveError(this.message);
  @override
  String toString() => 'ResolveError: $message';
}

typedef Record = Map<String, dynamic>; // flat: {id, typeId, <field>: <value>...}
typedef TypeDef = Map<String, dynamic>;
typedef Skill = Map<String, dynamic>;

class Plan {
  final List<Record> writes = [];
  final List<String> deletes = []; // record ids to tombstone
  String? confirmation;
}

/// Mutable accumulator threaded through static validation.
class _VCtx {
  final String sid;
  bool setsConfirmation = false;
  _VCtx(this.sid);
}

class Interpreter {
  final Map<String, TypeDef> types;
  final DateTime now;
  final Random _rng;
  Interpreter(this.types, this.now, {Random? rng}) : _rng = rng ?? Random();

  /// Mint a globally-unique record id (Spec 02 §4.4). A UUID-v4 with a typeId
  /// prefix: unique across process restarts AND across devices, so a later
  /// session (or a second device) can never collide with a persisted record and
  /// silently overwrite it. (A per-session sequential counter did exactly that.)
  String _mint(String typeId) {
    final b = List<int>.generate(16, (_) => _rng.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40; // version 4
    b[8] = (b[8] & 0x3f) | 0x80; // variant
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '$typeId-${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
        '${h.substring(16, 20)}-${h.substring(20)}';
  }

  // ---- value + expression evaluation (closed vocabulary) -------------------
  dynamic val(dynamic v, Map<String, dynamic> env) {
    if (v is Map) {
      if (v.containsKey('var')) return env[v['var']];
      if (v.containsKey('ref')) {
        final rec = env[v['ref']];
        return rec == null ? null : rec['id'];
      }
      if (v.containsKey('field')) {
        final f = v['field'] as List;
        final rec = env[f[0]];
        return rec is Map ? rec[f[1]] : null;
      }
      if (v.containsKey('fn')) {
        return compute(v['fn'] as String, (v['args'] ?? []) as List, env);
      }
    }
    return v; // literal
  }

  dynamic compute(String fn, List args, Map<String, dynamic> env) {
    final a = args.map((x) => val(x, env)).toList();
    switch (fn) {
      case 'now':
        return now.toIso8601String();
      case 'today':
        return _dateOnly(now);
      case 'format_date':
        final d = _asDate(a[0]);
        if (d == null) return null;
        return a[1] == 'EEEE' ? _weekday(d) : _dateOnly(d);
      case 'start_of_week':
        final d = _asDate(a[0])!;
        return _dateOnly(d.subtract(Duration(days: d.weekday - 1)));
      case 'add':
        return (a[0] ?? 0) + (a[1] ?? 0);
      case 'count':
        return (a[0] as List?)?.length ?? 0;
      case 'concat':
        return a.map((x) => x?.toString() ?? '').join();
      default:
        throw ResolveError("unknown compute fn '$fn'");
    }
  }

  static const _days = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'
  ];
  static String _weekday(DateTime d) => _days[d.weekday - 1];
  static String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  static DateTime? _asDate(dynamic s) {
    if (s == null) return null;
    final str = s.toString();
    // never throw: only take the date prefix when it's actually there. A stray
    // non-date slot (e.g. a leaked "none" from the cloud) parses to null, not a crash.
    return DateTime.tryParse(str.length >= 10 ? str.substring(0, 10) : str);
  }

  bool cond(Map c, Map<String, dynamic> env) {
    if (c.containsKey('isNull')) return env[c['isNull']] == null;
    if (c.containsKey('notNull')) return env[c['notNull']] != null;
    if (c.containsKey('gte')) {
      final ab = (c['gte'] as List).map((x) => val(x, env)).toList();
      final a = ab[0], b = ab[1];
      if (a is num && b is num) return a >= b;
      // numeric when both look numeric; else lexical (correct for fixed-width ISO dates)
      final an = num.tryParse(a.toString()), bn = num.tryParse(b.toString());
      if (an != null && bn != null) return an >= bn;
      return a.toString().compareTo(b.toString()) >= 0;
    }
    if (c.containsKey('eq')) {
      final ab = (c['eq'] as List).map((x) => val(x, env)).toList();
      return ab[0] == ab[1];
    }
    throw ResolveError('unknown cond $c');
  }

  // ---- static validation (authoring-time gate; Spec 02 §6.4) --------------
  static const _ops = {'read_one', 'read_many', 'write_record', 'delete_record', 'compute', 'set', 'format', 'branch', 'foreach'};
  static const _fns = {'now', 'today', 'format_date', 'start_of_week', 'add', 'count', 'concat'};
  static const _valueTypes = {'text', 'date', 'datetime', 'decimal', 'integer', 'boolean', 'entity', 'enum'};

  /// Validate an authored TYPE def (Spec 01 §3). Throws ResolveError (never a
  /// raw TypeError) so the authoring retry loop can catch it.
  void validateType(Map<String, dynamic> type) {
    final tid = type['typeId'];
    if (tid is! String) throw ResolveError('type must have a string typeId');
    final attrs = type['attributes'];
    if (attrs is! List) throw ResolveError("type '$tid': attributes must be a list");
    for (final a in attrs) {
      if (a is! Map || a['name'] is! String) throw ResolveError("type '$tid': each attribute needs a name");
      if (!_valueTypes.contains(a['valueType'])) {
        throw ResolveError("type '$tid': attribute '${a['name']}' has unknown valueType '${a['valueType']}'");
      }
      if (a['valueType'] == 'entity' && a['refType'] is! String) {
        throw ResolveError("type '$tid': entity attribute '${a['name']}' needs a refType");
      }
    }
  }

  /// The authoring gate. Total over arbitrary JSON (raises ResolveError, never a
  /// raw Error), whitelists the closed op/fn vocabulary, checks every entity
  /// field traces to a resolved record reference of the right refType on ALL
  /// paths (G-17, branch-sound), and requires a confirmation to be produced.
  void validateSkill(Skill skill) {
    final sid = skill['skillId']?.toString() ?? '?';
    final steps = skill['steps'];
    if (steps is! Map || steps['main'] is! List) {
      throw ResolveError("$sid: skill must have steps.main (a list of ops)");
    }
    final c = _VCtx(sid);
    _validate(steps['main'] as List, <String, String?>{}, <String, String?>{}, c);
    if (!c.setsConfirmation) {
      throw ResolveError("$sid: no step produces a 'confirmation' (a format op into confirmation is required)");
    }
  }

  // recVars: var -> typeId of a resolved RECORD; listVars: var -> element typeId of a read_many LIST.
  void _validate(List steps, Map<String, String?> recVars, Map<String, String?> listVars, _VCtx c) {
    for (final raw in steps) {
      if (raw is! Map) throw ResolveError("${c.sid}: a step must be an object, got $raw");
      final step = raw;
      final op = step['op'];
      if (!_ops.contains(op)) {
        throw ResolveError("${c.sid}: unknown op '$op' (closed vocabulary: ${_ops.join(', ')})");
      }
      switch (op) {
        case 'compute':
          if (!_fns.contains(step['fn'])) throw ResolveError("${c.sid}: unknown compute fn '${step['fn']}'");
        case 'read_one':
          final tid = step['typeId'];
          if (!types.containsKey(tid)) throw ResolveError("${c.sid}: read_one unknown type '$tid'");
          if (step['into'] is String) recVars[step['into'] as String] = tid as String;
        case 'read_many':
          final tid = step['typeId'];
          if (!types.containsKey(tid)) throw ResolveError("${c.sid}: read_many unknown type '$tid'");
          final f = step['filter'];
          if (f != null && f['op'] != 'eq') throw ResolveError("${c.sid}: read_many unsupported filter op '${f['op']}'");
          if (step['into'] is String) listVars[step['into'] as String] = tid as String;
        case 'write_record':
          final tid = step['typeId'];
          final td = types[tid];
          if (td == null) throw ResolveError("${c.sid}: write_record unknown type '$tid'");
          final entity = <String, dynamic>{
            for (final a in ((td['attributes'] as List?) ?? []))
              if (a is Map && a['valueType'] == 'entity') a['name'] as String: a['refType']
          };
          ((step['fields'] as Map?) ?? {}).forEach((name, fval) {
            if (!entity.containsKey(name)) return;
            String? srcVar;
            if (fval is Map && fval['ref'] is String) {
              srcVar = fval['ref'] as String;
            } else if (fval is Map &&
                fval['field'] is List &&
                (fval['field'] as List).length == 2 &&
                (fval['field'] as List)[1] == 'id') {
              srcVar = (fval['field'] as List)[0] as String;
            }
            if (srcVar == null || !recVars.containsKey(srcVar)) {
              throw ResolveError("${c.sid}: entity field '$tid.$name' must be fed by a resolved record "
                  "reference (read_one/write_record → {ref}), not $fval (G-17, static)");
            }
            final refType = entity[name], srcType = recVars[srcVar];
            if (refType is String && srcType != null && srcType != refType) {
              throw ResolveError("${c.sid}: entity field '$tid.$name' expects a $refType, but '$srcVar' is a $srcType");
            }
          });
          if (step['into'] is String) recVars[step['into'] as String] = tid as String;
        case 'delete_record':
          if (step['id'] == null) throw ResolveError("${c.sid}: delete_record needs an 'id'");
        case 'format':
          if (step['into'] == 'confirmation') c.setsConfirmation = true;
        case 'branch':
          final tRec = Map<String, String?>.from(recVars), eRec = Map<String, String?>.from(recVars);
          final tList = Map<String, String?>.from(listVars), eList = Map<String, String?>.from(listVars);
          _validate((step['then'] as List?) ?? const [], tRec, tList, c);
          _validate((step['else'] as List?) ?? const [], eRec, eList, c);
          // only bindings resolved on BOTH paths (same type) survive the branch
          for (final k in tRec.keys) {
            if (!recVars.containsKey(k) && eRec.containsKey(k) && eRec[k] == tRec[k]) recVars[k] = tRec[k];
          }
        case 'foreach':
          final listExpr = step['list'];
          final elemType = (listExpr is Map && listExpr['var'] is String) ? listVars[listExpr['var']] : null;
          final scoped = Map<String, String?>.from(recVars);
          if (step['as'] is String) scoped[step['as'] as String] = elemType;
          _validate((step['body'] as List?) ?? const [], scoped, Map<String, String?>.from(listVars), c);
        case 'set':
          break;
      }
    }
  }

  // ---- resolve (pure; no store mutation) ----------------------------------
  Plan resolve(Skill skill, Map<String, dynamic> slots, Map<String, Record> store) {
    final env = Map<String, dynamic>.from(slots);
    final plan = Plan();
    _run(skill['steps']['main'] as List, env, store, plan);
    return plan;
  }

  void _run(List steps, Map<String, dynamic> env, Map<String, Record> store, Plan plan) {
    for (final step in steps) {
      _op(step as Map, env, store, plan);
    }
  }

  void _op(Map step, Map<String, dynamic> env, Map<String, Record> store, Plan plan) {
    switch (step['op']) {
      case 'compute':
        env[step['into']] = compute(step['fn'], (step['args'] ?? []) as List, env);
      case 'set':
        env[step['var']] = val(step['value'], env);
      case 'format':
        final out = (step['template'] as String).replaceAllMapped(
            RegExp(r'\{(\w+)\}'), (m) => '${env[m.group(1)] ?? '{${m.group(1)}}'}');
        env[step['into']] = out;
        if (step['into'] == 'confirmation') plan.confirmation = out;
      case 'read_one':
        final match = {
          for (final e in (step['match'] as Map).entries) e.key: val(e.value, env)
        };
        final hits = store.values
            .where((r) =>
                r['typeId'] == step['typeId'] &&
                match.entries.every((e) {
                  final rv = r[e.key], mv = e.value;
                  // case-insensitive name resolution: "mia" finds "Mia" (voice
                  // transcripts vary in case), so we don't create a duplicate contact
                  return (rv is String && mv is String) ? rv.toLowerCase() == mv.toLowerCase() : rv == mv;
                }))
            .toList();
        if (hits.length > 1) {
          throw ResolveError(
              "read_one ${step['typeId']} $match matched ${hits.length} (ambiguous — G-12)");
        }
        env[step['into']] = hits.isEmpty ? null : hits.first;
      case 'read_many':
        var recs = store.values.where((r) => r['typeId'] == step['typeId']).toList();
        final f = step['filter'];
        if (f != null) {
          if (f['op'] != 'eq') {
            // an unknown filter op must fail loudly — silently matching everything
            // would turn a wrong filter into a mass write (no silent failure, P7)
            throw ResolveError("read_many: unsupported filter op '${f['op']}' (only 'eq')");
          }
          final fv = val(f['value'], env); // resolve {var}/{ref}/literal -> dynamic filters
          recs = recs.where((r) => r[f['field']] == fv).toList();
        }
        env[step['into']] = recs;
      case 'write_record':
        env[step['into']] = _resolveWrite(step, env, store, plan);
      case 'delete_record':
        final id = val(step['id'], env);
        if (id is String && store.containsKey(id)) plan.deletes.add(id);
      case 'branch':
        _run((cond(step['cond'] as Map, env) ? step['then'] : step['else']) ?? [], env, store, plan);
      case 'foreach':
        for (final item in (val(step['list'], env) as List? ?? [])) {
          env[step['as']] = item;
          _run(step['body'] as List, env, store, plan);
        }
      default:
        throw ResolveError("unknown op '${step['op']}'");
    }
  }

  Record _resolveWrite(Map step, Map<String, dynamic> env, Map<String, Record> store, Plan plan) {
    final typeId = step['typeId'] as String;
    final td = types[typeId]!;
    final fields = <String, dynamic>{
      for (final e in (step['fields'] as Map).entries) e.key: val(e.value, env)
    };
    Record rec;
    final target = step['target']; // {ref: recVar} / an id expr -> UPDATE the existing record
    if (target != null) {
      final id = val(target, env);
      final existing = id == null ? null : store[id];
      if (existing == null) throw ResolveError("write $typeId: update target '$id' not found");
      // merge: keep existing fields, overlay the new ones (id-based upsert, Spec 02 §3.2)
      rec = <String, dynamic>{...existing, ...fields, 'id': existing['id'], 'typeId': typeId};
    } else {
      for (final a in (td['attributes'] as List)) {
        if (fields[a['name']] == null && a.containsKey('default')) fields[a['name']] = a['default'];
      }
      for (final a in (td['attributes'] as List)) {
        if (a['required'] == true && fields[a['name']] == null) {
          throw ResolveError("write $typeId: required '${a['name']}' missing (schema validation)");
        }
      }
      rec = <String, dynamic>{'id': _mint(typeId), 'typeId': typeId, ...fields};
    }
    plan.writes.add(rec);
    return rec;
  }

  /// Applies the plan and returns the before-images (Spec 02 §5.4): recordId ->
  /// prior state, or null when the write created the record. This is what makes
  /// `undo` deterministic and reliable — the safety net act-then-describe rests on.
  Map<String, Map<String, dynamic>?> execute(Plan plan, Map<String, Record> store) {
    final before = <String, Map<String, dynamic>?>{};
    for (final rec in plan.writes) {
      final id = rec['id'] as String;
      before[id] = store.containsKey(id) ? Map<String, dynamic>.from(store[id]!) : null;
      store[id] = Map<String, dynamic>.from(rec);
    }
    for (final id in plan.deletes) {
      before[id] = store.containsKey(id) ? Map<String, dynamic>.from(store[id]!) : null;
      store.remove(id); // the before-image (the deleted record) lets undo restore it
    }
    return before;
  }
}
