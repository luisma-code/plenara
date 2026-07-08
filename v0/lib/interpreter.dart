/// Plenara v0 — the Skill Interpreter (Spec 02), ported from the validated
/// Phase-0 spike. Two phases: [resolve] is pure over (skill, slots, store) and
/// returns a concrete plan without mutating the store; [execute] applies it.
/// [validateSkill] is the authoring-time static gate (Spec 02 §6.4, incl. G-17).
library;

import 'dart:math';

import 'dates.dart';

class ResolveError implements Exception {
  final String message;
  /// Candidate labels when the failure is an AMBIGUITY (G-12) — lets the caller ask
  /// the user which one instead of leaking a raw error.
  final List<String>? options;
  ResolveError(this.message, {this.options});
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
  final Set<String> readTypes = {}; // types actually read (for the capability closure)
  final Set<String> writeTypes = {}; // types actually written
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
      case 'format_time':
        final d = _asDateTime(a[0]);
        if (d == null) return null;
        final h12 = d.hour % 12 == 0 ? 12 : d.hour % 12;
        return '$h12:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
      case 'next_annual':
        // next occurrence of this date's MM-DD on/after today (for birthdays etc.)
        final d = _asDate(a[0]);
        return d == null ? null : _dateOnly(nextAnnual(d, now));
      case 'days_until_annual':
        final d = _asDate(a[0]);
        return d == null ? null : daysUntilAnnual(d, now);
      case 'current_streak':
        // consecutive days (ending today, or yesterday if today is blank) that the
        // list has a record for — the motivating "you're on an N-day streak".
        final days = _daysSet(a[0], a[1]);
        var t = _epochDay(now);
        if (!days.contains(t)) {
          if (days.contains(t - 1)) t -= 1; else return 0;
        }
        var n = 0;
        while (days.contains(t)) { n++; t -= 1; }
        return n;
      case 'longest_streak':
        final days = (_daysSet(a[0], a[1]).toList())..sort();
        if (days.isEmpty) return 0;
        var best = 1, cur = 1;
        for (var i = 1; i < days.length; i++) {
          cur = days[i] == days[i - 1] + 1 ? cur + 1 : 1;
          if (cur > best) best = cur;
        }
        return best;
      case 'start_of_week':
        final d = _asDate(a[0])!;
        return _dateOnly(d.subtract(Duration(days: d.weekday - 1)));
      case 'add':
        return (a[0] ?? 0) + (a[1] ?? 0);
      case 'mul':
        return (a[0] is num && a[1] is num) ? (a[0] as num) * (a[1] as num) : null;
      case 'div':
        // guarded: divide-by-zero (or a non-number) -> null, never a crash/Infinity
        return (a[0] is num && a[1] is num && (a[1] as num) != 0) ? (a[0] as num) / (a[1] as num) : null;
      case 'round':
        return a[0] is num ? (a[0] as num).round() : null;
      case 'days_between':
        final d1 = _asDate(a[0]), d2 = _asDate(a[1]);
        return (d1 == null || d2 == null) ? null : d2.difference(d1).inDays;
      case 'add_days':
        final d = _asDate(a[0]);
        return d == null || a[1] is! num ? null : _dateOnly(d.add(Duration(days: (a[1] as num).toInt())));
      case 'count':
        return (a[0] as List?)?.length ?? 0;
      case 'count_where':
        // count records in list a[0] whose field a[1] equals value a[2]
        return ((a[0] as List?) ?? []).where((r) => r is Map && r[a[1]] == a[2]).length;
      case 'sum':
        return _nums(a[0], a[1]).fold<num>(0, (s, x) => s + x);
      case 'avg':
        final ns = _nums(a[0], a[1]);
        return ns.isEmpty ? null : ns.reduce((s, x) => s + x) / ns.length; // no data -> null, not a misleading 0 (spec §3.7)
      case 'min':
        final ns = _nums(a[0], a[1]);
        return ns.isEmpty ? null : ns.reduce((x, y) => x < y ? x : y);
      case 'max':
        final ns = _nums(a[0], a[1]);
        return ns.isEmpty ? null : ns.reduce((x, y) => x > y ? x : y);
      case 'if':
        // ternary over a boolean value: if(flag, whenTrue, whenFalse)
        return a[0] == true ? a[1] : a[2];
      case 'concat':
        return a.map((x) => x?.toString() ?? '').join();
      case 'ordinal_num':
        // an ordinal WORD -> its number (1..4), or -1 for "last" — for monthly recurrence math.
        return switch ((a.isEmpty ? '' : '${a[0]}').toLowerCase().trim()) {
          'first' || '1st' || 'one' => 1,
          'second' || '2nd' || 'two' => 2,
          'third' || '3rd' || 'three' => 3,
          'fourth' || '4th' || 'four' => 4,
          'last' => -1,
          _ => 1,
        };
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

  // full datetime (keeps the time-of-day; used by format_time). Never throws.
  static DateTime? _asDateTime(dynamic s) => s == null ? null : DateTime.tryParse(s.toString());

  // day number in UTC (no DST) so consecutive calendar days differ by exactly 1.
  static int _epochDay(DateTime d) => DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;
  // numeric values of [field] across a record list (parses numeric strings; skips non-numbers).
  static List<num> _nums(dynamic list, dynamic field) {
    final out = <num>[];
    if (list is List) {
      for (final r in list) {
        final v = (r is Map) ? r[field] : null;
        final n = v is num ? v : num.tryParse(v?.toString() ?? '');
        if (n != null) out.add(n);
      }
    }
    return out;
  }

  // ordering/filter comparison: numeric when both look numeric, else lexical (ISO dates sort right).
  static int _cmp(dynamic a, dynamic b) {
    if (a == null && b == null) return 0;
    if (a == null) return -1;
    if (b == null) return 1;
    if (a is num && b is num) return a.compareTo(b);
    final an = num.tryParse(a.toString()), bn = num.tryParse(b.toString());
    if (an != null && bn != null) return an.compareTo(bn);
    return a.toString().compareTo(b.toString());
  }

  // the set of distinct day-numbers a record list occupies on [field].
  static Set<int> _daysSet(dynamic list, dynamic field) {
    final out = <int>{};
    if (list is List) {
      for (final r in list) {
        if (r is Map) {
          final dt = _asDate(r[field]);
          if (dt != null) out.add(_epochDay(dt));
        }
      }
    }
    return out;
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
    if (c.containsKey('contains')) {
      // case-insensitive substring test — lets a skill match "likes chess" within a
      // stored fact without the user repeating it verbatim. Empty needle never matches.
      final ab = (c['contains'] as List).map((x) => val(x, env)).toList();
      final hay = ab[0]?.toString().toLowerCase() ?? '';
      final needle = ab[1]?.toString().toLowerCase() ?? '';
      return needle.isNotEmpty && hay.contains(needle);
    }
    throw ResolveError('unknown cond $c');
  }

  // read_many filter predicate: {field, op, value?}. op defaults to eq.
  bool _filterMatch(Map f, Record r, Map<String, dynamic> env) {
    final op = (f['op'] ?? 'eq') as String;
    final rv = r[f['field']];
    if (op == 'isNull') return rv == null;
    if (op == 'notNull') return rv != null;
    final fv = val(f['value'], env);
    switch (op) {
      case 'eq':
        return rv == fv;
      case 'neq':
        return rv != fv;
      case 'gte':
        return _cmp(rv, fv) >= 0;
      case 'gt':
        return _cmp(rv, fv) > 0;
      case 'lte':
        return _cmp(rv, fv) <= 0;
      case 'lt':
        return _cmp(rv, fv) < 0;
      case 'contains':
        return rv is String && fv is String && rv.toLowerCase().contains(fv.toLowerCase());
      case 'in':
        return fv is List && fv.contains(rv);
      default:
        throw ResolveError("read_many: unsupported filter op '$op'");
    }
  }

  // ---- static validation (authoring-time gate; Spec 02 §6.4) --------------
  static const _ops = {'read_one', 'read_many', 'read_related', 'write_record', 'delete_record', 'compute', 'set', 'format', 'branch', 'foreach'};
  static const _fns = {'now', 'today', 'format_date', 'format_time', 'start_of_week', 'add', 'count', 'concat',
    'next_annual', 'days_until_annual', 'current_streak', 'longest_streak',
    'days_between', 'add_days', 'count_where', 'sum', 'avg', 'min', 'max', 'if', 'ordinal_num',
    'mul', 'div', 'round'};
  static const _filterOps = {'eq', 'neq', 'gt', 'gte', 'lt', 'lte', 'contains', 'in', 'isNull', 'notNull'};
  // The Spec 01 §3 canonical value-type set (fixed; a new one needs a kernel bump). `integer`
  // is retained only as a tolerated legacy alias for `number` (older authored types).
  static const _valueTypes = {
    'text', 'number', 'decimal', 'date', 'datetime', 'boolean',
    'duration', 'enum', 'entityRef', 'tag', 'attachment', 'json',
    'integer', // legacy alias -> number
  };

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
      if (a['valueType'] == 'entityRef' && a['refType'] is! String) {
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
      throw ResolveError("$sid: no step produces a 'confirmationText' (a format op into confirmationText is required)");
    }
    _checkVarClosure(steps['main'] as List, skill, sid);
    // capability closure (Spec 02 §6.4 rule 3): if the skill declares reads/writes,
    // it may not touch a type it didn't declare. Enforced-if-present.
    final declaredReads = (skill['reads'] as List?)?.map((e) => e.toString()).toSet();
    if (declaredReads != null) {
      final extra = c.readTypes.difference(declaredReads);
      if (extra.isNotEmpty) throw ResolveError("$sid: reads undeclared type(s) ${extra.join(', ')} — add to 'reads'");
    }
    final declaredWrites = (skill['writes'] as List?)?.map((e) => e.toString()).toSet();
    if (declaredWrites != null) {
      final extra = c.writeTypes.difference(declaredWrites);
      if (extra.isNotEmpty) throw ResolveError("$sid: writes undeclared type(s) ${extra.join(', ')} — add to 'writes'");
    }
  }

  // recVars: var -> typeId of a resolved RECORD; listVars: var -> element typeId of a read_many LIST.
  /// Static var-closure (Spec 02 §6.4 rule 4): every {var}/{field}/{ref} reference and
  /// every format placeholder must resolve to a bound name (an input, or a prior step's
  /// `into`/`set var`/`foreach as`). A typo'd `{persoName}` would otherwise pass the gate
  /// and silently render as empty at runtime — the exact silent failure P7 forbids, moved
  /// to authoring time. Conservative (bound-anywhere) so it never rejects a valid skill.
  void _checkVarClosure(List main, Skill skill, String sid) {
    final bound = <String>{};
    for (final i in (skill['inputs'] as List? ?? const [])) {
      if (i is Map && i['name'] is String) bound.add(i['name'] as String);
    }
    void collect(dynamic steps) {
      if (steps is! List) return;
      for (final s in steps) {
        if (s is! Map) continue;
        if (s['into'] is String) bound.add(s['into'] as String);
        if (s['op'] == 'set' && s['var'] is String) bound.add(s['var'] as String); // set's target binds
        if (s['op'] == 'foreach' && s['as'] is String) bound.add(s['as'] as String);
        collect(s['then']);
        collect(s['else']);
        collect(s['body']);
      }
    }

    collect(main);
    final refs = <String>{};
    void refsIn(dynamic node) {
      if (node is Map) {
        if (node['var'] is String) refs.add(node['var'] as String);
        if (node['ref'] is String) refs.add(node['ref'] as String);
        final f = node['field'];
        if (f is List && f.isNotEmpty && f.first is String) refs.add(f.first as String);
        node.forEach((k, v) {
          if (k != 'into' && k != 'as' && k != 'var') refsIn(v); // skip binding sites
        });
      } else if (node is List) {
        for (final e in node) {
          refsIn(e);
        }
      }
    }

    void scanRefs(dynamic steps) {
      if (steps is! List) return;
      for (final s in steps) {
        if (s is! Map) continue;
        if (s['op'] == 'format' && s['template'] is String) {
          for (final m in RegExp(r'\{(\w+)\}').allMatches(s['template'] as String)) {
            refs.add(m.group(1)!);
          }
        }
        final cond = s['cond'];
        if (cond is Map) {
          for (final key in const ['isNull', 'notNull']) {
            if (cond[key] is String) refs.add(cond[key] as String); // cond takes a bare var name
          }
          refsIn(cond);
        }
        for (final key in const ['value', 'args', 'fields', 'filter', 'list', 'from', 'match']) {
          refsIn(s[key]);
        }
        scanRefs(s['then']);
        scanRefs(s['else']);
        scanRefs(s['body']);
      }
    }

    scanRefs(main);
    for (final r in refs) {
      if (!bound.contains(r)) {
        throw ResolveError("$sid: references unbound variable '$r' "
            "(typo? not an input, a prior step's 'into'/'set', or a foreach 'as')");
      }
    }
  }

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
          c.readTypes.add(tid as String);
          if (step['into'] is String) recVars[step['into'] as String] = tid;
        case 'read_many':
          final tid = step['typeId'];
          if (!types.containsKey(tid)) throw ResolveError("${c.sid}: read_many unknown type '$tid'");
          c.readTypes.add(tid as String);
          final f = step['filter'];
          if (f != null && f['op'] != null && !_filterOps.contains(f['op'])) {
            throw ResolveError("${c.sid}: read_many unsupported filter op '${f['op']}' (${_filterOps.join('/')})");
          }
          if (step['orderDir'] != null && step['orderDir'] != 'asc' && step['orderDir'] != 'desc') {
            throw ResolveError("${c.sid}: read_many orderDir must be 'asc' or 'desc'");
          }
          if (step['limit'] != null && step['limit'] is! int) throw ResolveError("${c.sid}: read_many limit must be an int");
          if (step['into'] is String) listVars[step['into'] as String] = tid;
        case 'read_related':
          final tid = step['typeId'];
          if (!types.containsKey(tid)) throw ResolveError("${c.sid}: read_related unknown type '$tid'");
          if (step['via'] is! String) throw ResolveError("${c.sid}: read_related needs a 'via' attribute name");
          if (step['from'] == null) throw ResolveError("${c.sid}: read_related needs a 'from' record reference");
          c.readTypes.add(tid as String);
          if (step['into'] is String) listVars[step['into'] as String] = tid;
        case 'write_record':
          final tid = step['typeId'];
          final td = types[tid];
          if (td == null) throw ResolveError("${c.sid}: write_record unknown type '$tid'");
          c.writeTypes.add(tid as String);
          final entity = <String, dynamic>{
            for (final a in ((td['attributes'] as List?) ?? []))
              if (a is Map && a['valueType'] == 'entityRef') a['name'] as String: a['refType']
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
          if (step['into'] is String) recVars[step['into'] as String] = tid;
        case 'delete_record':
          if (step['id'] == null) throw ResolveError("${c.sid}: delete_record needs an 'id'");
        case 'format':
          if (step['into'] == 'confirmationText') c.setsConfirmation = true;
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
        // a null/absent var renders as empty (the spec's omitIfNull default) — never
        // leak a literal "{var}" into the user-facing string (no silent failure, P7).
        final out = (step['template'] as String).replaceAllMapped(
            RegExp(r'\{(\w+)\}'), (m) => '${env[m.group(1)] ?? ''}');
        env[step['into']] = out;
        if (step['into'] == 'confirmationText') plan.confirmation = out;
      case 'read_one':
        final match = {
          for (final e in (step['match'] as Map).entries) e.key: val(e.value, env)
        };
        bool matches(Record r, bool Function(String rv, String mv) strCmp) =>
            r['typeId'] == step['typeId'] &&
            match.entries.every((e) {
              final rv = r[e.key], mv = e.value;
              return (rv is String && mv is String) ? strCmp(rv.toLowerCase(), mv.toLowerCase()) : rv == mv;
            });
        // Exact (case-insensitive) resolution first — "mia" finds "Mia", never a
        // duplicate. With `partial:true` (people lookups), fall back to a substring
        // match so "Sam" finds "Sam Rivera" — surfacing a clarify when >1 qualifies.
        var hits = store.values.where((r) => matches(r, (rv, mv) => rv == mv)).toList();
        if (hits.isEmpty && step['partial'] == true) {
          hits = store.values.where((r) => matches(r, (rv, mv) => rv.contains(mv))).toList();
        }
        // alias tier (G-24): a record whose comma-separated `aliases` holds the match
        // value exactly (case-insensitive) — resolves "Mum", "my boss", "the wife".
        if (hits.isEmpty && step['partial'] == true && match['displayName'] is String) {
          final want = (match['displayName'] as String).toLowerCase().trim();
          hits = store.values.where((r) {
            if (r['typeId'] != step['typeId']) return false;
            final a = r['aliases'];
            return a is String && a.toLowerCase().split(',').map((s) => s.trim()).contains(want);
          }).toList();
        }
        if (hits.length > 1) {
          final labelField = (step['match'] as Map).keys.first as String;
          final labels = hits.map((h) => (h['displayName'] ?? h[labelField] ?? h['id']).toString()).toList();
          throw ResolveError(
              "read_one ${step['typeId']} $match matched ${hits.length} (ambiguous — G-12)",
              options: labels);
        }
        env[step['into']] = hits.isEmpty ? null : hits.first;
      case 'read_many':
        var recs = store.values.where((r) => r['typeId'] == step['typeId']).toList();
        final f = step['filter'];
        if (f != null) {
          final op = (f as Map)['op'] ?? 'eq';
          // fail loudly on a bad op even over an empty set (never silently match all)
          if (!_filterOps.contains(op)) throw ResolveError("read_many: unsupported filter op '$op'");
          recs = recs.where((r) => _filterMatch(f, r, env)).toList();
        }
        // orderBy <field> [orderDir asc|desc]
        final orderBy = step['orderBy'];
        if (orderBy is String) {
          final dir = step['orderDir'] == 'desc' ? -1 : 1;
          recs.sort((x, y) => dir * _cmp(x[orderBy], y[orderBy]));
        }
        // limit N (top-N after ordering)
        final limit = step['limit'];
        if (limit is int && limit >= 0 && recs.length > limit) recs = recs.sublist(0, limit);
        env[step['into']] = recs;
      case 'read_related':
        // records of typeId whose `via` entity attr points at the `from` record's id
        final fromId = val(step['from'], env);
        final via = step['via'] as String;
        env[step['into']] = store.values
            .where((r) => r['typeId'] == step['typeId'] && r[via] == fromId)
            .toList();
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
