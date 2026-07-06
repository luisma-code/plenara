/// Plenara v0 — the Skill Interpreter (Spec 02), ported from the validated
/// Phase-0 spike. Two phases: [resolve] is pure over (skill, slots, store) and
/// returns a concrete plan without mutating the store; [execute] applies it.
/// [validateSkill] is the authoring-time static gate (Spec 02 §6.4, incl. G-17).
library;

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
  String? confirmation;
}

class Interpreter {
  final Map<String, TypeDef> types;
  final DateTime now;
  int _idc = 0;
  Interpreter(this.types, this.now);

  String _mint(String typeId) =>
      '$typeId-${(++_idc).toString().padLeft(4, '0')}';

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
    return DateTime.tryParse(s.toString().substring(0, 10));
  }

  bool cond(Map c, Map<String, dynamic> env) {
    if (c.containsKey('isNull')) return env[c['isNull']] == null;
    if (c.containsKey('notNull')) return env[c['notNull']] != null;
    if (c.containsKey('gte')) {
      final ab = (c['gte'] as List).map((x) => val(x, env)).toList();
      return ab[0].toString().compareTo(ab[1].toString()) >= 0;
    }
    if (c.containsKey('eq')) {
      final ab = (c['eq'] as List).map((x) => val(x, env)).toList();
      return ab[0] == ab[1];
    }
    throw ResolveError('unknown cond $c');
  }

  // ---- static validation (authoring-time gate; G-17) ----------------------
  void validateSkill(Skill skill) {
    _validate((skill['steps']['main'] as List), <String>{},
        skill['skillId']?.toString() ?? '?');
  }

  void _validate(List steps, Set<String> recordVars, String sid) {
    for (final step in steps) {
      final op = step['op'];
      if (op == 'write_record') {
        final td = types[step['typeId']]!;
        final entity = {
          for (final a in (td['attributes'] as List))
            if (a['valueType'] == 'entity') a['name']
        };
        (step['fields'] as Map).forEach((name, fval) {
          if (!entity.contains(name)) return;
          final ok = fval is Map &&
              ((recordVars.contains(fval['ref'])) ||
                  (fval.containsKey('field') &&
                      recordVars.contains((fval['field'] as List)[0]) &&
                      (fval['field'] as List)[1] == 'id'));
          if (!ok) {
            throw ResolveError(
                "$sid: entity field '${step['typeId']}.$name' is fed by $fval, not a "
                "resolved record reference — resolve it via read_one first (G-17, static)");
          }
        });
        if (step.containsKey('into')) recordVars.add(step['into']);
      } else if (op == 'read_one' && step.containsKey('into')) {
        recordVars.add(step['into']);
      } else if (op == 'branch') {
        _validate((step['then'] ?? []) as List, recordVars, sid);
        _validate((step['else'] ?? []) as List, recordVars, sid);
      } else if (op == 'foreach') {
        final scoped = {...recordVars, step['as'] as String};
        _validate(step['body'] as List, scoped, sid);
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
                match.entries.every((e) => r[e.key] == e.value))
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
          final fv = val(f['value'], env); // resolve {var}/{ref}/literal -> dynamic filters
          recs = recs.where((r) => f['op'] == 'eq' ? r[f['field']] == fv : true).toList();
        }
        env[step['into']] = recs;
      case 'write_record':
        env[step['into']] = _resolveWrite(step, env, plan);
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

  Record _resolveWrite(Map step, Map<String, dynamic> env, Plan plan) {
    final typeId = step['typeId'] as String;
    final td = types[typeId]!;
    final fields = <String, dynamic>{
      for (final e in (step['fields'] as Map).entries) e.key: val(e.value, env)
    };
    for (final a in (td['attributes'] as List)) {
      if (fields[a['name']] == null && a.containsKey('default')) {
        fields[a['name']] = a['default'];
      }
    }
    for (final a in (td['attributes'] as List)) {
      final name = a['name'], v = fields[name];
      if (a['required'] == true && v == null) {
        throw ResolveError("write $typeId: required '$name' missing (schema validation)");
      }
    }
    final rec = <String, dynamic>{'id': _mint(typeId), 'typeId': typeId, ...fields};
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
    return before;
  }
}
