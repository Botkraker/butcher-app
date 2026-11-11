"""Makes secrets.json (for --dart-define-from-file) from ../app/local.properties.
Reads the file like java.util.Properties. Prints only the key names, never the values."""
import json, pathlib, sys

src = pathlib.Path(__file__).resolve().parents[2] / "app" / "local.properties"
out = pathlib.Path(__file__).resolve().parents[1] / "secrets.json"
keys = {"neon.sql.url": "NEON_SQL_URL", "neon.connection.string": "NEON_CONNECTION_STRING"}

def unescape(v):
    r, i = [], 0
    while i < len(v):
        c = v[i]
        if c == "\\" and i + 1 < len(v):
            n = v[i + 1]
            r.append({"t": "\t", "n": "\n", "r": "\r", "f": "\f"}.get(n, n))
            i += 2
        else:
            r.append(c)
            i += 1
    return "".join(r)

props = {}
for line in src.read_text(encoding="utf-8").splitlines():
    s = line.strip()
    if not s or s[0] in "#!":
        continue
    cut = min([i for i in (s.find("="), s.find(":")) if i >= 0], default=-1)
    if cut < 0:
        continue
    props[s[:cut].strip()] = unescape(s[cut + 1:].strip())

data = {dart: props.get(prop, "") for prop, dart in keys.items()}
missing = [k for k, v in data.items() if not v]
out.write_text(json.dumps(data), encoding="utf-8")
print("wrote", out.name, "keys:", ", ".join(data), "| empty:", ", ".join(missing) or "none")
sys.exit(1 if missing else 0)
