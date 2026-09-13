#!/usr/bin/env python3
from __future__ import annotations

import csv
import hashlib
import json
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    patch = ROOT / "patches" / "nodes_qwen.v2.py"
    assert hashlib.sha256(patch.read_bytes()).hexdigest() == (
        "9df96288f466ca03f7d7fa8587ad53c8021b784f42daabdc1f59a61b71c40238"
    )

    with (ROOT / "manifests" / "models.tsv").open(newline="", encoding="utf-8") as handle:
        rows = list(csv.DictReader(handle, delimiter="\t"))
    assert {row["variant"] for row in rows} == {"nsfw-v23"}
    for row in rows:
        assert int(row["size_bytes"]) > 28_000_000_000
        assert re.fullmatch(r"[0-9a-f]{64}", row["sha256"]), row
        assert re.fullmatch(r"[0-9a-f]{40}", row["revision"]), row
        assert row["target_rel"].startswith("checkpoints/")

    api_files = sorted((ROOT / "workflows" / "api").glob("*.json"))
    gui_files = sorted((ROOT / "workflows" / "gui").glob("*.json"))
    assert len(api_files) == 2
    assert len(gui_files) == 2
    for path in api_files:
        graph = json.loads(path.read_text(encoding="utf-8"))
        positive = graph["4"]
        sampler = graph["6"]["inputs"]
        assert positive["class_type"] == "TextEncodeQwenImageEditPlus"
        assert positive["inputs"]["target_latent"] == ["3", 0]
        assert positive["inputs"]["image1"] == ["1", 0]
        assert sampler["steps"] in (4, 8)
        assert sampler["cfg"] == 1.0
        assert sampler["sampler_name"] == "euler_ancestral"
        assert sampler["scheduler"] == "beta"
        assert graph["3"]["inputs"]["width"] == 1344
        assert graph["3"]["inputs"]["height"] == 768

    for path in gui_files:
        graph = json.loads(path.read_text(encoding="utf-8"))
        assert graph["version"] == 0.4
        positive = next(node for node in graph["nodes"] if node["id"] == 4)
        assert any(slot["name"] == "target_latent" and slot["link"] for slot in positive["inputs"])

    dockerfile = (ROOT / "Dockerfile").read_text(encoding="utf-8")
    assert "ARG HF_TOKEN" not in dockerfile
    assert "ENV HF_TOKEN" not in dockerfile
    assert "--mount=type=secret,id=hf_token" in dockerfile
    assert not any(path.stat().st_size > 1_000_000 for path in ROOT.rglob("*") if path.is_file())

    downloader = (ROOT / "scripts" / "download-model.sh").read_text(encoding="utf-8")
    assert "os.path.relpath" in downloader
    assert 'ln -s "$relative_source" "$temporary"' in downloader

    print("bundle tests: OK")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
