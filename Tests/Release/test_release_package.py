from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
ADDON = ROOT / "Addon" / "HeroPath"

errors = []

def check(cond, msg):
    if not cond:
        errors.append(msg)

# Project layout.
check((ROOT / "README-FR.md").is_file(), "README missing")
check((ROOT / "Documentation" / "MANUAL-FR.md").is_file(), "manual missing")
expected_dirs = {".github", "Addon", "Demo", "Documentation", "Maps", "Tests", "Web"}
actual_dirs = {p.name for p in ROOT.iterdir() if p.is_dir()}
check(actual_dirs == expected_dirs, f"unexpected project directories: {sorted(actual_dirs)}")

# Runtime metadata.
toc = (ADDON / "HeroPath.toc").read_text(encoding="utf-8")
check("## Title: Hero’sPath" in toc, "TOC title mismatch")
check("## Author: Darwyn" in toc, "TOC author mismatch")
check("## Version: 1.0.0" in toc, "TOC version mismatch")
check("## X-HeroPath-Schema: 1" in toc, "TOC schema mismatch")
check("## X-HeroPath-API: 1" in toc, "TOC API mismatch")
check("## SavedVariablesPerCharacter: HeroPathDB" in toc, "TOC SavedVariables name mismatch")

contract = (ADDON / "Contract.lua").read_text(encoding="utf-8")
engine = (ADDON / "HeroPath.lua").read_text(encoding="utf-8")
check(re.search(r"SAVED_VARIABLES_SCHEMA\s*=\s*1", contract) is not None, "SavedVariables schema is not 1")
check("FORMAT_VERSION = C.SAVED_VARIABLES_SCHEMA" in engine, "engine is not bound to Contract.lua")

# Lua files must parse.
for path in sorted(ADDON.glob("*.lua")):
    subprocess.run(["texluac", "-p", str(path)], check=True)

# Public integration surface.
check((ROOT / "Documentation" / "Integration" / "PUBLIC-API.md").is_file(), "public API documentation missing")
check((ROOT / "Documentation" / "Integration" / "HOST-INTEGRATION-CONTRACT.md").is_file(), "host integration contract missing")
check((ROOT / "Demo" / "index.html").is_file(), "demo entry missing")

if errors:
    for error in errors:
        print("FAIL:", error)
    raise SystemExit(1)

print("package: ok")
