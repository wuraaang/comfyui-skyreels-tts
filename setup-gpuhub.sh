#!/bin/bash
# =============================================================================
# Setup script for GPUhub — reproduces the Dockerfile natively
# Run once on a fresh GPUhub pod, then "Save Image" to reuse
#
# IMPORTANT: Read GPUHUB.md before running this script.
# =============================================================================
set -e

export PATH="/root/miniconda3/bin:$PATH"
INSTALL_DIR="/root/autodl-tmp/ComfyUI"
REPO_RAW="https://raw.githubusercontent.com/wuraaang/comfyui-skyreels-tts/master"

# GitHub is blocked/throttled on GPUhub. We download repos as zip via a
# temporary redirect through HuggingFace or direct codeload URLs.
# If a download fails, the script uses scp fallback instructions.
download_github_zip() {
  local repo="$1" dest="$2"
  local name=$(basename "$repo")
  if [ -d "$dest/$name" ]; then
    echo "  $name: already exists, skipping"
    return 0
  fi
  echo "  $name: downloading..."
  # Try codeload (sometimes works), then archive URL
  local url="https://codeload.github.com/$repo/zip/refs/heads/main"
  if curl -sfL --max-time 60 "$url" -o "/tmp/$name.zip" 2>/dev/null; then
    cd "$dest" && unzip -q "/tmp/$name.zip" && mv "${name}-main" "$name" && rm "/tmp/$name.zip"
    echo "  $name: OK"
    return 0
  fi
  # Try master branch
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
echo "  Target: $INSTALL_DIR"
echo "============================================"
echo ""

# 1. System deps
echo "[1/7] System dependencies..."
apt-get update -qq && apt-get install -y -qq ffmpeg unzip > /dev/null 2>&1
echo "  Done."

# 2. PyTorch (skip if already installed via GPUhub framework)
echo "[2/7] PyTorch..."
if python3 -c "import torch; print(torch.__version__)" 2>/dev/null | grep -q "^2\."; then
  echo "  Already installed: $(python3 -c 'import torch; print(torch.__version__)')"
else
  echo "  Installing PyTorch 2.x + CUDA 12.8..."
  pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128 2>&1 | tail -1
fi

# 3. ComfyUI
echo "[3/7] ComfyUI..."
if [ -d "$INSTALL_DIR/main.py" ] || [ -f "$INSTALL_DIR/main.py" ]; then
  echo "  Already installed."
else
  echo "  Downloading ComfyUI (zip, ~15MB)..."
  curl -sfL --max-time 120 "https://codeload.github.com/comfyanonymous/ComfyUI/zip/refs/heads/master" -o /tmp/ComfyUI.zip
  if [ $? -ne 0 ]; then
    echo "  ERROR: GitHub download failed. Use scp fallback (see GPUHUB.md)"
    exit 1
  fi
  cd /root/autodl-tmp && unzip -q /tmp/ComfyUI.zip && mv ComfyUI-master ComfyUI && rm /tmp/ComfyUI.zip
fi
cd "$INSTALL_DIR"
echo "  Installing Python deps..."
pip install -r requirements.txt 2>&1 | tail -1

# 4. Custom nodes
echo "[4/7] Custom nodes..."
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

# 5. Install node deps
echo "[5/7] Installing node dependencies..."
for node in ComfyUI-WanVideoWrapper ComfyUI-MelBandRoFormer ComfyUI-VideoHelperSuite ComfyUI-KJNodes ComfyUI_Fill-ChatterBox; do
  if [ -f "$NODES_DIR/$node/requirements.txt" ]; then
    echo "  $node..."
    pip install -r "$NODES_DIR/$node/requirements.txt" 2>&1 | tail -1
  fi
done

# 6. Extra deps + custom long node
echo "[6/7] SageAttention + HF transfer + ChatterBox patch..."
pip install sageattention huggingface-hub hf_transfer 2>&1 | tail -1

# Download chatterbox_long_node.py (from GitHub raw — small file, usually works)
curl -sfL "$REPO_RAW/chatterbox_long_node.py" -o "$NODES_DIR/ComfyUI_Fill-ChatterBox/chatterbox_long_node.py"

# Patch __init__.py (only if not already patched)
INIT_FILE="$NODES_DIR/ComfyUI_Fill-ChatterBox/__init__.py"
if [ -f "$INIT_FILE" ] && ! grep -q "LONG_CLASS_MAPPINGS" "$INIT_FILE"; then
  sed -i '/^NODE_CLASS_MAPPINGS = {}/i from .chatterbox_long_node import NODE_CLASS_MAPPINGS as LONG_CLASS_MAPPINGS, NODE_DISPLAY_NAME_MAPPINGS as LONG_DISPLAY_NAME_MAPPINGS' "$INIT_FILE"
  sed -i '/NODE_DISPLAY_NAME_MAPPINGS.update(DIALOG_DISPLAY_NAME_MAPPINGS)/a NODE_CLASS_MAPPINGS.update(LONG_CLASS_MAPPINGS)\nNODE_DISPLAY_NAME_MAPPINGS.update(LONG_DISPLAY_NAME_MAPPINGS)' "$INIT_FILE"
  echo "  Patched __init__.py"
else
  echo "  __init__.py already patched (or not found)"
fi

# 7. Workflows + start script
echo "[7/7] Workflows + start script..."
mkdir -p "$INSTALL_DIR/user/default/workflows"
for wf in chatterbox-long-tts.json chatterbox-voice-clone.json skyreels-v3-talking-avatar.json; do
  curl -sfL "$REPO_RAW/workflows/$wf" -o "$INSTALL_DIR/user/default/workflows/$wf"
done
curl -sfL "$REPO_RAW/start.sh" -o "$INSTALL_DIR/start.sh"
chmod +x "$INSTALL_DIR/start.sh"

echo ""
echo "============================================"
echo "  Setup complete!"
echo "============================================"
echo ""
echo "To start ComfyUI:"
echo "  cd $INSTALL_DIR && bash start.sh"
echo ""
echo "Default port: 6006 (GPUhub). Override with: COMFYUI_PORT=8188 bash start.sh"
echo "First run downloads ~31GB of models from HuggingFace."
