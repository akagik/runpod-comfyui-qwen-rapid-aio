# Upstream pins

- ComfyUI runtime parent (linux/amd64 manifest): `ghcr.io/akagik/runpod-comfyui-minimax-h3:0.1.4@sha256:8447ef7693fe42429528bc90f3aab68eb956f20a13216711bab27124149c377f`
- Parent OCI index: `sha256:09e695790b1eb815a92c382f384313712c621172e031dd2cf136a0a7a9ea053e`
- Parent ComfyUI before replacement: `dec5d9450a5290bcf63430409ea41018e67f41c3` / 0.30.2
- Image ComfyUI: `12d5279438bfefc058a269eae805ceab6047777f` / 0.34.0
- Stock `comfy_extras/nodes_qwen.py` SHA-256: `b8d18d9f897c4bd5a4b2651b30643bed277f1808e033c9c376dc21025fed00a5`
- Rapid AIO repository revision: `691024f438640508f8aa86414863fc15edfb8a84`
- Vendored author v2 Qwen encoder source: <https://huggingface.co/Phr00t/Qwen-Image-Edit-Rapid-AIO/blob/691024f438640508f8aa86414863fc15edfb8a84/fixed-textencode-node/nodes_qwen.v2.py>
- Vendored author v2 encoder SHA-256: `9df96288f466ca03f7d7fa8587ad53c8021b784f42daabdc1f59a61b71c40238`

The upstream Hugging Face repository declares Apache-2.0 in model metadata, but
does not include a standalone LICENSE file in its tree. Rapid AIO merges several
external accelerators and LoRAs. Treat the declared license as repository
metadata rather than a complete component provenance audit.
