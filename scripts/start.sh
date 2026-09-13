#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="${QWEN_RAPID_APP_DIR:-/opt/qwen-rapid-aio}"
manifest="${QWEN_RAPID_MODEL_MANIFEST:-$app_dir/manifests/models.tsv}"
variant="${RAPID_VARIANT:-nsfw-v23}"
mode="${MODE_TO_RUN:-serverless}"

if [[ -n "${RUNPOD_VOLUME_ROOT:-}" ]]; then
  volume_root="$RUNPOD_VOLUME_ROOT"
elif [[ -d /runpod-volume/models ]]; then
  volume_root=/runpod-volume
else
  volume_root=/workspace
fi
export RUNPOD_VOLUME_ROOT="$volume_root"
export REQUIRE_MINIMAX_MODELS=false

row="$(awk -F $'\t' -v wanted="$variant" 'NR > 1 && $1 == wanted { print; exit }' "$manifest")"
[[ -n "$row" ]] || { echo "Unknown RAPID_VARIANT=$variant" >&2; exit 2; }
IFS=$'\t' read -r _ _ _ _ target_rel expected_size _ <<<"$row"
volume_model="$volume_root/models/$target_rel"
baked_model="${COMFYUI_DIR:-/opt/ComfyUI}/models/$target_rel"

if [[ "${AUTO_DOWNLOAD_QWEN_RAPID:-false}" == true && ! -s "$volume_model" && ! -s "$baked_model" ]]; then
  "$app_dir/scripts/download-model.sh"
fi

if [[ "${REQUIRE_QWEN_RAPID_MODEL:-true}" == true ]]; then
  model_path="$volume_model"
  [[ -s "$model_path" ]] || model_path="$baked_model"
  if [[ ! -s "$model_path" ]]; then
    echo "Missing Qwen Rapid model for $variant." >&2
    echo "Set AUTO_DOWNLOAD_QWEN_RAPID=true or run $app_dir/scripts/download-model.sh." >&2
    exit 4
  fi
  actual_size="$(stat -Lc %s "$model_path")"
  [[ "$actual_size" == "$expected_size" ]] || {
    echo "Model size mismatch: $model_path expected=$expected_size actual=$actual_size" >&2
    exit 4
  }
fi

worker_id="${RUNPOD_POD_ID:-${RUNPOD_WORKER_ID:-${HOSTNAME:-worker}}}"
worker_id="$(printf '%s' "$worker_id" | tr -cd 'A-Za-z0-9._-')"
[[ -n "$worker_id" ]] || worker_id=worker
if [[ -n "${COMFY_USER_DIR:-}" ]]; then
  user_dir="$COMFY_USER_DIR"
elif [[ "$mode" == serverless ]]; then
  user_dir="${COMFY_RUNTIME_ROOT:-/tmp/comfyui/$worker_id}/user"
else
  user_dir="${COMFY_RUNTIME_ROOT:-$volume_root/pods/$worker_id}/user"
fi
workflow_dir="$user_dir/default/workflows"
mkdir -p "$workflow_dir"
for workflow in "$app_dir"/workflows/gui/*.json; do
  target="$workflow_dir/$(basename "$workflow")"
  [[ -e "$target" ]] || cp "$workflow" "$target"
done

echo "qwen_rapid_variant=$variant"
echo "qwen_rapid_model=${model_path:-optional}"
echo "qwen_target_latent_encoder=enabled"
exec env APP_DIR=/opt/runpod-comfyui \
  /opt/runpod-comfyui/scripts/start.sh

