import json, os, re, sys, zipfile

VEH = os.path.expanduser(os.environ.get("BEAMNG_VEHICLES", "~/.local/share/Steam/steamapps/common/BeamNG.drive/content/vehicles"))

def strip_comments(s):
    out, i, n, in_str = [], 0, len(s), False
    while i < n:
        c = s[i]
        if in_str:
            out.append(c)
            if c == "\\" and i + 1 < n:
                out.append(s[i + 1]); i += 2; continue
            if c == '"': in_str = False
            i += 1
        elif c == '"':
            in_str = True; out.append(c); i += 1
        elif s.startswith("//", i):
            j = s.find("\n", i); i = n if j < 0 else j
        elif s.startswith("/*", i):
            j = s.find("*/", i + 2); i = n if j < 0 else j + 2
        else:
            out.append(c); i += 1
    return "".join(out)

TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|-?\d+\.?\d*(?:[eE][-+]?\d+)?|true|false|null|[{}\[\]:,]|\S', re.S)

def jbeam_loads(text):
    toks = TOKEN.findall(strip_comments(text))
    fixed = []
    def is_value_end(t): return t in ("}", "]") or t[0] == '"' or t[0].isdigit() or t[0] == "-" or t in ("true", "false", "null")
    def is_value_start(t): return t in ("{", "[") or t[0] == '"' or t[0].isdigit() or t[0] == "-" or t in ("true", "false", "null")
    for t in toks:
        if fixed and is_value_end(fixed[-1]) and is_value_start(t):
            fixed.append(",")
        if t in ("}", "]") and fixed and fixed[-1] == ",":
            fixed.pop()
        fixed.append(t)
    return json.loads("".join(fixed))

def load_parts(zf, prefix):
    parts = {}
    for name in zf.namelist():
        if name.startswith(prefix) and name.endswith(".jbeam"):
            try:
                data = jbeam_loads(zf.read(name).decode("utf-8", "replace"))
            except Exception:
                continue
            if isinstance(data, dict):
                for k, v in data.items():
                    if isinstance(v, dict):
                        parts[k] = v
    return parts

def slots_of(part):
    rows = part.get("slots2") or part.get("slots") or []
    out = []
    if not rows or not isinstance(rows[0], list):
        return out
    header = rows[0]
    v2 = "slots2" in part
    for row in rows[1:]:
        if not isinstance(row, list) or not row: continue
        if v2:
            d = dict(zip(header, row))
            out.append({"name": d.get("name"), "allow": d.get("allowTypes") or [], "deny": d.get("denyTypes") or [], "default": d.get("default", "")})
        else:
            if row[0] == "type": continue
            out.append({"name": row[0], "allow": [row[0]], "deny": [], "default": row[1] if len(row) > 1 else ""})
    return out

def slot_types(part):
    st = part.get("slotType")
    return st if isinstance(st, list) else ([st] if isinstance(st, str) else [])


def export(model, common, out_dir):
    zf = zipfile.ZipFile(os.path.join(VEH, model + ".zip"))
    raw = dict(common)
    raw.update(load_parts(zf, "vehicles/%s/" % model))
    parts = {}
    for name, d in raw.items():
        slots = [{"name": s["name"], "allowTypes": s["allow"], "denyTypes": s["deny"], "default": s["default"] or ""} for s in slots_of(d)]
        rows = d.get("slots2") or d.get("slots") or []
        extras = [r[-1] for r in rows[1:] if isinstance(r, list) and r and r[0] != "type" and isinstance(r[-1], dict)] if rows and isinstance(rows[0], list) else []
        for slot, extra in zip(slots, extras):
            slot.update({k: v for k, v in extra.items() if k != "name"})
        keep = {k: d[k] for k in ("slotType", "props", "flexbodies", "variables", "lights") if k in d}
        keep["slots2"] = slots
        parts[name] = keep
    configs = {}
    for n in zf.namelist():
        if n.startswith("vehicles/%s/" % model) and n.endswith(".pc") and n.count("/") == 2:
            try:
                cfg = jbeam_loads(zf.read(n).decode("utf-8", "replace"))
            except Exception:
                continue
            if isinstance(cfg, dict) and isinstance(cfg.get("parts"), dict) and cfg.get("format") != 4:
                configs[os.path.basename(n)[:-3]] = {"main": cfg.get("mainPartName") or model, "parts": cfg["parts"]}
    if configs:
        json.dump({"parts": parts, "configs": configs}, open(os.path.join(out_dir, model + ".json"), "w"))
    return len(configs)

def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else ".lightcheck"
    os.makedirs(out_dir, exist_ok=True)
    models = sys.argv[2:] or sorted(z[:-4] for z in os.listdir(VEH) if z.endswith(".zip") and z != "common.zip")
    common = load_parts(zipfile.ZipFile(os.path.join(VEH, "common.zip")), "vehicles/common/")
    for model in models:
        n = export(model, common, out_dir)
        if n: print(model, n, "configs")

main()
