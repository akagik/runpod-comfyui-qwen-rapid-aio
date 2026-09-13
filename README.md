# ComfyUI + Qwen Image Edit Rapid AIO

RunPod Pod / Serverless 用のNSFW v23専用Docker。標準構成はモデルをimageに含めず、
固定 revision と SHA-256 を使って Network Volume へ1回だけ取得する。必要なら1モデルを
image に bake することもできる。

Published image:

```text
ghcr.io/akagik/runpod-comfyui-qwen-rapid-aio:0.1.0
```

## 固定構成

- Runtime: `ghcr.io/akagik/runpod-comfyui-minimax-h3:0.1.4` の immutable digest
- ComfyUI: 0.34.0 / `12d5279438bfefc058a269eae805ceab6047777f`
- Rapid AIO: `691024f438640508f8aa86414863fc15edfb8a84`
- 既定モデル: `Qwen-Rapid-AIO-NSFW-v23.safetensors`
- Qwen encoder: 作者配布 v2、`target_latent` と最大4参照画像に対応
- sampling: Euler ancestral / beta、CFG 1.0、4 step または 8 step
- workflow解像度: 1344×768

## ローカル検査

```bash
python3 scripts/generate-workflows.py
python3 tests/test_bundle.py
python3 tests/verify_upstream.py
bash -n scripts/download-model.sh scripts/start.sh
```

## Thin imageをbuild

```bash
docker buildx build \
  --platform linux/amd64 \
  --load \
  -t qwen-rapid-aio:0.1.0 \
  .
```

モデルは `/workspace/models/checkpoints/` または
`/runpod-volume/models/checkpoints/` に置く。既定で不足時に固定revisionから自動取得する。

```bash
docker run --rm --gpus all -p 8188:8188 \
  -e MODE_TO_RUN=pod \
  -e RUNPOD_VOLUME_ROOT=/workspace \
  -e RAPID_VARIANT=nsfw-v23 \
  -e AUTO_DOWNLOAD_QWEN_RAPID=true \
  -v /local/persistent/workspace:/workspace \
  qwen-rapid-aio:0.1.0
```

公開・ungatedのため、現在はHugging Face token不要。将来必要になった場合もtokenを
Dockerfileの `ARG` や `ENV` に入れず、実行時secretとして渡す。

## モデルを含むimage

v23 NSFWをimageへ含める例。checkpointだけで28.43 GBあるため、通常はThin imageと
Network Volumeを推奨する。

```bash
docker buildx build \
  --platform linux/amd64 \
  --build-arg BAKE_MODEL=true \
  --load \
  -t qwen-rapid-aio:0.1.0-baked \
  .
```

tokenが必要な環境では、ローカル環境変数 `HF_TOKEN` をBuildKit secretとしてだけ渡す。

```bash
docker buildx build \
  --platform linux/amd64 \
  --build-arg BAKE_MODEL=true \
  --secret id=hf_token,env=HF_TOKEN \
  --load \
  -t qwen-rapid-aio:0.1.0-baked \
  .
```

## Checkpoint

`Qwen-Rapid-AIO-NSFW-v23.safetensors` だけを使用する。正確なrevision、サイズ、SHA-256は
[models.tsv](manifests/models.tsv) に固定している。既存ファイルのサイズまたはhashが異なる場合、
downloaderは上書きせず停止する。

## Workflow

`workflows/gui/` はComfyUI画面用、`workflows/api/` はAPI/Manager用。NSFW v23の4/8-stepを
用意した。全workflowで参照画像を `target_latent` と同じ1344×768へ合わせる。

起動時にはGUI workflowをユーザーディレクトリへ不足分だけコピーする。既存workflowは
上書きしない。Pod起動後、ComfyUI Webの `Workflows` から次の2本を直接開ける。

- `qwen-rapid-nsfw-v23-4step-target-latent.json`
- `qwen-rapid-nsfw-v23-8step-target-latent.json`

RunPod Templateの既定値:

```text
Image: ghcr.io/akagik/runpod-comfyui-qwen-rapid-aio:0.1.0
Container Disk: 40 GB
Ports: 8188/http, 22/tcp
MODE_TO_RUN=pod
RUNPOD_VOLUME_ROOT=/workspace
REQUIRE_NETWORK_VOLUME=true
AUTO_DOWNLOAD_QWEN_RAPID=true
REQUIRE_QWEN_RAPID_MODEL=true
```

## 未実施

GPU上の生成E2Eは別途記録する。モデルは起動前にNetwork Volumeへ置けるため、初回起動でも
checkpointの再取得は発生しない。
