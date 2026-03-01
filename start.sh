#!/bin/bash
set -e
export HF_HUB_ENABLE_HF_TRANSFER=1
MODELS_DIR="/app/models"
PORT="${COMFYUI_PORT:-8188}"

echo "============================================"
echo "  ComfyUI — SkyReels V3 A2V + Qwen3-TTS"
echo "============================================"
echo ""
echo "Checking models (~35GB total)..."
echo "First launch: ~2-3 min on datacenter, then cached."
echo ""

# Create directories
mkdir -p "$MODELS_DIR/diffusion_models" \
         "$MODELS_DIR/text_encoders" \
         "$MODELS_DIR/vae" \
         "$MODELS_DIR/clip_vision" \
         "$MODELS_DIR/Qwen3-TTS"

# --- SkyReels V3 A2V models ---

# Diffusion model (18GB) — file is in SkyReelsV3/ subdirectory in the repo
TARGET="$MODELS_DIR/diffusion_models/SkyReelsV3/Wan21-SkyReelsV3-A2V_fp8_scaled_mixed.safetensors"
if [ ! -f "$TARGET" ]; then
  echo "[1/7] Downloading SkyReels A2V diffusion model (18GB)..."
  huggingface-cli download Kijai/WanVideo_comfy_fp8_scaled \
    SkyReelsV3/Wan21-SkyReelsV3-A2V_fp8_scaled_mixed.safetensors \
    --local-dir "$MODELS_DIR/diffusion_models/"
else
  echo "[1/7] SkyReels A2V diffusion model — OK"
fi

# Text encoder (11GB) — file at repo root
TARGET="$MODELS_DIR/text_encoders/umt5-xxl-enc-bf16.safetensors"
if [ ! -f "$TARGET" ]; then
  echo "[2/7] Downloading text encoder umt5-xxl (11GB)..."
  huggingface-cli download Kijai/WanVideo_comfy \
    umt5-xxl-enc-bf16.safetensors \
    --local-dir "$MODELS_DIR/text_encoders/"
else
  echo "[2/7] Text encoder umt5-xxl — OK"
fi

# VAE (243MB) — file at repo root
TARGET="$MODELS_DIR/vae/Wan2_1_VAE_bf16.safetensors"
if [ ! -f "$TARGET" ]; then
  echo "[3/7] Downloading VAE (243MB)..."
  huggingface-cli download Kijai/WanVideo_comfy \
    Wan2_1_VAE_bf16.safetensors \
    --local-dir "$MODELS_DIR/vae/"
else
  echo "[3/7] VAE — OK"
fi

# CLIP Vision (1.2GB) — nested path in Comfy-Org repo, use wget for clean download
TARGET="$MODELS_DIR/clip_vision/clip_vision_h.safetensors"
if [ ! -f "$TARGET" ]; then
  echo "[4/7] Downloading CLIP Vision (1.2GB)..."
  wget -q --show-progress -O "$TARGET" \
    "https://huggingface.co/Comfy-Org/Wan_2.1_ComfyUI_repackaged/resolve/main/split_files/clip_vision/clip_vision_h.safetensors"
else
  echo "[4/7] CLIP Vision — OK"
fi

# MelBandRoFormer (436MB) — file at repo root
TARGET="$MODELS_DIR/diffusion_models/MelBandRoformer_fp16.safetensors"
if [ ! -f "$TARGET" ]; then
  echo "[5/7] Downloading MelBandRoFormer (436MB)..."
  huggingface-cli download Kijai/MelBandRoFormer_comfy \
    MelBandRoformer_fp16.safetensors \
    --local-dir "$MODELS_DIR/diffusion_models/"
else
  echo "[5/7] MelBandRoFormer — OK"
fi

# --- Qwen3-TTS models ---

# Qwen3-TTS Base 1.7B (~3.5GB) — full model repo
TARGET="$MODELS_DIR/Qwen3-TTS/Qwen3-TTS-12Hz-1.7B-Base"
if [ ! -d "$TARGET" ] || [ ! -f "$TARGET/config.json" ]; then
  echo "[6/7] Downloading Qwen3-TTS Base 1.7B (~3.5GB)..."
  huggingface-cli download Qwen/Qwen3-TTS-12Hz-1.7B-Base \
    --local-dir "$TARGET"
else
  echo "[6/7] Qwen3-TTS Base 1.7B — OK"
fi

# Qwen3-TTS Tokenizer (~500MB) — full model repo
TARGET="$MODELS_DIR/Qwen3-TTS/Qwen3-TTS-Tokenizer-12Hz"
if [ ! -d "$TARGET" ] || [ ! -f "$TARGET/config.json" ]; then
  echo "[7/7] Downloading Qwen3-TTS Tokenizer (~500MB)..."
  huggingface-cli download Qwen/Qwen3-TTS-Tokenizer-12Hz \
    --local-dir "$TARGET"
else
  echo "[7/7] Qwen3-TTS Tokenizer — OK"
fi

echo ""
echo "============================================"
echo "  All models ready. Starting ComfyUI..."
echo "============================================"
echo ""
echo "Access ComfyUI at: http://localhost:$PORT"
echo ""

python3 main.py --listen 0.0.0.0 --port "$PORT"
