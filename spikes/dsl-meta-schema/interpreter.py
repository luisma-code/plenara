"""THROWAWAY Phase-0 spike interpreter — validates DSL/meta-schema VIABILITY.

Proves the closed-vocab Skill DSL (data) can express and deterministically execute
diverse tasks against data-defined types. NOT production code; no persistence, no
undo journal, minimal error surfaces. The point is to find dead-ends in the DSL /
meta-schema design before committing to the real Dart codebase.

Two-phase, per Spec 02: resolve() is a PURE function of (skill, slots, store) that
mints ids, evaluates control flow, validates every write against its type schema,
and returns a flat, concrete action plan — WITHOUT mutating the store. execute()
then applies that plan. This spike specifically tests that the resolve/execute
split survives real branch/foreach control flow.
"""
import re
from datetime import datetime, timedelta, date


class ResolveError(Exception):
    pass


class Interpreter:
    def __init__(self, types, now):
        self.types = types          # {typeId: typedef}
        self.now = now              # frozen system input (a datetime)
        self._idc = 0

    def _mint(self, type_id):
        self._idc += 1
        return f"{type_id}-{self._idc:04d}"

    # ---- value + expression evaluation (closed vocabulary) ------------------
    def val(self, v, env):
        if isinstance(v, dict):
            if "var" in v:
                return env.get(v["var"])
            if "ref" in v:                       # entityRef -> the record's id
                rec = env.get(v["ref"])
                return rec["id"] if rec else None
            if "field" in v:                     # [recordVar, attr]
                recname, attr = v["field"]
                rec = env.get(recname)
                return rec.get(attr) if isinstance(rec, dict) else None
            if "fn" in v:
                return self.compute(v["fn"], v.get("args", []), env)
        return v                                 # literal

    def compute(self, fn, args, env):
        a = [self.val(x, env) for x in args]
        if fn == "now":
            return self.now.isoformat()
        if fn == "today":
            return self.now.date().isoformat()
        if fn == "format_date":
            d, fmt = self._as_date(a[0]), a[1]
            if d is None:
                return None
            return d.strftime("%A") if fmt == "EEEE" else d.isoformat()
        if fn == "start_of_week":
            d = self._as_date(a[0])
            return (d - timedelta(days=d.weekday())).isoformat()
        if fn == "add":
            return (a[0] or 0) + (a[1] or 0)
        if fn == "count":
            return len(a[0] or [])
        raise ResolveError(f"unknown compute fn '{fn}'")

    @staticmethod
    def _as_date(s):
        if not s:
            return None
        try:
            return date.fromisoformat(s[:10])
        except ValueError:
            return None

    def cond(self, c, env):
        if "isNull" in c:
            return env.get(c["isNull"]) is None
        if "notNull" in c:
            return env.get(c["notNull"]) is not None
        if "gte" in c:
            a, b = (self.val(x, env) for x in c["gte"])
            return str(a) >= str(b)
        if "eq" in c:
            a, b = (self.val(x, env) for x in c["eq"])
            return a == b
        raise ResolveError(f"unknown cond {c}")

    # ---- static validation (authoring-time gate; Spec 02 §6.4) -------------
    def validate_skill(self, skill):
        """Static semantic validation. The load-bearing check (G-17): an `entity`
        field must be fed by a RECORD reference (`{ref: recordVar}` or
        `{field:[recordVar,'id']}`), NEVER a raw input `{var}` — because at runtime
        a resolved id and a raw name are BOTH strings, so this is only catchable
        statically, on the skill definition, before it ever runs. (Spike finding.)"""
        inputs = {i["name"] for i in skill.get("inputs", [])}
        self._validate(skill["steps"]["main"], set(), inputs, skill.get("skillId", "?"))

    def _validate(self, steps, record_vars, inputs, sid):
        for step in steps:
            op = step["op"]
            if op == "write_record":
                td = self.types[step["typeId"]]
                entity_fields = {a["name"] for a in td["attributes"] if a["valueType"] == "entity"}
                for fname, fval in step["fields"].items():
                    if fname not in entity_fields:
                        continue
                    ok = isinstance(fval, dict) and (
                        (fval.get("ref") in record_vars) or
                        ("field" in fval and fval["field"][0] in record_vars and fval["field"][1] == "id"))
                    if not ok:
                        raise ResolveError(
                            f"{sid}: entity field '{step['typeId']}.{fname}' is fed by {fval}, not a "
                            f"resolved record reference — a raw value cannot be a valid entityRef; "
                            f"resolve it via read_one/entityNames first (G-17, static)")
                if "into" in step:
                    record_vars.add(step["into"])
            elif op == "read_one" and "into" in step:
                record_vars.add(step["into"])
            elif op == "branch":
                self._validate(step.get("then", []), record_vars, inputs, sid)
                self._validate(step.get("else", []), record_vars, inputs, sid)
            elif op == "foreach":
                scoped = set(record_vars)
                scoped.add(step["as"])          # loop var is a record (read_many element)
                self._validate(step["body"], scoped, inputs, sid)

    # ---- resolve (pure; no store mutation) ---------------------------------
    def resolve(self, skill, slots, store):
        env = dict(slots)
        plan = {"writes": [], "before_images": [], "confirmation": None}
        self._run(skill["steps"]["main"], env, store, plan)
        return plan, env

    def _run(self, steps, env, store, plan):
        for step in steps:
            self._op(step, env, store, plan)

    def _op(self, step, env, store, plan):
        op = step["op"]
        if op == "compute":
            env[step["into"]] = self.compute(step["fn"], step.get("args", []), env)
        elif op == "set":
            env[step["var"]] = self.val(step["value"], env)
        elif op == "format":
            out = re.sub(r"\{(\w+)\}",
                         lambda m: str(env.get(m.group(1), "{" + m.group(1) + "}")),
                         step["template"])
            env[step["into"]] = out
            if step["into"] == "confirmation":
                plan["confirmation"] = out
        elif op == "read_one":
            match = {k: self.val(v, env) for k, v in step["match"].items()}
            hits = [r for r in store.values()
                    if r["typeId"] == step["typeId"]
                    and all(r.get(k) == v for k, v in match.items())]
            if len(hits) > 1:
                raise ResolveError(f"read_one {step['typeId']} {match} matched {len(hits)} (ambiguous — G-12)")
            env[step["into"]] = hits[0] if hits else None
        elif op == "read_many":
            recs = [r for r in store.values() if r["typeId"] == step["typeId"]]
            f = step.get("filter")
            if f:
                recs = [r for r in recs if self._match_filter(r, f)]
            env[step["into"]] = recs
        elif op == "write_record":
            env[step["into"]] = self._resolve_write(step, env, plan)
        elif op == "branch":
            branch = step.get("then", []) if self.cond(step["cond"], env) else step.get("else", [])
            self._run(branch, env, store, plan)
        elif op == "foreach":
            for item in (self.val(step["list"], env) or []):
                env[step["as"]] = item
                self._run(step["body"], env, store, plan)
        else:
            raise ResolveError(f"unknown op '{op}'")

    def _resolve_write(self, step, env, plan):
        type_id = step["typeId"]
        td = self.types[type_id]
        fields = {k: self.val(v, env) for k, v in step["fields"].items()}
        # schema defaults
        for a in td["attributes"]:
            if fields.get(a["name"]) is None and "default" in a:
                fields[a["name"]] = a["default"]
        # validation (the deterministic gate — Spec 02 §6.4 / G-17)
        for a in td["attributes"]:
            name, val = a["name"], fields.get(a["name"])
            if a.get("required") and val is None:
                raise ResolveError(f"write {type_id}: required '{name}' missing (schema validation)")
            if a["valueType"] == "entity" and val is not None and not isinstance(val, str):
                raise ResolveError(f"write {type_id}: entityRef '{name}' must be a resolved id, "
                                   f"got {type(val).__name__} (semantic validation — G-17)")
        rec = {"id": self._mint(type_id), "typeId": type_id, **fields}
        plan["writes"].append(rec)
        plan["before_images"].append({"id": rec["id"], "before": None})   # create
        return rec

    @staticmethod
    def _match_filter(r, f):
        v = r.get(f["field"])
        return v == f["value"] if f["op"] == "eq" else True

    # ---- execute (applies the resolved plan) -------------------------------
    @staticmethod
    def execute(plan, store):
        for rec in plan["writes"]:
            store[rec["id"]] = dict(rec)
        return plan
