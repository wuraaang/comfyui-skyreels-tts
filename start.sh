#!/bin/bash
# =============================================================================
# Smart Start — ComfyUI + SkyReels V3 A2V + Chatterbox TTS
#
# Strategy: launch ComfyUI FAST, download heavy models in background
#   Phase 1: small models (~1.9 GB, ~2 min) — blocking
#   Phase 2: big models (~29 GB) — background while user uses ComfyUI
#   Result: UI accessible in < 3 min, TTS ready immediately,
#           video generation ready when Phase 2 completes
#
# Storage (GPUhub):
#   autodl-fs  (200GB, persistent, survives shutdown/release) → models HERE
#   autodl-tmp (50GB, SSD, wiped on release)                  → cache only
#   /opt/      (30GB, system, saved in image)                 → ComfyUI code
#
# If autodl-fs has models → instant start (~30s)
# If not → Phase 1 (~2 min) then Phase 2 in background (~30 min)
# =============================================================================
set -e

export PATH="/root/miniconda3/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HF_HOME="/root/autodl-tmp/cache"

# --- Paths ---
COMFY_DIR="/opt/ComfyUI"
PORT="${COMFYUI_PORT:-6006}"
DOWNLOAD_LOG="/tmp/model-download.log"

# Docker fallback
if [ -f "/app/main.py" ]; then
  COMFY_DIR="/app"
  MODELS_DIR="/app/models"
else
  # GPUhub: prefer autodl-fs (persistent), fallback to autodl-tmp
  if [ -d "/root/autodl-fs" ]; then
    MODELS_DIR="/root/autodl-fs/models"
  else
    MODELS_DIR="/root/autodl-tmp/comfyui-models"
  fi
fi

# Create dirs + symlink
mkdir -p "$MODELS_DIR"/{diffusion_models/SkyReelsV3,text_encoders,vae,clip_vision}
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

# Download helper: skip if cached, fallback to hf-mirror
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

# Check if ALL models are already cached
all_cached() {
  [ -f "$MODELS_DIR/vae/Wan2_1_VAE_bf16.safetensors" ] && \
  [ -f "$MODELS_DIR/clip_vision/clip_vision_h.safetensors" ] && \
  [ -f "$MODELS_DIR/diffusion_models/MelBandRoformer_fp16.safetensors" ] && \
  [ -f "$MODELS_DIR/text_encoders/umt5-xxl-enc-bf16.safetensors" ] && \
  [ -f "$MODELS_DIR/diffusion_models/SkyReelsV3/Wan21-SkyReelsV3-A2V_fp8_scaled_mixed.safetensors" ]
}

echo "============================================"
echo "  ComfyUI — SkyReels V3 A2V + Chatterbox TTS"
echo "============================================"
echo ""
echo "  ComfyUI : $COMFY_DIR"
echo "  Models  : $MODELS_DIR"
echo "  Port    : $PORT"
echo "  HF CLI  : $HF_CLI"
echo ""

# =============================================================================
# FAST PATH: all models cached → start immediately
# =============================================================================
if all_cached; then
  echo "All models cached. Starting ComfyUI..."
  echo ""
  echo "  Local:  http://localhost:$PORT"
  echo "  GPUhub: check your GPUhub console for the public URL"
  echo ""
  cd "$COMFY_DIR"
  exec env -u HTTPS_PROXY -u HTTP_PROXY -u http_proxy -u https_proxy \
    python3 main.py --listen 0.0.0.0 --port "$PORT"
fi

# =============================================================================
# SMART START: Phase 1 (small models) → launch ComfyUI → Phase 2 (background)
# =============================================================================
echo "First launch detected. Downloading models..."
echo ""

# --- Phase 1: Small models (~1.9 GB, ~2 min) — blocking ---
echo "=== Phase 1/2: Essential models (1.9 GB, ~2 min) ==="
echo ""

download_hf \
  "$MODELS_DIR/vae/Wan2_1_VAE_bf16.safetensors" \
  "[1/5] VAE (243MB)" \
  "Kijai/WanVideo_comfy" \
  "Wan2_1_VAE_bf16.safetensors" \
  "$MODELS_DIR/vae/" &

download_hf \
  "$MODELS_DIR/clip_vision/clip_vision_h.safetensors" \
  "[2/5] CLIP Vision (1.2GB)" \
  "Comfy-Org/Wan_2.1_ComfyUI_repackaged" \
  "split_files/clip_vision/clip_vision_h.safetensors" \
  "$MODELS_DIR/clip_vision/" &

download_hf \
  "$MODELS_DIR/diffusion_models/MelBandRoformer_fp16.safetensors" \
  "[3/5] MelBandRoFormer (436MB)" \
  "Kijai/MelBandRoFormer_comfy" \
  "MelBandRoformer_fp16.safetensors" \
  "$MODELS_DIR/diffusion_models/" &

wait
echo ""
echo "Phase 1 complete."
echo ""

# --- Launch ComfyUI NOW ---
echo "============================================"
echo "  Starting ComfyUI (Phase 2 downloads in background)"
echo "============================================"
echo ""
echo "  Local:  http://localhost:$PORT"
echo "  GPUhub: check your GPUhub console for the public URL"
echo ""
echo "  TTS workflows:   ready (Chatterbox auto-downloads ~2GB on first use)"
echo "  Video workflows:  downloading 2 large models in background..."
echo "                    Progress: tail -f $DOWNLOAD_LOG"
echo "                    Video generation available when download completes."
echo "  Next launch:      instant (models saved to persistent storage)"
echo ""

cd "$COMFY_DIR"
env -u HTTPS_PROXY -u HTTP_PROXY -u http_proxy -u https_proxy \
  python3 main.py --listen 0.0.0.0 --port "$PORT" &
COMFY_PID=$!

# --- Phase 2: Big models (~29 GB) — background ---
(
  echo "=== Phase 2/2: Large models (background download) ==="
  echo "Started: $(date)"
  echo ""

  download_hf \
    "$MODELS_DIR/text_encoders/umt5-xxl-enc-bf16.safetensors" \
    "[4/5] umt5-xxl (11GB)" \
    "Kijai/WanVideo_comfy" \
    "umt5-xxl-enc-bf16.safetensors" \
    "$MODELS_DIR/text_encoders/"

  download_hf \
    "$MODELS_DIR/diffusion_models/SkyReelsV3/Wan21-SkyReelsV3-A2V_fp8_scaled_mixed.safetensors" \
    "[5/5] SkyReels A2V (18GB)" \
    "Kijai/WanVideo_comfy_fp8_scaled" \
    "SkyReelsV3/Wan21-SkyReelsV3-A2V_fp8_scaled_mixed.safetensors" \
    "$MODELS_DIR/diffusion_models/"

  echo ""
  echo "============================================"
  echo "  All models downloaded! $(date)"
  echo "  Refresh the model list in ComfyUI to use video workflows."
  echo "============================================"
) > "$DOWNLOAD_LOG" 2>&1 &

# Wait for ComfyUI process (keeps the script alive)
wait $COMFY_PID
