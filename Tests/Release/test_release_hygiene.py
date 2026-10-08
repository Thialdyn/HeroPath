from pathlib import Path
import hashlib, re, subprocess, collections

ROOT = Path(__file__).resolve().parents[2]

# 1) Production Lua parses and has no obvious definition-only local functions.
runtime = [
    ROOT / "Addon/HeroPath/Contract.lua",
    ROOT / "Addon/HeroPath/DataModel.lua",
    ROOT / "Addon/HeroPath/Bootstrap.lua",
    ROOT / "Addon/HeroPath/Metadata.lua",
    ROOT / "Addon/HeroPath/HeroPath.lua",
    ROOT / "Addon/HeroPath/API.lua",
    ROOT / "Addon/HeroPath/Diagnostics.lua",
]
for path in runtime:
    subprocess.run(["texluac", "-p", str(path)], check=True)
    text = path.read_text(encoding="utf-8")
    for name in re.findall(r"\blocal\s+function\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(", text):
        assert len(re.findall(r"\b" + re.escape(name) + r"\b", text)) > 1, (path.name, name, "definition-only local function")
assert "ns.IntegrationDiagnostics = diagnostics" not in runtime[0].read_text(encoding="utf-8")

# 2) Published tree has a small, explicit responsibility-based shape.
expected_dirs={".github", "Addon", "Demo", "Documentation", "Maps", "Tests", "Web"}
actual_dirs={p.name for p in ROOT.iterdir() if p.is_dir()}
assert actual_dirs == expected_dirs, ("unexpected product directories", sorted(actual_dirs))

# 3) Build a searchable corpus for active asset-reference checks.
text_ext={".html", ".js", ".json", ".md", ".py", ".lua", ".txt", ".svg", ".toc", ".bat", ".sh"}
texts=[]
for path in ROOT.rglob("*"):
    if path.is_file() and path.suffix.lower() in text_ext:
        texts.append(path.read_text(encoding="utf-8", errors="ignore"))
joined="\n".join(texts)

# 4) Every active map/icon is either directly referenced or belongs to the dynamic class family.
assert "classes-round/" in joined and "classicon_" in joined
for path in (ROOT / "Maps/icons").rglob("*"):
    if not path.is_file():
        continue
    rel = path.relative_to(ROOT).as_posix()
    if "/classes-round/" in "/" + rel:
        continue
    assert path.name in joined or rel in joined, ("orphan active icon", rel)

# 5) Active duplicate source/demo files are restricted to deliberate runtime/reference copies.
groups = collections.defaultdict(list)
for path in ROOT.rglob("*"):
    if not path.is_file() or path.suffix.lower() in {".webp", ".zip"}:
        continue
    digest = hashlib.sha256(path.read_bytes()).hexdigest()
    groups[digest].append(path.relative_to(ROOT).as_posix())
allowed = {
    frozenset({"Maps/icons/vignettekillelite.png", "Maps/WorldAtlas/icons/svc-rare-elite.png"}),
}
for paths in groups.values():
    if len(paths) > 1:
        assert frozenset(paths) in allowed, ("unexpected active duplicate", paths)

# 6) Demo has one public entrypoint.
index = ROOT / "Demo/index.html"
assert index.is_file() and index.stat().st_size > 100000
assert [p.name for p in (ROOT / "Demo").glob("*.html")] == ["index.html"]

# 7) Public demo/documentation must not contain character identity-bearing data.
public_text = []
for base in (ROOT / "Demo", ROOT / "Documentation"):
    for path in base.rglob("*"):
        if path.is_file() and path.suffix.lower() in text_ext:
            public_text.append(path.read_text(encoding="utf-8", errors="ignore"))
public = "\n".join(public_text)
assert not re.search(r"Player-\d{3,}-[0-9A-F]{6,}", public, re.I), "player GUID leaked into public demo/docs"
assert "ownerNameKey" not in public and "ownerKey" not in public, "identity-bearing SavedVariables field leaked into public demo/docs"

print("RELEASE_RUNTIME_DEAD_CODE=PASS")
print("RELEASE_PUBLICATION_HYGIENE=PASS")
print("RELEASE_ACTIVE_ASSET_GRAPH=PASS")
print("RELEASE_DUPLICATE_SCAN=PASS")
print("RELEASE_DEMO_ENTRYPOINT=PASS")
print("RELEASE_ANONYMIZATION=PASS")
