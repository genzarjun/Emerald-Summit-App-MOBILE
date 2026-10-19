#!/usr/bin/env python3
"""State + change-detection helper for the /checkup skill.

  checkup.py scan [TIER|all]       what changed and what's never been checked -> JSON plan
  checkup.py impact FILE...        files that depend on FILE... according to graphify-out/graph.json
  checkup.py mark --note TXT FILE...   record FILE... as checked (content hash) and HEAD as the last run
  checkup.py coverage              per-file checked / changed / never-checked listing
  checkup.py declined add TXT | list   larger changes the user said no to (so they aren't re-asked)

Per-file tracking: every tracked file (lib/, test/, supabase/) gets a content hash
when a checkup reviews it. A file is "current" while its hash still matches,
"changed" once it's edited, and "never" until a checkup has read it.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(subprocess.check_output(["git", "rev-parse", "--show-toplevel"], text=True).strip())
STATE = ROOT / ".claude" / "skills" / "checkup" / "state.json"
GRAPH = ROOT / "graphify-out" / "graph.json"
APP_PACKAGE = "emerald_summit"
IGNORED_PACKAGES = {"flutter", "flutter_test", APP_PACKAGE}
TRACKED = [("lib", ".dart"), ("test", ".dart"), ("supabase", ".sql"), ("supabase/functions", ".ts")]
# How many never-checked files each tier pulls in on top of the changed ones.
COVERAGE_SLICE = {"light": 3, "standard": 6, "deep": 12, "coverage": 8, "all": 10**6}

# Path prefix -> area. First match wins, so order matters.
AREAS = [
    ("pubspec.yaml", "deps"),
    ("pubspec.lock", "deps"),
    ("supabase/functions/", "edge_functions"),
    ("supabase/", "sql"),
    ("lib/screens/auth/", "auth"),
    ("lib/backend/supabase/supabase_auth", "auth"),
    ("lib/backend/auth", "auth"),
    ("lib/screens/", "ui"),
    ("lib/widgets/", "ui"),
    ("lib/theme", "ui"),
    ("lib/backend/", "backend"),
    ("lib/models/", "models"),
    ("lib/data/", "models"),
    ("lib/", "app_core"),
    ("test/", "tests"),
    ("ios/", "native"),
    ("android/", "native"),
    (".claude/", "tooling"),
]


def git(*args):
    return subprocess.run(["git", *args], cwd=ROOT, text=True, capture_output=True).stdout


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def load_state():
    state = json.loads(STATE.read_text()) if STATE.exists() else {}
    state.setdefault("last_sha", None)
    state.setdefault("last_run", None)
    state.setdefault("runs", [])
    state.setdefault("files", {})
    state.setdefault("declined", [])
    return state


def save_state(state):
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=2) + "\n")


def area_of(path):
    for prefix, area in AREAS:
        if path.startswith(prefix):
            return area
    return "docs" if path.endswith(".md") else "other"


def file_hash(rel):
    return hashlib.sha1((ROOT / rel).read_bytes()).hexdigest()


def tracked_files():
    files = set()
    for folder, ext in TRACKED:
        for p in (ROOT / folder).rglob(f"*{ext}"):
            if p.is_file():
                files.add(str(p.relative_to(ROOT)))
    return sorted(files)


def coverage_status(state):
    """{file: 'current' | 'changed' | 'never'} for every tracked file."""
    out = {}
    for f in tracked_files():
        rec = state["files"].get(f)
        out[f] = "never" if not rec else ("current" if rec["hash"] == file_hash(f) else "changed")
    return out


def graph_degree():
    """{source_file: number of edges touching it}; empty if there's no graph."""
    if not GRAPH.exists():
        return {}
    g = json.loads(GRAPH.read_text())
    nodes = {n["id"]: n.get("source_file") for n in g["nodes"]}
    deg = {}
    for e in g.get("links") or g.get("edges"):
        for end in (e["source"], e["target"]):
            f = nodes.get(end)
            if f:
                deg[f] = deg.get(f, 0) + 1
    return deg


def numstat(*range_args):
    """{path: lines_changed} for a diff range (or working tree vs HEAD)."""
    out = {}
    for line in git("diff", "--numstat", *range_args).splitlines():
        added, removed, path = line.split("\t", 2)
        if " => " in path:  # rename: keep the new name
            path = re.sub(r"\{.*? => (.*?)\}", r"\1", path).split(" => ")[-1]
        n = (0 if added == "-" else int(added)) + (0 if removed == "-" else int(removed))
        out[path] = out.get(path, 0) + n
    return out


def packages_in(files):
    pkgs = set()
    for f in files:
        p = ROOT / f
        if f.endswith(".dart") and p.exists():
            pkgs.update(re.findall(r"""import\s+['"]package:([a-z0-9_]+)/""", p.read_text(errors="ignore")))
    return sorted(pkgs - IGNORED_PACKAGES)


def scan(forced_tier=None):
    state = load_state()
    head = git("rev-parse", "HEAD").strip()
    base = state["last_sha"]
    if base and subprocess.run(["git", "cat-file", "-e", base], cwd=ROOT, capture_output=True).returncode != 0:
        base = None  # history was rewritten

    # Line counts from git (commits since last run + uncommitted work).
    lines_by_file = numstat(f"{base}..HEAD") if base else {}
    working = numstat("HEAD")
    untracked = [f for f in git("ls-files", "--others", "--exclude-standard").splitlines()
                 if not f.startswith("graphify-out/")]
    for f, n in working.items():
        lines_by_file[f] = lines_by_file.get(f, 0) + n
    for f in untracked:
        lines_by_file.setdefault(f, 0)

    # Per-file status from content hashes.
    status = coverage_status(state)
    changed = sorted(f for f, s in status.items() if s == "changed")
    never = [f for f, s in status.items() if s == "never"]
    first_run = not state["files"]
    # On the first run every file is "never"; the git diff is meaningless, so
    # changed = nothing and the whole review comes from the coverage slice.
    changed_set = set(changed) if not first_run else set()
    if not first_run:
        changed_set |= {f for f in lines_by_file if f in status and status[f] != "current"}
    changed = sorted(changed_set)

    code_lines = sum(lines_by_file.get(f, 0) for f in changed)
    days = None
    if state["last_run"]:
        days = (datetime.now(timezone.utc) - datetime.fromisoformat(state["last_run"])).days

    if forced_tier == "all":
        tier, why = "all", "requested: check every file that isn't current"
        changed = sorted(f for f, st in status.items() if st == "changed")
    elif forced_tier:
        tier, why = forced_tier, "requested"
    elif first_run:
        tier, why = "deep", "first checkup: no file has been checked yet"
    elif not changed and not never and not lines_by_file:
        tier, why = "none", "nothing changed and every file is checked"
    elif not changed:
        tier, why = "coverage", f"no code changes; {len(never)} files still never checked"
    elif days is not None and days >= 30:
        tier, why = "deep", f"{days} days since the last checkup"
    elif len(changed) > 25 or code_lines > 1000:
        tier, why = "deep", f"{len(changed)} files / {code_lines} lines changed"
    elif len(changed) > 5 or code_lines > 150:
        tier, why = "standard", f"{len(changed)} files / {code_lines} lines changed"
    else:
        tier, why = "light", f"{len(changed)} files / {code_lines} lines changed"

    deg = graph_degree()
    never.sort(key=lambda f: (-deg.get(f, 0), f))  # most-connected first
    slice_ = never[: COVERAGE_SLICE.get(tier, 0)]

    all_touched = sorted(set(lines_by_file) | set(changed))
    areas = {}
    for f in all_touched:
        areas.setdefault(area_of(f), []).append(f)
    lib_changed = [f for f in changed if f.startswith("lib/")]
    tests_changed = [f for f in all_touched if f.startswith("test/")]

    counts = {s: sum(1 for v in status.values() if v == s) for s in ("current", "changed", "never")}
    print(json.dumps({
        "tier": tier,
        "reason": why,
        "base_sha": base,
        "head_sha": head,
        "days_since_last": days,
        "commits_since": git("log", "--oneline", f"{base}..HEAD").splitlines() if base else [],
        "dirty_worktree": bool(working or untracked),
        "uncommitted_files": sorted(set(working) | set(untracked)),
        "changed_files": changed,
        "never_checked_slice": slice_,
        "review_files": sorted(set(changed) | set(slice_)),
        "lines_changed": {f: lines_by_file[f] for f in changed if f in lines_by_file},
        "areas": {a: sorted(fs) for a, fs in sorted(areas.items())},
        "other_touched_files": [f for f in all_touched if f not in status],
        "lib_changed_without_test_change": lib_changed if lib_changed and not tests_changed else [],
        "packages_used_in_review_files": packages_in(sorted(set(changed) | set(slice_))),
        "coverage": {**counts, "total": len(status),
                     "percent_current": round(100 * counts["current"] / max(len(status), 1))},
        "graph_exists": GRAPH.exists(),
        "declined": [d["item"] for d in state["declined"]],
        "previous_runs": state["runs"][-3:],
    }, indent=2))


def _resolve_import(importer, target):
    if target.startswith(f"package:{APP_PACKAGE}/"):
        return "lib/" + target.split("/", 1)[1]
    if target.startswith(("package:", "dart:")):
        return None
    return os.path.normpath(os.path.join(os.path.dirname(importer), target))


def impact(files):
    if not GRAPH.exists():
        sys.exit("graphify-out/graph.json missing - run `graphify update .` first")
    g = json.loads(GRAPH.read_text())
    nodes = {n["id"]: n for n in g["nodes"]}
    targets = set(files)
    dependents = {}  # dependent file -> set of (relation, changed file)

    for e in g.get("links") or g.get("edges"):
        rel = e.get("relation")
        if rel in ("defines", "contains"):
            continue
        src_file = e.get("source_file") or nodes.get(e["source"], {}).get("source_file")
        tgt = nodes.get(e["target"], {})
        if rel in ("imports", "imports_from", "exports"):
            hit = _resolve_import(src_file or "", tgt.get("label", "")) if src_file else None
        else:
            hit = tgt.get("source_file")
        if hit in targets and src_file and src_file != hit:
            dependents.setdefault(src_file, set()).add((rel, hit))

    out = [{"file": f, "via": sorted({r for r, _ in v}), "depends_on": sorted({h for _, h in v})}
           for f, v in sorted(dependents.items(), key=lambda kv: (-len(kv[1]), kv[0]))
           if f not in targets]
    stale = g.get("built_at_commit") and not git("rev-parse", "HEAD").startswith(g["built_at_commit"][:7])
    print(json.dumps({"graph_stale": bool(stale), "dependents": out}, indent=2))


def mark(note, files):
    state = load_state()
    head = git("rev-parse", "HEAD").strip()
    ts = now()
    recorded = 0
    for f in files:
        if (ROOT / f).is_file():
            state["files"][f] = {"hash": file_hash(f), "checked": ts, "sha": head[:8]}
            recorded += 1
    # Drop records for files that no longer exist.
    state["files"] = {f: r for f, r in state["files"].items() if (ROOT / f).is_file()}
    state["runs"] = (state["runs"] + [{"at": ts, "sha": head, "files": recorded, "note": note}])[-30:]
    state["last_sha"], state["last_run"] = head, ts
    save_state(state)
    status = coverage_status(state)
    cur = sum(1 for s in status.values() if s == "current")
    print(f"checkup marked at {head[:8]}: {recorded} files recorded, coverage {cur}/{len(status)}")


def coverage():
    state = load_state()
    status = coverage_status(state)
    deg = graph_degree()
    for label in ("changed", "never", "current"):
        fs = sorted((f for f, s in status.items() if s == label), key=lambda f: (-deg.get(f, 0), f))
        print(f"\n{label.upper()} ({len(fs)})")
        for f in fs:
            rec = state["files"].get(f)
            print(f"  {f}" + (f"  (checked {rec['checked'][:10]})" if rec else ""))


def declined(args):
    state = load_state()
    if args[:1] == ["add"]:
        state["declined"].append({"item": " ".join(args[1:]), "date": now()[:10]})
        save_state(state)
    for d in state["declined"]:
        print(f"- {d['item']} ({d['date']})")


if __name__ == "__main__":
    cmd, rest = (sys.argv[1], sys.argv[2:]) if len(sys.argv) > 1 else ("scan", [])
    if cmd == "scan":
        scan(rest[0] if rest else None)
    elif cmd == "impact":
        impact(rest)
    elif cmd == "mark":
        note = rest[1] if rest[:1] == ["--note"] and len(rest) > 1 else ""
        mark(note, rest[2:] if rest[:1] == ["--note"] else rest)
    elif cmd == "coverage":
        coverage()
    elif cmd == "declined":
        declined(rest)
    else:
        sys.exit(__doc__)
