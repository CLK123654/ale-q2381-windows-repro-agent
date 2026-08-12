from __future__ import annotations

import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TASK = ROOT / "task"
EXPECTED = json.loads((ROOT / "qa/expected_hashes.json").read_text(encoding="utf-8"))

def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()

actual = {name: digest(TASK / name) for name in EXPECTED}
if actual != EXPECTED:
    raise SystemExit(f"attachment hash mismatch: {actual}")
print(json.dumps(actual, ensure_ascii=True, sort_keys=True))
