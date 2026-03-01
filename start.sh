#!/bin/bash
set -e

# Ensure miniconda is in PATH (needed on GPUhub where it's not default)
export PATH="/root/miniconda3/bin:$PATH"
export HF_HUB_ENABLE_HF_TRANSFER=1

# Auto-detect install location: /app (Docker) or script directory (native)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -d "/app/models" ]; then
  MODELS_DIR="/app/models"
  COMFYUI_DIR="/app"
else
  MODELS_DIR="$SCRIPT_DIR/models"
  COMFYUI_DIR="$SCRIPT_DIR"
fi
PORT="${COMFYUI_PORT:-8188}"

# Auto-detect HuggingFace CLI (newer versions use 'hf', older use 'huggingface-cli')
if command -v hf &>/dev/null; then
  HF_CLI="hf"
elif command -v huggingface-cli &>/dev/null; then
  HF_CLI="huggingface-cli"
else
  echo "ERROR: Neither 'hf' nor 'huggingface-cli' found. Install huggingface-hub."
  exit 1
fi

echo "============================================"
echo "  ComfyUI — SkyReels V3 A2V + Chatterbox TTS"
echo "============================================"
echo ""
echo "Checking models (~31GB total)..."
echo "First launch: downloads run in parallel."
echo "Using HF CLI: $HF_CLI"
echo ""

# Create directories
mkdir -p "$MODELS_DIR/diffusion_models" \
         "$MODELS_DIR/text_encoders" \
         "$MODELS_DIR/vae" \
         "$MODELS_DIR/clip_vision"

# Helper: download only if not already cached
download_if_missing() {
  local target="$1" label="$2"; shift 2
  if [ ! -f "$target" ] && [ ! -d "$target" ]; then
    echo "$label Downloading..."
    "$@" && echo "$label Done." || echo "$label FAILED!"
  else
    echo "$label Cached."
  fi
}

# --- All downloads in parallel ---

# [1/5] SkyReels A2V diffusion model (18GB)
download_if_missing \
  "$MODELS_DIR/diffusion_models/SkyReelsV3/Wan21-SkyReelsV3-A2V_fp8_scaled_mixed.safetensors" \
  "[1/5] SkyReels A2V (18GB)" \
  $HF_CLI download Kijai/WanVideo_comfy_fp8_scaled \
    SkyReelsV3/Wan21-SkyReelsV3-A2V_fp8_scaled_mixed.safetensors \
    --local-dir "$MODELS_DIR/diffusion_models/" &

# [2/5] Text encoder umt5-xxl (11GB)
download_if_missing \
  "$MODELS_DIR/text_encoders/umt5-xxl-enc-bf16.safetensors" \
  "[2/5] umt5-xxl (11GB)" \
  $HF_CLI download Kijai/WanVideo_comfy \
    umt5-xxl-enc-bf16.safetensors \
    --local-dir "$MODELS_DIR/text_encoders/" &

# [3/5] VAE (243MB)
download_if_missing \
  "$MODELS_DIR/vae/Wan2_1_VAE_bf16.safetensors" \
  "[3/5] VAE (243MB)" \
  $HF_CLI download Kijai/WanVideo_comfy \
    Wan2_1_VAE_bf16.safetensors \
    --local-dir "$MODELS_DIR/vae/" &

# [4/5] CLIP Vision (1.2GB)
download_if_missing \
  "$MODELS_DIR/clip_vision/clip_vision_h.safetensors" \
  "[4/5] CLIP Vision (1.2GB)" \
  wget -q --show-progress -O "$MODELS_DIR/clip_vision/clip_vision_h.safetensors" \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors" &

# [5/5] MelBandRoFormer (436MB)
download_if_missing \
  "$MODELS_DIR/diffusion_models/MelBandRoformer_fp16.safetensors" \
  "[5/5] MelBandRoFormer (436MB)" \
  $HF_CLI download Kijai/MelBandRoFormer_comfy \
    MelBandRoformer_fp16.safetensors \
    --local-dir "$MODELS_DIR/diffusion_models/" &

# Wait for all parallel downloads
wait

echo ""
echo "============================================"
echo "  All models ready. Starting ComfyUI..."
echo "============================================"
echo ""
echo "Access ComfyUI at: http://localhost:$PORT"
echo "Note: Chatterbox models (~2GB) download automatically on first TTS run."
echo ""

cd "$COMFYUI_DIR"
python3 main.py --listen 0.0.0.0 --port "$PORT"
