#!/bin/bash
# =============================================================================
# Setup script for GPUhub — installs on SYSTEM DISK so "Save Image" captures it
# Run once on a fresh GPUhub pod, then "Save Image" to reuse
#
# Architecture:
#   /opt/ComfyUI/          → system disk (30GB) → CAPTURED in saved images
#   /root/autodl-tmp/models/ → data disk (50GB+) → NOT in images, start.sh downloads
#
# IMPORTANT: Read GPUHUB.md before running this script.
# =============================================================================
set -e

export PATH="/root/miniconda3/bin:$PATH"
export PIP_CACHE_DIR="/root/autodl-tmp/pip-cache"
mkdir -p "$PIP_CACHE_DIR"

INSTALL_DIR="/opt/ComfyUI"
MODELS_DIR="/root/autodl-tmp/comfyui-models"
REPO_RAW="https://raw.githubusercontent.com/wuraaang/comfyui-skyreels-tts/master"

# GitHub is blocked/throttled on GPUhub Singapore.
# Download repos as zip via codeload URLs (more reliable than git clone).
download_github_zip() {
  local repo="$1" dest="$2"
  local name=$(basename "$repo")
  if [ -d "$dest/$name" ]; then
    echo "  $name: already exists, skipping"
    return 0
  fi
  echo "  $name: downloading..."
  local url="https://codeload.github.com/$repo/zip/refs/heads/main"
  if curl -sfL --max-time 60 "$url" -o "/tmp/$name.zip" 2>/dev/null; then
    cd "$dest" && unzip -q "/tmp/$name.zip" && mv "${name}-main" "$name" && rm "/tmp/$name.zip"
    echo "  $name: OK"
    return 0
  fi
  url="https://codeload.github.com/$repo/zip/refs/heads/master"
  if curl -sfL --max-time 60 "$url" -o "/tmp/$name.zip" 2>/dev/null; then
    cd "$dest" && unzip -q "/tmp/$name.zip" && mv "${name}-master" "$name" && rm "/tmp/$name.zip"
    echo "  $name: OK"
    return 0
  fi
  echo "  $name: FAILED — GitHub blocked. Use scp fallback (see GPUHUB.md)"
  return 1
}

echo "============================================"
echo "  Setup: ComfyUI + SkyReels + Chatterbox"
echo "  Install: $INSTALL_DIR (system disk)"
echo "  Models:  $MODELS_DIR (data disk)"
echo "============================================"
echo ""

# 1. System deps
echo "[1/8] System dependencies..."
apt-get update -qq && apt-get install -y -qq ffmpeg unzip > /dev/null 2>&1
echo "  Done."

# 2. PyTorch (skip if already installed via GPUhub framework)
echo "[2/8] PyTorch..."
if python3 -c "import torch; print(torch.__version__)" 2>/dev/null | grep -q "^2\."; then
  echo "  Already installed: $(python3 -c 'import torch; print(torch.__version__)')"
else
  echo "  Installing PyTorch 2.x + CUDA 12.8..."
  pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128 --timeout 300 2>&1 | tail -1
fi

# 3. ComfyUI on system disk
echo "[3/8] ComfyUI..."
if [ -f "$INSTALL_DIR/main.py" ]; then
  echo "  Already installed."
else
  echo "  Downloading ComfyUI (zip, ~15MB)..."
  curl -sfL --max-time 120 "https://codeload.github.com/comfyanonymous/ComfyUI/zip/refs/heads/master" -o /tmp/ComfyUI.zip
  if [ $? -ne 0 ]; then
    echo "  ERROR: GitHub download failed. Use scp fallback (see GPUHUB.md)"
    exit 1
  fi
  unzip -q /tmp/ComfyUI.zip -d /opt/ && mv /opt/ComfyUI-master "$INSTALL_DIR" && rm /tmp/ComfyUI.zip
fi
cd "$INSTALL_DIR"
echo "  Installing Python deps..."
pip install -r requirements.txt --timeout 300 2>&1 | tail -1

# 4. Symlink models → data disk (not captured in image, too large)
echo "[4/8] Models symlink..."
mkdir -p "$MODELS_DIR"/{checkpoints,clip,clip_vision,vae,loras,controlnet,upscale_models,diffusion_models,text_encoders}
if [ -d "$INSTALL_DIR/models" ] && [ ! -L "$INSTALL_DIR/models" ]; then
  mv "$INSTALL_DIR/models" "$INSTALL_DIR/models.bak"
fi
ln -sfn "$MODELS_DIR" "$INSTALL_DIR/models"
echo "  $INSTALL_DIR/models → $MODELS_DIR"

# 5. Custom nodes
echo "[5/8] Custom nodes..."
NODES_DIR="$INSTALL_DIR/custom_nodes"
FAILED=0
for repo in \
  "kijai/ComfyUI-WanVideoWrapper" \
  "kijai/ComfyUI-MelBandRoFormer" \
  "Kosinkadink/ComfyUI-VideoHelperSuite" \
  "kijai/ComfyUI-KJNodes" \
  "filliptm/ComfyUI_Fill-ChatterBox"; do
  download_github_zip "$repo" "$NODES_DIR" || FAILED=1
done
if [ "$FAILED" = "1" ]; then
  echo ""
  echo "  WARNING: Some nodes failed to download. GitHub is likely blocked."
  echo "  Use the SCP fallback method described in GPUHUB.md"
  echo ""
fi

# 6. Install node deps
echo "[6/8] Installing node dependencies..."
for node in ComfyUI-WanVideoWrapper ComfyUI-MelBandRoFormer ComfyUI-VideoHelperSuite ComfyUI-KJNodes ComfyUI_Fill-ChatterBox; do
  if [ -f "$NODES_DIR/$node/requirements.txt" ]; then
    echo "  $node..."
    pip install -r "$NODES_DIR/$node/requirements.txt" --timeout 300 2>&1 | tail -1
  fi
done

# 7. Extra deps + custom long node
echo "[7/8] SageAttention + HF transfer + ChatterBox patch..."
pip install sageattention huggingface-hub hf_transfer --timeout 300 2>&1 | tail -1

curl -sfL "$REPO_RAW/chatterbox_long_node.py" -o "$NODES_DIR/ComfyUI_Fill-ChatterBox/chatterbox_long_node.py"

INIT_FILE="$NODES_DIR/ComfyUI_Fill-ChatterBox/__init__.py"
if [ -f "$INIT_FILE" ] && ! grep -q "LONG_CLASS_MAPPINGS" "$INIT_FILE"; then
  sed -i '/^NODE_CLASS_MAPPINGS = {}/i from .chatterbox_long_node import NODE_CLASS_MAPPINGS as LONG_CLASS_MAPPINGS, NODE_DISPLAY_NAME_MAPPINGS as LONG_DISPLAY_NAME_MAPPINGS' "$INIT_FILE"
  sed -i '/NODE_DISPLAY_NAME_MAPPINGS.update(DIALOG_DISPLAY_NAME_MAPPINGS)/a NODE_CLASS_MAPPINGS.update(LONG_CLASS_MAPPINGS)\nNODE_DISPLAY_NAME_MAPPINGS.update(LONG_DISPLAY_NAME_MAPPINGS)' "$INIT_FILE"
  echo "  Patched __init__.py"
else
  echo "  __init__.py already patched (or not found)"
fi

# 8. Workflows + start script + verification
echo "[8/8] Workflows + start script + verification..."
mkdir -p "$INSTALL_DIR/user/default/workflows"
for wf in chatterbox-long-tts.json chatterbox-voice-clone.json skyreels-v3-talking-avatar.json; do
  curl -sfL "$REPO_RAW/workflows/$wf" -o "$INSTALL_DIR/user/default/workflows/$wf"
done
curl -sfL "$REPO_RAW/start.sh" -o "$INSTALL_DIR/start.sh"
chmod +x "$INSTALL_DIR/start.sh"

echo ""
echo "  Verification..."
pip check 2>&1 | head -5 || true
python3 -c "import torch; print(f'  PyTorch {torch.__version__}, CUDA {torch.version.cuda}, GPU: {torch.cuda.get_device_name(0)}')" 2>/dev/null || echo "  (GPU check skipped — no GPU available during setup)"

echo ""
echo "════════════════════════════════════════════"
echo "  Setup complete!"
echo "════════════════════════════════════════════"
echo ""
echo "  Next steps:"
echo "    1. Test:  bash $INSTALL_DIR/start.sh"
echo "    2. If OK: shutdown the instance"
echo "    3. Save:  More > Save Image (GPUhub console)"
echo "    4. The image is now reusable by anyone"
echo ""
echo "  First run downloads ~31GB of models (~5-10 min)."
echo "════════════════════════════════════════════"
