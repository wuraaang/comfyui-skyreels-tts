#!/bin/bash
# Setup script for GPUhub — reproduces the Dockerfile natively
# Run once on a fresh GPUhub pod, then "Save Image" to reuse
set -e

export PATH="/root/miniconda3/bin:$PATH"
INSTALL_DIR="/root/autodl-tmp/ComfyUI"

echo "============================================"
echo "  Setup: ComfyUI + SkyReels + Chatterbox"
echo "============================================"

# 1. System deps
echo "[1/7] System dependencies..."
apt-get update -qq && apt-get install -y -qq ffmpeg > /dev/null 2>&1
echo "  Done."

# 2. PyTorch (skip if already installed via GPUhub framework)
echo "[2/7] PyTorch..."
if python3 -c "import torch; print(torch.__version__)" 2>/dev/null | grep -q "^2\."; then
  echo "  Already installed: $(python3 -c 'import torch; print(torch.__version__)')"
else
  pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cu128 2>&1 | tail -1
fi

# 3. ComfyUI
echo "[3/7] ComfyUI..."
if [ -d "$INSTALL_DIR" ]; then
  echo "  Already cloned."
else
  git clone https://github.com/comfyanonymous/ComfyUI.git "$INSTALL_DIR" 2>&1 | tail -1
fi
cd "$INSTALL_DIR"
pip install -r requirements.txt 2>&1 | tail -1

# 4. Custom nodes — stable
echo "[4/7] Custom nodes (stable)..."
cd "$INSTALL_DIR/custom_nodes"
for repo in \
  "https://github.com/kijai/ComfyUI-WanVideoWrapper" \
  "https://github.com/kijai/ComfyUI-MelBandRoFormer" \
  "https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite" \
  "https://github.com/kijai/ComfyUI-KJNodes"; do
  name=$(basename "$repo")
  if [ -d "$name" ]; then
    echo "  $name: already cloned"
  else
    git clone "$repo" 2>&1 | tail -1
    echo "  $name: cloned"
  fi
  if [ -f "$name/requirements.txt" ]; then
    pip install -r "$name/requirements.txt" 2>&1 | tail -1
  fi
done

# 5. ChatterBox node
echo "[5/7] ChatterBox node..."
cd "$INSTALL_DIR/custom_nodes"
if [ -d "ComfyUI_Fill-ChatterBox" ]; then
  echo "  Already cloned."
else
  git clone https://github.com/filliptm/ComfyUI_Fill-ChatterBox 2>&1 | tail -1
fi
pip install -r ComfyUI_Fill-ChatterBox/requirements.txt 2>&1 | tail -1

# 6. Extra deps + custom long node
echo "[6/7] SageAttention + HF transfer + custom node patch..."
pip install sageattention huggingface-hub hf_transfer 2>&1 | tail -1

# Download chatterbox_long_node.py from repo
REPO_RAW="https://raw.githubusercontent.com/wuraaang/comfyui-skyreels-tts/master"
curl -sL "$REPO_RAW/chatterbox_long_node.py" -o "$INSTALL_DIR/custom_nodes/ComfyUI_Fill-ChatterBox/chatterbox_long_node.py"

# Patch __init__.py (only if not already patched)
INIT_FILE="$INSTALL_DIR/custom_nodes/ComfyUI_Fill-ChatterBox/__init__.py"
if ! grep -q "LONG_CLASS_MAPPINGS" "$INIT_FILE"; then
  sed -i '/^NODE_CLASS_MAPPINGS = {}/i from .chatterbox_long_node import NODE_CLASS_MAPPINGS as LONG_CLASS_MAPPINGS, NODE_DISPLAY_NAME_MAPPINGS as LONG_DISPLAY_NAME_MAPPINGS' "$INIT_FILE"
  sed -i '/NODE_DISPLAY_NAME_MAPPINGS.update(DIALOG_DISPLAY_NAME_MAPPINGS)/a NODE_CLASS_MAPPINGS.update(LONG_CLASS_MAPPINGS)\nNODE_DISPLAY_NAME_MAPPINGS.update(LONG_DISPLAY_NAME_MAPPINGS)' "$INIT_FILE"
  echo "  Patched __init__.py"
else
  echo "  __init__.py already patched"
fi

# 7. Workflows + start script
echo "[7/7] Workflows + start script..."
mkdir -p "$INSTALL_DIR/user/default/workflows"
for wf in chatterbox-long-tts.json chatterbox-voice-clone.json skyreels-v3-talking-avatar.json; do
  curl -sL "$REPO_RAW/workflows/$wf" -o "$INSTALL_DIR/user/default/workflows/$wf"
done
curl -sL "$REPO_RAW/start.sh" -o "$INSTALL_DIR/start.sh"
chmod +x "$INSTALL_DIR/start.sh"

echo ""
echo "============================================"
echo "  Setup complete!"
echo "============================================"
echo ""
echo "To start ComfyUI:"
echo "  cd $INSTALL_DIR"
echo "  COMFYUI_PORT=6006 bash start.sh"
echo ""
echo "First run will download ~31GB of models."
