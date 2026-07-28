#!/usr/bin/env python3
"""App Store Connect API client for Plenara's TestFlight releases.

Drives the parts of a release that used to need the App Store Connect web UI:
checking build processing state, wiring up the internal beta group, and
distributing a processed build to internal testers.

Auth is the same App Store Connect API key the upload script uses
(tool/.testflight.env). Requires the venv at ~/.plenara-asc/venv.

Usage:
  tool/asc.py status                 # app + latest builds + processing state
  tool/asc.py groups                 # beta groups and their testers
  tool/asc.py add-tester EMAIL       # add an internal tester to the internal group
  tool/asc.py invite EMAIL           # email that tester a TestFlight invite
  tool/asc.py release [BUILD]        # distribute a build (default: newest) to internal testers
  tool/asc.py raw PATH               # GET an arbitrary API path, for poking around
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

import jwt
import requests

API = "https://api.appstoreconnect.apple.com"
BUNDLE_ID = "com.plenara.plenaraApp"


def load_env():
    root = Path(
        subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip()
    )
    env_file = root / "tool" / ".testflight.env"
    env = {}
    if env_file.exists():
        for line in env_file.read_text().splitlines():
            line = line.strip()
            if line and not line.startswith("#") and "=" in line:
                k, v = line.split("=", 1)
                env[k.strip()] = v.strip()
    for k in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_KEY_PATH"):
        env.setdefault(k, os.environ.get(k, ""))
        if not env[k]:
            sys.exit(f"missing {k} — set it in tool/.testflight.env")
    return env


def token(env):
    key = Path(env["ASC_KEY_PATH"]).read_text()
    now = int(time.time())
    return jwt.encode(
        {
            "iss": env["ASC_ISSUER_ID"],
            "iat": now,
            "exp": now + 15 * 60,
            "aud": "appstoreconnect-v1",
        },
        key,
        algorithm="ES256",
        headers={"kid": env["ASC_KEY_ID"], "typ": "JWT"},
    )


class Client:
    def __init__(self):
        self.env = load_env()
        self.headers = {"Authorization": f"Bearer {token(self.env)}"}

    def get(self, path, **params):
        r = requests.get(f"{API}{path}", headers=self.headers, params=params, timeout=60)
        if r.status_code >= 400:
            sys.exit(f"GET {path} -> {r.status_code}\n{r.text}")
        return r.json()

    def post(self, path, body, tolerate=()):
        r = requests.post(f"{API}{path}", headers=self.headers, json=body, timeout=60)
        if r.status_code in tolerate:
            return None
        if r.status_code >= 400:
            sys.exit(f"POST {path} -> {r.status_code}\n{r.text}")
        return r.json() if r.text else {}

    def app(self):
        data = self.get("/v1/apps", **{"filter[bundleId]": BUNDLE_ID})["data"]
        if not data:
            sys.exit(
                f"no app record for {BUNDLE_ID} — create it in App Store Connect first"
            )
        return data[0]

    def builds(self, app_id, limit=10):
        return self.get(
            "/v1/builds",
            **{
                "filter[app]": app_id,
                "limit": limit,
                "sort": "-version",
                "include": "preReleaseVersion",
            },
        )


def cmd_status(c):
    app = c.app()
    a = app["attributes"]
    print(f"App: {a['name']}  ({a['bundleId']})  id={app['id']}")
    resp = c.builds(app["id"])
    included = {i["id"]: i for i in resp.get("included", [])}
    if not resp["data"]:
        print("\nNo builds yet — Apple may still be ingesting the upload (allow ~5 min).")
        return
    print("\nBuilds (newest first):")
    for b in resp["data"]:
        at = b["attributes"]
        rel = b["relationships"].get("preReleaseVersion", {}).get("data")
        ver = included.get(rel["id"], {}).get("attributes", {}).get("version", "?") if rel else "?"
        print(
            f"  {ver} ({at['version']})  state={at['processingState']}  "
            f"expired={at['expired']}  uploaded={at.get('uploadedDate')}"
        )


def cmd_groups(c):
    app = c.app()
    groups = c.get("/v1/betaGroups", **{"filter[app]": app["id"], "limit": 50})["data"]
    if not groups:
        print("No beta groups.")
        return
    for g in groups:
        at = g["attributes"]
        kind = "internal" if at.get("isInternalGroup") else "EXTERNAL"
        print(f"\n[{kind}] {at['name']}  id={g['id']}")
        testers = c.get(f"/v1/betaGroups/{g['id']}/betaTesters", limit=200)["data"]
        for t in testers:
            ta = t["attributes"]
            print(f"    {ta.get('email')}  {ta.get('firstName') or ''} state={ta.get('state')}")


def internal_group(c, app_id):
    groups = c.get("/v1/betaGroups", **{"filter[app]": app_id, "limit": 50})["data"]
    for g in groups:
        if g["attributes"].get("isInternalGroup"):
            return g
    return None


def cmd_add_tester(c, email):
    app = c.app()
    g = internal_group(c, app["id"])
    if not g:
        print("No internal group exists yet; creating one named 'Internal'.")
        g = c.post(
            "/v1/betaGroups",
            {
                "data": {
                    "type": "betaGroups",
                    "attributes": {"name": "Internal", "isInternalGroup": True},
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": app["id"]}}
                    },
                }
            },
        )["data"]
    existing = c.get(f"/v1/betaGroups/{g['id']}/betaTesters", limit=200)["data"]
    if any((t["attributes"].get("email") or "").lower() == email.lower() for t in existing):
        print(f"{email} is already in '{g['attributes']['name']}'.")
        return
    c.post(
        "/v1/betaTesters",
        {
            "data": {
                "type": "betaTesters",
                "attributes": {"email": email},
                "relationships": {
                    "betaGroups": {"data": [{"type": "betaGroups", "id": g["id"]}]}
                },
            }
        },
    )
    print(f"Added {email} to '{g['attributes']['name']}'.")


def cmd_release(c, want=None):
    app = c.app()
    resp = c.builds(app["id"])
    builds = resp["data"]
    if not builds:
        sys.exit("no builds — upload one first")
    build = None
    if want:
        for b in builds:
            if b["attributes"]["version"] == str(want):
                build = b
                break
        if not build:
            sys.exit(f"build {want} not found")
    else:
        build = builds[0]
    state = build["attributes"]["processingState"]
    num = build["attributes"]["version"]
    if state != "VALID":
        sys.exit(f"build {num} is {state}, not VALID yet — wait for Apple to finish processing")
    g = internal_group(c, app["id"])
    if not g:
        sys.exit("no internal beta group — run 'add-tester EMAIL' first")
    # The betaGroups relationship allows only CREATE/DELETE (no GET), so there is no
    # way to pre-check membership — POST and treat "already there" (409) as success.
    res = c.post(
        f"/v1/builds/{build['id']}/relationships/betaGroups",
        {"data": [{"type": "betaGroups", "id": g["id"]}]},
        tolerate=(409,),
    )
    name = g["attributes"]["name"]
    if res is None:
        print(f"Build {num} was already distributed to '{name}'.")
    else:
        print(f"Build {num} distributed to '{name}' — testers get it now.")


def cmd_invite(c, email):
    """Email a TestFlight invite. Internal testers can install without it (the build
    just appears in the TestFlight app), but the invite is what flips the tester's
    state off NOT_INVITED and gives a one-tap link."""
    app = c.app()
    g = internal_group(c, app["id"])
    if not g:
        sys.exit("no internal beta group — run 'add-tester EMAIL' first")
    testers = c.get(f"/v1/betaGroups/{g['id']}/betaTesters", limit=200)["data"]
    match = [t for t in testers if (t["attributes"].get("email") or "").lower() == email.lower()]
    if not match:
        sys.exit(f"{email} is not in '{g['attributes']['name']}' — run 'add-tester' first")
    c.post(
        "/v1/betaTesterInvitations",
        {
            "data": {
                "type": "betaTesterInvitations",
                "relationships": {
                    "app": {"data": {"type": "apps", "id": app["id"]}},
                    "betaTester": {"data": {"type": "betaTesters", "id": match[0]["id"]}},
                },
            }
        },
    )
    print(f"Invitation sent to {email}.")


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    c = Client()
    cmd = sys.argv[1]
    if cmd == "status":
        cmd_status(c)
    elif cmd == "groups":
        cmd_groups(c)
    elif cmd == "add-tester":
        cmd_add_tester(c, sys.argv[2])
    elif cmd == "invite":
        cmd_invite(c, sys.argv[2])
    elif cmd == "release":
        cmd_release(c, sys.argv[2] if len(sys.argv) > 2 else None)
    elif cmd == "raw":
        print(json.dumps(c.get(sys.argv[2]), indent=2))
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
