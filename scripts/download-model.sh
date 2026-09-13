#!/usr/bin/env bash
set -Eeuo pipefail

app_dir="${QWEN_RAPID_APP_DIR:-/opt/qwen-rapid-aio}"
manifest="${QWEN_RAPID_MODEL_MANIFEST:-$app_dir/manifests/models.tsv}"
variant="${RAPID_VARIANT:-nsfw-v23}"
python_bin="${VIRTUAL_ENV:-/opt/comfyui-venv}/bin/python"

if [[ -n "${RUNPOD_VOLUME_ROOT:-}" ]]; then
  volume_root="$RUNPOD_VOLUME_ROOT"
elif [[ -d /runpod-volume/models ]]; then
  volume_root=/runpod-volume
else
  volume_root=/workspace
fi

row="$(awk -F $'\t' -v wanted="$variant" 'NR > 1 && $1 == wanted { print; exit }' "$manifest")"
if [[ -z "$row" ]]; then
  echo "Unknown RAPID_VARIANT=$variant" >&2
  echo "Available: $(awk -F $'\t' 'NR > 1 {printf "%s%s", sep, $1; sep=", "}' "$manifest")" >&2
  exit 2
fi
IFS=$'\t' read -r _ repo revision repo_path target_rel expected_size expected_sha256 <<<"$row"

target="$volume_root/models/$target_rel"
receipt="$target.verified"
cache_dir="${HF_HOME_OVERRIDE:-$volume_root/hf-cache}/hub"
lock_file="$volume_root/.qwen-rapid-model-download.lock"
mkdir -p "$(dirname "$target")" "$cache_dir" "$(dirname "$lock_file")"

exec 9>"$lock_file"
flock 9

verify_full() {
  local path="$1" actual_size actual_sha256
  actual_size="$(stat -Lc %s "$path")"
  [[ "$actual_size" == "$expected_size" ]] || {
    echo "Size mismatch: $path expected=$expected_size actual=$actual_size" >&2
    return 1
  }
  actual_sha256="$(sha256sum "$path" | awk '{print $1}')"
  [[ "$actual_sha256" == "$expected_sha256" ]] || {
    echo "SHA-256 mismatch: $path expected=$expected_sha256 actual=$actual_sha256" >&2
    return 1
  }
}

write_receipt() {
  local temporary="$receipt.tmp.$$"
  printf 'variant=%s\nsize_bytes=%s\nsha256=%s\nrevision=%s\n' \
    "$variant" "$expected_size" "$expected_sha256" "$revision" >"$temporary"
  mv -f "$temporary" "$receipt"
}

if [[ -f "$target" ]]; then
  actual_size="$(stat -Lc %s "$target")"
  if [[ "$actual_size" == "$expected_size" ]] \
    && [[ -f "$receipt" ]] \
    && grep -qx "sha256=$expected_sha256" "$receipt" \
    && [[ ! "$target" -nt "$receipt" ]]; then
    echo "Already verified: $target"
    exit 0
  fi
  if verify_full "$target"; then
    write_receipt
    echo "Verified existing model: $target"
    exit 0
  fi
  echo "Refusing to replace an existing mismatched model: $target" >&2
  exit 3
elif [[ -e "$target" ]]; then
  echo "Refusing to replace a non-file target: $target" >&2
  exit 3
fi

if [[ -n "${HF_TOKEN_FILE:-}" && -s "${HF_TOKEN_FILE}" && -z "${HF_TOKEN:-}" ]]; then
  export HF_TOKEN="$(cat "${HF_TOKEN_FILE}")"
fi
export HF_HOME="${HF_HOME_OVERRIDE:-$volume_root/hf-cache}"
export HUGGINGFACE_HUB_CACHE="$cache_dir"
export HF_HUB_DOWNLOAD_TIMEOUT="${HF_HUB_DOWNLOAD_TIMEOUT:-120}"
export HF_HUB_ETAG_TIMEOUT="${HF_HUB_ETAG_TIMEOUT:-30}"
export HF_XET_HIGH_PERFORMANCE="${HF_XET_HIGH_PERFORMANCE:-1}"

echo "Downloading $repo@$revision:$repo_path"
source_path="$($python_bin - "$repo" "$revision" "$repo_path" "$cache_dir" <<'PY'
import os
import sys
from huggingface_hub import hf_hub_download

repo, revision, filename, cache_dir = sys.argv[1:]
token = os.environ.get("HF_TOKEN") or None
print(hf_hub_download(
    repo_id=repo,
    revision=revision,
    filename=filename,
    cache_dir=cache_dir,
    token=token,
))
PY
)"
source_path="$(readlink -f "$source_path")"
verify_full "$source_path"

temporary="$target.part.$$"
trap 'rm -f "$temporary"' EXIT
if ! ln "$source_path" "$temporary" 2>/dev/null; then
  cp --reflink=auto --sparse=always "$source_path" "$temporary"
fi
verify_full "$temporary"
mv -T "$temporary" "$target"
write_receipt
trap - EXIT
echo "Installed and verified: $target"
