#!/bin/bash
# =============================================================================
# Start script — downloads models (if missing) then launches ComfyUI
# Runs at each session. Models live on data disk (not in saved image).
# =============================================================================
set -e

export PATH="/root/miniconda3/bin:$PATH"
export HF_HUB_ENABLE_HF_TRANSFER=1
export HF_HOME="/root/autodl-tmp/cache"

# Paths — system disk for code, data disk for models
COMFY_DIR="/opt/ComfyUI"
MODELS_DIR="/root/autodl-tmp/comfyui-models"
PORT="${COMFYUI_PORT:-6006}"

# Docker fallback: if /app exists, use Docker paths
if [ -f "/app/main.py" ]; then
  COMFY_DIR="/app"
  MODELS_DIR="/app/models"
fi

# Recreate models symlink if data disk was wiped (15-day shutdown)
mkdir -p "$MODELS_DIR"/{diffusion_models,text_encoders,vae,clip_vision}
if [ "$COMFY_DIR" = "/opt/ComfyUI" ]; then
  ln -sfn "$MODELS_DIR" "$COMFY_DIR/models"
fi

# Auto-detect HuggingFace CLI
if command -v hf &>/dev/null; then
  HF_CLI="hf"
elif command -v huggingface-cli &>/dev/null; then
  HF_CLI="huggingface-cli"
else
  echo "ERROR: Neither 'hf' nor 'huggingface-cli' found."
  exit 1
fi

echo "============================================"
echo "  ComfyUI — SkyReels V3 A2V + Chatterbox TTS"
echo "============================================"
echo ""
echo "  ComfyUI : $COMFY_DIR"
echo "  Models  : $MODELS_DIR"
echo "  Port    : $PORT"
echo "  HF CLI  : $HF_CLI"
echo ""

# Download helper: skip if cached, fallback to hf-mirror if HF fails
download_hf() {
  local target="$1" label="$2" repo="$3" file="$4" dest_dir="$5"
  if [ -f "$target" ]; then
    echo "$label Cached."
    return 0
  fi
  echo "$label Downloading..."
  if $HF_CLI download "$repo" "$file" --local-dir "$dest_dir" --quiet 2>/dev/null; then
    echo "$label Done."
  else
    echo "$label Retry via hf-mirror..."
    HF_ENDPOINT=https://hf-mirror.com $HF_CLI download "$repo" "$file" --local-dir "$dest_dir" --quiet && \
      echo "$label Done." || echo "$label FAILED!"
  fi
}

echo "Checking models (~31GB total)..."
echo ""

# --- All downloads in parallel ---

# [1/5] SkyReels A2V diffusion model (18GB)
download_hf \
  "$MODELS_DIR/diffusion_models/SkyReelsV3/Wan21-SkyReelsV3-A2V_fp8_scaled_mixed.safetensors" \
  "[1/5] SkyReels A2V (18GB)" \
  "Kijai/WanVideo_comfy_fp8_scaled" \
  "SkyReelsV3/Wan21-SkyReelsV3-A2V_fp8_scaled_mixed.safetensors" \
  "$MODELS_DIR/diffusion_models/" &

# [2/5] Text encoder umt5-xxl (11GB)
download_hf \
  "$MODELS_DIR/text_encoders/umt5-xxl-enc-bf16.safetensors" \
  "[2/5] umt5-xxl (11GB)" \
  "Kijai/WanVideo_comfy" \
  "umt5-xxl-enc-bf16.safetensors" \
  "$MODELS_DIR/text_encoders/" &

# [3/5] VAE (243MB)
download_hf \
  "$MODELS_DIR/vae/Wan2_1_VAE_bf16.safetensors" \
  "[3/5] VAE (243MB)" \
  "Kijai/WanVideo_comfy" \
  "Wan2_1_VAE_bf16.safetensors" \
  "$MODELS_DIR/vae/" &

# [4/5] CLIP Vision (1.2GB)
download_hf \
  "$MODELS_DIR/clip_vision/clip_vision_h.safetensors" \
  "[4/5] CLIP Vision (1.2GB)" \
  "Comfy-Org/Wan_2.1_ComfyUI_repackaged" \
  "split_files/clip_vision/clip_vision_h.safetensors" \
  "$MODELS_DIR/clip_vision/" &

# [5/5] MelBandRoFormer (436MB)
download_hf \
  "$MODELS_DIR/diffusion_models/MelBandRoformer_fp16.safetensors" \
  "[5/5] MelBandRoFormer (436MB)" \
  "Kijai/MelBandRoFormer_comfy" \
  "MelBandRoformer_fp16.safetensors" \
  "$MODELS_DIR/diffusion_models/" &

# Wait for all parallel downloads
wait

echo ""
echo "============================================"
echo "  All models ready. Starting ComfyUI..."
echo "============================================"
echo ""
echo "  Local:  http://localhost:$PORT"
echo "  GPUhub: https://region.gpuhub.com:8443"
echo "  Note: Chatterbox models (~2GB) download on first TTS run."
echo ""

cd "$COMFY_DIR"
env -u HTTPS_PROXY -u HTTP_PROXY -u http_proxy -u https_proxy \
  python3 main.py --listen 0.0.0.0 --port "$PORT"
