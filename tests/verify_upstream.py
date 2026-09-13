#!/usr/bin/env python3
"""Check the pinned public Hugging Face objects without downloading weights."""

from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path
import urllib.request


ROOT = Path(__file__).resolve().parents[1]
REVISION = "691024f438640508f8aa86414863fc15edfb8a84"
BASE = "https://huggingface.co"


def get_json(url: str):
    request = urllib.request.Request(url, headers={"User-Agent": "qwen-rapid-bundle-verifier"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return json.load(response)


def get_bytes(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "qwen-rapid-bundle-verifier"})
    with urllib.request.urlopen(request, timeout=30) as response:
        return response.read()


def main() -> int:
    model = get_json(f"{BASE}/api/models/Phr00t/Qwen-Image-Edit-Rapid-AIO")
    assert model["private"] is False
    assert model["gated"] is False
    assert model["disabled"] is False
    assert model["sha"] == REVISION

    with (ROOT / "manifests" / "models.tsv").open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    expected = {row["repo_path"]: row for row in rows}

    actual = {}
    for directory in ("v23",):
        tree = get_json(
            f"{BASE}/api/models/Phr00t/Qwen-Image-Edit-Rapid-AIO/tree/{REVISION}/{directory}"
            "?recursive=true&expand=true"
        )
        actual.update({entry["path"]: entry for entry in tree if entry["path"] in expected})
    assert set(actual) == set(expected)
    for path, row in expected.items():
        entry = actual[path]
        assert entry["size"] == int(row["size_bytes"])
        assert entry["lfs"]["oid"] == row["sha256"]

    node = get_bytes(
        f"{BASE}/Phr00t/Qwen-Image-Edit-Rapid-AIO/resolve/{REVISION}/"
        "fixed-textencode-node/nodes_qwen.v2.py"
    )
    assert hashlib.sha256(node).hexdigest() == (
        "9df96288f466ca03f7d7fa8587ad53c8021b784f42daabdc1f59a61b71c40238"
    )
    assert node == (ROOT / "patches" / "nodes_qwen.v2.py").read_bytes()
    print("upstream pins: OK (public, ungated, NSFW v23, author node)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
