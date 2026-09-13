#!/usr/bin/env python3
"""Generate pinned API and editable GUI workflows for Rapid AIO v23/v19."""

from __future__ import annotations

from collections import defaultdict
import json
from pathlib import Path
import uuid


ROOT = Path(__file__).resolve().parents[1]
API_DIR = ROOT / "workflows" / "api"
GUI_DIR = ROOT / "workflows" / "gui"
WIDTH = 1344
HEIGHT = 768
SEED = 2026091301
PROMPT = (
    "Picture 1 の人物の顔、髪、ポーズ、視線、カメラ、照明、背景、フレーミングを維持する。"
    "指定した変更だけを適用し、自然な皮膚のきめと解剖学的整合性を保つ。"
)

CHECKPOINTS = {
    "nsfw-v23": "Qwen-Rapid-AIO-NSFW-v23.safetensors",
}

OUTPUTS = {
    "LoadImage": [("IMAGE", "IMAGE"), ("MASK", "MASK")],
    "CheckpointLoaderSimple": [("MODEL", "MODEL"), ("CLIP", "CLIP"), ("VAE", "VAE")],
    "EmptyLatentImage": [("LATENT", "LATENT")],
    "TextEncodeQwenImageEditPlus": [("CONDITIONING", "CONDITIONING")],
    "KSampler": [("LATENT", "LATENT")],
    "VAEDecode": [("IMAGE", "IMAGE")],
    "SaveImage": [],
}

INPUT_TYPES = {
    "LoadImage": {"image": "COMBO"},
    "CheckpointLoaderSimple": {"ckpt_name": "COMBO"},
    "EmptyLatentImage": {"width": "INT", "height": "INT", "batch_size": "INT"},
    "TextEncodeQwenImageEditPlus": {
        "clip": "CLIP",
        "prompt": "STRING",
        "vae": "VAE",
        "image1": "IMAGE",
        "image2": "IMAGE",
        "image3": "IMAGE",
        "image4": "IMAGE",
        "target_latent": "LATENT",
    },
    "KSampler": {
        "model": "MODEL",
        "seed": "INT",
        "steps": "INT",
        "cfg": "FLOAT",
        "sampler_name": "COMBO",
        "scheduler": "COMBO",
        "positive": "CONDITIONING",
        "negative": "CONDITIONING",
        "latent_image": "LATENT",
        "denoise": "FLOAT",
    },
    "VAEDecode": {"samples": "LATENT", "vae": "VAE"},
    "SaveImage": {"images": "IMAGE", "filename_prefix": "STRING"},
}

POSITIONS = {
    "1": [40, 40],
    "2": [40, 320],
    "3": [40, 520],
    "4": [470, 40],
    "5": [470, 380],
    "6": [900, 120],
    "7": [1240, 120],
    "8": [1510, 120],
}


def is_link(value: object, node_ids: set[str]) -> bool:
    return (
        isinstance(value, list)
        and len(value) == 2
        and str(value[0]) in node_ids
        and isinstance(value[1], int)
    )


def api_graph(variant: str, steps: int) -> dict:
    return {
        "1": {"class_type": "LoadImage", "inputs": {"image": "reference.png"}},
        "2": {
            "class_type": "CheckpointLoaderSimple",
            "inputs": {"ckpt_name": CHECKPOINTS[variant]},
        },
        "3": {
            "class_type": "EmptyLatentImage",
            "inputs": {"width": WIDTH, "height": HEIGHT, "batch_size": 1},
        },
        "4": {
            "class_type": "TextEncodeQwenImageEditPlus",
            "inputs": {
                "clip": ["2", 1],
                "prompt": PROMPT,
                "vae": ["2", 2],
                "image1": ["1", 0],
                "target_latent": ["3", 0],
            },
            "_meta": {"title": "Positive · author v2 target-latent encoder"},
        },
        "5": {
            "class_type": "TextEncodeQwenImageEditPlus",
            "inputs": {"clip": ["2", 1], "prompt": " ", "vae": ["2", 2]},
            "_meta": {"title": "Negative (CFG 1.0)"},
        },
        "6": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["2", 0],
                "seed": SEED,
                "steps": steps,
                "cfg": 1.0,
                "sampler_name": "euler_ancestral",
                "scheduler": "beta",
                "positive": ["4", 0],
                "negative": ["5", 0],
                "latent_image": ["3", 0],
                "denoise": 1.0,
            },
        },
        "7": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["6", 0], "vae": ["2", 2]},
        },
        "8": {
            "class_type": "SaveImage",
            "inputs": {
                "images": ["7", 0],
                "filename_prefix": f"qwen-rapid/{variant}-{steps}step-target-latent",
            },
        },
    }


def widget_values(class_type: str, inputs: dict, node_ids: set[str]) -> list:
    values = [
        value
        for name, value in inputs.items()
        if not is_link(value, node_ids)
    ]
    if class_type == "KSampler":
        values.insert(1, "fixed")
    return values


def gui_graph(api: dict, variant: str, steps: int) -> dict:
    node_ids = set(api)
    nodes = []
    links = []
    output_links: dict[tuple[str, int], list[int]] = defaultdict(list)
    input_slots: dict[tuple[str, str], int] = {}

    for order, node_id in enumerate(sorted(api, key=int)):
        entry = api[node_id]
        class_type = entry["class_type"]
        gui_inputs = []
        for name, value in entry["inputs"].items():
            if is_link(value, node_ids):
                input_slots[(node_id, name)] = len(gui_inputs)
                gui_inputs.append({"name": name, "type": INPUT_TYPES[class_type][name], "link": None})
        gui_outputs = [
            {"name": name, "type": kind, "links": None}
            for name, kind in OUTPUTS[class_type]
        ]
        node = {
            "id": int(node_id),
            "type": class_type,
            "pos": POSITIONS[node_id],
            "size": [360, 220 if class_type == "TextEncodeQwenImageEditPlus" else 140],
            "flags": {},
            "order": order,
            "mode": 0,
            "inputs": gui_inputs,
            "outputs": gui_outputs,
            "properties": {"Node name for S&R": class_type},
            "widgets_values": widget_values(class_type, entry["inputs"], node_ids),
        }
        title = entry.get("_meta", {}).get("title")
        if title:
            node["title"] = title
        nodes.append(node)

    by_id = {str(node["id"]): node for node in nodes}
    next_link = 1
    for target_id in sorted(api, key=int):
        for input_name, value in api[target_id]["inputs"].items():
            if not is_link(value, node_ids):
                continue
            source_id, source_slot = str(value[0]), value[1]
            target_slot = input_slots[(target_id, input_name)]
            kind = by_id[source_id]["outputs"][source_slot]["type"]
            links.append([next_link, int(source_id), source_slot, int(target_id), target_slot, kind])
            by_id[target_id]["inputs"][target_slot]["link"] = next_link
            output_links[(source_id, source_slot)].append(next_link)
            next_link += 1

    for (source_id, source_slot), values in output_links.items():
        by_id[source_id]["outputs"][source_slot]["links"] = values

    return {
        "id": str(uuid.uuid5(uuid.NAMESPACE_URL, f"qwen-rapid-{variant}-{steps}-target-latent")),
        "revision": 0,
        "last_node_id": 8,
        "last_link_id": next_link - 1,
        "nodes": nodes,
        "links": links,
        "groups": [],
        "config": {},
        "extra": {"frontendVersion": "1.49.6"},
        "version": 0.4,
    }


def write(path: Path, value: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    for directory in (API_DIR, GUI_DIR):
        directory.mkdir(parents=True, exist_ok=True)
        for old in directory.glob("qwen-rapid-*-target-latent.json"):
            old.unlink()
    for variant in CHECKPOINTS:
        for steps in (4, 8):
            api = api_graph(variant, steps)
            name = f"qwen-rapid-{variant}-{steps}step-target-latent.json"
            write(API_DIR / name, api)
            write(GUI_DIR / name, gui_graph(api, variant, steps))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
