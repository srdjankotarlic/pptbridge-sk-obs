#!/bin/bash

set -euo pipefail

SCENES_DIR="${1:-$HOME/Library/Application Support/obs-studio/basic/scenes}"

if [ ! -d "$SCENES_DIR" ]; then
  echo "OBS scenes directory not found:"
  echo "$SCENES_DIR"
  exit 0
fi

python3 - "$SCENES_DIR" <<'PY'
import json
import os
import sys
from pathlib import Path

scenes_dir = Path(sys.argv[1])
targets = sorted(
    path for path in scenes_dir.iterdir()
    if path.is_file() and (path.suffix == ".json" or path.name.endswith(".json.bak"))
)

modified = []

for path in targets:
    try:
        data = json.loads(path.read_text())
    except Exception:
        continue

    modules = data.get("modules")
    if not isinstance(modules, dict):
        continue

    scripts_tool = modules.get("scripts-tool")
    if not isinstance(scripts_tool, list):
        continue

    filtered = []
    changed = False
    for entry in scripts_tool:
        script_path = ""
        if isinstance(entry, dict):
            script_path = entry.get("path") or ""

        if os.path.basename(script_path) == "pptbridge_obs.py":
            changed = True
            continue

        filtered.append(entry)

    if not changed:
        continue

    modules["scripts-tool"] = filtered
    path.write_text(json.dumps(data, indent=4, ensure_ascii=False) + "\n")
    modified.append(str(path))

if modified:
    print("Removed legacy PPTBridge Python script entries from:")
    for item in modified:
        print(item)
else:
    print("No legacy PPTBridge Python script entries were found.")
PY
