# syntax=docker/dockerfile:1.7

# Thin derivative of the verified RunPod ComfyUI runtime. The default build
# contains no model weights; BAKE_MODEL=true adds exactly one pinned checkpoint.
ARG BASE_IMAGE=ghcr.io/akagik/runpod-comfyui-minimax-h3:0.1.4@sha256:8447ef7693fe42429528bc90f3aab68eb956f20a13216711bab27124149c377f
ARG RUNPOD_PLATFORM=linux/amd64
FROM --platform=${RUNPOD_PLATFORM} ${BASE_IMAGE}

ARG IMAGE_VERSION=0.1.1
ARG BAKE_MODEL=false
ARG COMFYUI_COMMIT=12d5279438bfefc058a269eae805ceab6047777f
ARG COMFYUI_VERSION=0.34.0

LABEL org.opencontainers.image.title="RunPod ComfyUI Qwen Image Edit Rapid AIO" \
      org.opencontainers.image.description="Pinned ComfyUI runtime for Qwen Image Edit Rapid AIO NSFW v23" \
      org.opencontainers.image.source="https://github.com/akagik/runpod-comfyui-qwen-rapid-aio" \
      org.opencontainers.image.licenses="GPL-3.0-only" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      io.runpod.comfyui.base="ghcr.io/akagik/runpod-comfyui-minimax-h3:0.1.4@sha256:8447ef7693fe42429528bc90f3aab68eb956f20a13216711bab27124149c377f" \
      io.runpod.comfyui.version="${COMFYUI_VERSION}" \
      io.runpod.comfyui.commit="${COMFYUI_COMMIT}" \
      io.runpod.qwen.rapid.revision="691024f438640508f8aa86414863fc15edfb8a84" \
      io.runpod.qwen.encoder.patch.sha256="9df96288f466ca03f7d7fa8587ad53c8021b784f42daabdc1f59a61b71c40238"

ENV QWEN_RAPID_APP_DIR=/opt/qwen-rapid-aio \
    RAPID_VARIANT=nsfw-v23 \
    AUTO_DOWNLOAD_QWEN_RAPID=true \
    REQUIRE_QWEN_RAPID_MODEL=true \
    REQUIRE_MINIMAX_MODELS=false

SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Recreate the exact ComfyUI revision used by the prior A100 Rapid v23
# benchmark. The parent supplies the tested CUDA/PyTorch/RunPod runtime.
RUN git init /tmp/ComfyUI \
    && git -C /tmp/ComfyUI remote add origin https://github.com/Comfy-Org/ComfyUI.git \
    && git -C /tmp/ComfyUI fetch --depth 1 origin "${COMFYUI_COMMIT}" \
    && git -C /tmp/ComfyUI checkout --detach FETCH_HEAD \
    && test "$(git -C /tmp/ComfyUI rev-parse HEAD)" = "${COMFYUI_COMMIT}" \
    && rm -rf /tmp/ComfyUI/.git "${COMFYUI_DIR}" \
    && mv /tmp/ComfyUI "${COMFYUI_DIR}" \
    && uv pip install --python "${VIRTUAL_ENV}/bin/python" \
      comfyui-frontend-package==1.49.6 \
      comfyui-workflow-templates==0.11.48 \
      comfyui-embedded-docs==0.5.10 \
      comfy-kitchen==0.2.31 \
      comfy-aimdo==0.4.15 \
    && "${VIRTUAL_ENV}/bin/python" -m pip check

COPY config/ "${QWEN_RAPID_APP_DIR}/config/"
COPY manifests/ "${QWEN_RAPID_APP_DIR}/manifests/"
COPY patches/nodes_qwen.v2.py "${QWEN_RAPID_APP_DIR}/patches/nodes_qwen.v2.py"
COPY scripts/ "${QWEN_RAPID_APP_DIR}/scripts/"
COPY tests/ "${QWEN_RAPID_APP_DIR}/tests/"
COPY workflows/ "${QWEN_RAPID_APP_DIR}/workflows/"
COPY Dockerfile LICENSE UPSTREAM.md README.md "${QWEN_RAPID_APP_DIR}/"

# Phr00t's v2 file is a replacement for the built-in node, not an additional
# custom node. Verify both sides before replacing it so an upstream base change
# cannot silently patch an incompatible file.
RUN test "$(sha256sum "${COMFYUI_DIR}/comfy_extras/nodes_qwen.py" | awk '{print $1}')" = \
      "b8d18d9f897c4bd5a4b2651b30643bed277f1808e033c9c376dc21025fed00a5" \
    && test "$(sha256sum "${QWEN_RAPID_APP_DIR}/patches/nodes_qwen.v2.py" | awk '{print $1}')" = \
      "9df96288f466ca03f7d7fa8587ad53c8021b784f42daabdc1f59a61b71c40238" \
    && install -m 0644 "${QWEN_RAPID_APP_DIR}/patches/nodes_qwen.v2.py" \
      "${COMFYUI_DIR}/comfy_extras/nodes_qwen.py" \
    && chmod +x "${QWEN_RAPID_APP_DIR}/scripts/"*.sh \
    && "${VIRTUAL_ENV}/bin/python" -m py_compile "${COMFYUI_DIR}/comfy_extras/nodes_qwen.py" \
    && "${VIRTUAL_ENV}/bin/python" "${QWEN_RAPID_APP_DIR}/scripts/generate-workflows.py" \
    && "${VIRTUAL_ENV}/bin/python" "${QWEN_RAPID_APP_DIR}/tests/test_bundle.py"

# Optional self-contained image. The Hugging Face repository is public today,
# so no secret is normally required. If that changes, use a BuildKit secret;
# the token is read from /run/secrets/hf_token and never committed to a layer.
RUN --mount=type=secret,id=hf_token,required=false \
    if [[ "${BAKE_MODEL}" == "true" ]]; then \
      RAPID_VARIANT=nsfw-v23 \
      RUNPOD_VOLUME_ROOT="${COMFYUI_DIR}" \
      HF_HOME_OVERRIDE=/tmp/qwen-rapid-hf-cache \
      HF_TOKEN_FILE=/run/secrets/hf_token \
      "${QWEN_RAPID_APP_DIR}/scripts/download-model.sh"; \
      rm -rf /tmp/qwen-rapid-hf-cache; \
    elif [[ "${BAKE_MODEL}" != "false" ]]; then \
      echo "BAKE_MODEL must be true or false" >&2; exit 2; \
    fi

RUN cd "${COMFYUI_DIR}" \
    && timeout 300 "${VIRTUAL_ENV}/bin/python" main.py \
      --quick-test-for-ci --cpu \
      --extra-model-paths-config "${QWEN_RAPID_APP_DIR}/config/extra_model_paths.yaml"

WORKDIR ${QWEN_RAPID_APP_DIR}
CMD ["/opt/qwen-rapid-aio/scripts/start.sh"]
