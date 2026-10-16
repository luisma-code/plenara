#!/usr/bin/env python3
"""Read or distribute a verified Plenara TestFlight build using the existing API key.

python3 tool/testflight.py status [BUILD]
python3 tool/testflight.py distribute BUILD
python3 tool/testflight.py release BUILD  # wait, distribute, confirm testing
Credentials stay outside the repository. JWTs are never printed.
"""
import base64, json, time, subprocess, urllib.request, urllib.error, urllib.parse, os, sys, tempfile

KEY = os.path.expanduser("~/.appstoreconnect/private_keys/AuthKey_AQMT4FFHKW.p8")
KID, ISS = "AQMT4FFHKW", "12ee92f1-bd97-4747-bc50-87c476d9eb9b"
APP_ID = "6795650460"
BUNDLE_ID = "com.plenara.plenaraApp"
GROUP_NAME = "Internal"
BASE = "https://api.appstoreconnect.apple.com/v1"


def token():
    b64 = lambda d: base64.urlsafe_b64encode(d).rstrip(b"=")
    head = b64(json.dumps({"alg": "ES256", "kid": KID, "typ": "JWT"}, separators=(",", ":")).encode())
    now = int(time.time())
    body = b64(json.dumps({"iss": ISS, "iat": now, "exp": now + 600,
                           "aud": "appstoreconnect-v1"}, separators=(",", ":")).encode())
    signing_input = head + b"." + body
    with tempfile.NamedTemporaryFile(delete=False) as f:
        f.write(signing_input)
    der = subprocess.run(["openssl", "dgst", "-sha256", "-sign", KEY, f.name],
                         capture_output=True, check=True).stdout
    os.unlink(f.name)
    # ES256 JWS wants raw r||s; openssl emits DER SEQUENCE{INTEGER r, INTEGER s}.
    i, out = (2 if der[1] < 0x80 else 2 + (der[1] & 0x7F)), []
    for _ in range(2):
        ln = der[i + 1]
        out.append(der[i + 2:i + 2 + ln].lstrip(b"\x00").rjust(32, b"\x00"))
        i += 2 + ln
    return (signing_input + b"." + b64(out[0] + out[1])).decode()



def call(method, path, body=None):
    url = path if path.startswith("http") else BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method, headers={
        "Authorization": f"Bearer {token()}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            raw = r.read()
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as e:
        detail = e.read().decode()
        raise SystemExit(f"{method} {url} -> {e.code}\n{detail}")


def contract():
    app = call("GET", f"/apps/{APP_ID}")["data"]
    if app["attributes"]["bundleId"] != BUNDLE_ID:
        raise SystemExit("App identity mismatch; no distribution attempted")
    gs = [g for g in call("GET", f"/apps/{APP_ID}/betaGroups")["data"]
          if g["attributes"]["name"] == GROUP_NAME and g["attributes"]["isInternalGroup"]]
    if len(gs) != 1:
        raise SystemExit("Expected one existing internal group; no distribution attempted")
    group = gs[0]
    testers = call("GET", f"/betaGroups/{group['id']}/betaTesters")["data"]
    if not any(t["attributes"].get("email") == "luisma.webaccounts@gmail.com" for t in testers):
        raise SystemExit("Owner is not enrolled; no distribution attempted")
    return app, group, testers


def status(version=None, distribute=False, emit=True):
    app, group, testers = contract()
    path = f"/builds?filter[app]={APP_ID}&limit=20&sort=-uploadedDate"
    if version:
        path += "&filter[version]=" + urllib.parse.quote(version, safe="")
    builds = call("GET", path)["data"]
    if distribute:
        if not version or len(builds) != 1:
            raise SystemExit("Choose one exact existing build; nothing distributed")
        b = builds[0]
        if b["attributes"]["processingState"] != "VALID" or b["attributes"]["expired"]:
            raise SystemExit("Build is not valid and current; nothing distributed")
        prerelease = call("GET", f"/builds/{b['id']}/preReleaseVersion")["data"]["attributes"]
        if prerelease["version"] != "1.0.0" or prerelease["platform"] != "IOS":
            raise SystemExit("Expected native reset version 1.0.0 for iOS; nothing distributed")
        attached = call("GET", f"/betaGroups/{group['id']}/relationships/builds")["data"]
        if not any(x["id"] == b["id"] for x in attached):
            call("POST", f"/betaGroups/{group['id']}/relationships/builds",
                 {"data": [{"type": "builds", "id": b["id"]}]})
    attached = call("GET", f"/betaGroups/{group['id']}/relationships/builds")["data"]
    ids = {b["id"] for b in attached}
    out = {"appId": app["id"], "bundleId": BUNDLE_ID,
           "group": {"id": group["id"], "name": GROUP_NAME, "internal": True},
           "ownerEnrolled": True,
           "builds": [{"id": b["id"], "version": b["attributes"]["version"],
                       "processingState": b["attributes"]["processingState"],
                       "expired": b["attributes"]["expired"], "inGroup": b["id"] in ids,
                       "betaDetail": (call("GET", f"/builds/{b['id']}/buildBetaDetail")["data"]["attributes"]
                                      if b["attributes"]["processingState"] == "VALID" else {})}
                      for b in builds]}
    if emit:
        print(json.dumps(out, indent=2))
    return out


def release(version, timeout=1200, interval=30):
    """Success requires Apple's positive testing readback, never elapsed time."""
    deadline = time.monotonic() + timeout
    while True:
        snapshot = status(version, emit=False)
        builds = snapshot["builds"]
        if len(builds) > 1:
            raise SystemExit("Ambiguous build number; no distribution attempted")
        if builds:
            build = builds[0]
            if build["expired"] or build["processingState"] in ("FAILED", "INVALID"):
                raise SystemExit("Apple rejected or expired this build; release stopped")
            if build["processingState"] == "VALID":
                snapshot = status(version, distribute=True, emit=False)
                build = snapshot["builds"][0]
                if build["inGroup"] and build["betaDetail"].get("internalBuildState") == "IN_BETA_TESTING":
                    print(json.dumps(snapshot, indent=2))
                    return snapshot
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise SystemExit("Apple has not confirmed TestFlight availability within the deadline")
        print("Waiting for Apple's processing/testing status…", flush=True)
        time.sleep(min(interval, remaining))


if __name__ == "__main__":
    import urllib.parse
    command = sys.argv[1] if len(sys.argv) > 1 else "status"
    version = sys.argv[2] if len(sys.argv) > 2 else None
    if command not in ("status", "distribute", "release") or (command in ("distribute", "release") and not version):
        raise SystemExit(__doc__)
    if command == "release":
        release(version)
    else:
        status(version, command == "distribute")
