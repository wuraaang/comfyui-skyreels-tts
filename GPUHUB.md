# Building the Image from Scratch (GPUhub)

This guide is for **rebuilding** the image on a fresh GPUhub instance. If you're just using an existing image, see [README.md](README.md).

## Known Issues

### 1. GitHub is blocked/throttled
**Symptom:** `git clone` and `wget` to github.com fail (timeout, `fetch-pack: invalid index-pack output`, `curl 92 HTTP/2 stream was not closed cleanly`).

**Cause:** GPUhub's Singapore network throttles or blocks connections to GitHub. This is a provider limitation, not a script issue.

**Impact:** The `setup-gpuhub.sh` script needs to download 6 GitHub repos (ComfyUI + 5 custom nodes). If GitHub is blocked, these downloads fail.

**Solution:** Use the **SCP fallback** (see below). Download repos from your local machine (where GitHub works) and upload via `scp`.

### 2. PATH not set in non-interactive mode
**Symptom:** `python3: command not found`, `pip: command not found`, `hf: command not found`

**Cause:** On GPUhub, Python is installed in `/root/miniconda3/bin/` but this path is NOT in `$PATH` when running commands via non-interactive SSH (`ssh host "command"`). It's only loaded in interactive mode (via `.bashrc`).

**Solution:** Always add at the beginning of scripts or commands:
```bash
export PATH="/root/miniconda3/bin:$PATH"
```
Both `setup-gpuhub.sh` and `start.sh` do this automatically.

### 3. `huggingface-cli` renamed to `hf`
**Symptom:** `huggingface-cli: command not found`

**Cause:** Recent versions of `huggingface-hub` (>= 0.25) renamed the CLI from `huggingface-cli` to `hf`.

**Solution:** `start.sh` auto-detects `hf` or `huggingface-cli` and uses whichever is available.

### 4. Port 6006 (not 8188)
**Symptom:** ComfyUI starts but is not accessible from outside.

**Cause:** GPUhub exposes port **6006** for web services. Port 8188 (ComfyUI default) is not routed.

**Solution:** `start.sh` uses port **6006 by default**. Override with `COMFYUI_PORT=8188` if needed.

### 5. Docker-in-Docker is impossible
**Symptom:** `Failed to create bridge docker0: operation not permitted`

**Cause:** GPUhub pods already run inside Docker containers. Running a Docker daemon inside requires network permissions the pod doesn't have.

**Solution:** Do NOT try to install/use Docker on GPUhub. Use the native install (`setup-gpuhub.sh`) then "Save Image" in the GPUhub console.

### 6. `/app` may exist
**Symptom:** Models download to `/app/models/` instead of the correct directory.

**Cause:** Some GPUhub configs create an `/app` folder. If `start.sh` auto-detects `/app/models`, it uses the wrong path.

**Solution:** `start.sh` now uses `$SCRIPT_DIR/models` (relative to script) and no longer auto-detects `/app`.

### 7. HuggingFace works, GitHub doesn't
**Symptom:** Models download fine (~15 MB/s from HuggingFace) but GitHub repos fail.

**Note:** PyPI also works. Only GitHub is problematic.

---

## Installation Methods

### Option A: Direct install (if GitHub is accessible)
```bash
export PATH="/root/miniconda3/bin:$PATH"
curl -sL https://raw.githubusercontent.com/wuraaang/comfyui-skyreels-tts/master/setup-gpuhub.sh | bash
cd /opt/ComfyUI && bash start.sh
```

### Option B: SCP fallback (when GitHub is blocked)

**On your local machine** (where GitHub works):
```bash
# 1. Download all repos as zip
cd /tmp && mkdir -p gpuhub-pack && cd gpuhub-pack

# ComfyUI
curl -sL https://codeload.github.com/comfyanonymous/ComfyUI/zip/refs/heads/master -o ComfyUI.zip

# Custom nodes
for repo in kijai/ComfyUI-WanVideoWrapper kijai/ComfyUI-MelBandRoFormer Kosinkadink/ComfyUI-VideoHelperSuite kijai/ComfyUI-KJNodes filliptm/ComfyUI_Fill-ChatterBox; do
  name=$(basename $repo)
  curl -sL "https://codeload.github.com/$repo/zip/refs/heads/main" -o "$name.zip" 2>/dev/null || \
  curl -sL "https://codeload.github.com/$repo/zip/refs/heads/master" -o "$name.zip"
done

# Repo files
curl -sL https://raw.githubusercontent.com/wuraaang/comfyui-skyreels-tts/master/chatterbox_long_node.py -o chatterbox_long_node.py
curl -sL https://raw.githubusercontent.com/wuraaang/comfyui-skyreels-tts/master/start.sh -o start.sh
for wf in chatterbox-long-tts.json chatterbox-voice-clone.json skyreels-v3-talking-avatar.json; do
  curl -sL "https://raw.githubusercontent.com/wuraaang/comfyui-skyreels-tts/master/workflows/$wf" -o "$wf"
done

# 2. Package as tarball
tar czf /tmp/gpuhub-pack.tar.gz -C /tmp/gpuhub-pack .

# 3. Upload to the pod (replace PORT and PASSWORD)
sshpass -p 'PASSWORD' scp -P PORT /tmp/gpuhub-pack.tar.gz root@connect.singapore-b.gpuhub.com:/root/autodl-tmp/
```

**On the GPUhub pod** (via SSH):
```bash
export PATH="/root/miniconda3/bin:$PATH"

# 4. Extract to SYSTEM DISK (/opt, not /root/autodl-tmp)
cd /root/autodl-tmp
tar xzf gpuhub-pack.tar.gz
unzip -q ComfyUI.zip && mv ComfyUI-master /opt/ComfyUI

# 5. Symlink models to persistent storage
mkdir -p /root/autodl-fs/models/{diffusion_models/SkyReelsV3,text_encoders,vae,clip_vision}
ln -sfn /root/autodl-fs/models /opt/ComfyUI/models

# 6. Custom nodes
cd /opt/ComfyUI/custom_nodes
for z in /root/autodl-tmp/ComfyUI-*.zip /root/autodl-tmp/ComfyUI_*.zip; do
  unzip -q "$z"
  name=$(basename "${z%.zip}")
  mv "${name}-main" "$name" 2>/dev/null || mv "${name}-master" "$name" 2>/dev/null || true
done

# 7. Install dependencies
cd /opt/ComfyUI
pip install -r requirements.txt --timeout 300
for node in custom_nodes/*/; do
  [ -f "$node/requirements.txt" ] && pip install -r "$node/requirements.txt" --timeout 300
done
pip install sageattention huggingface-hub hf_xet --timeout 300

# 8. Patch ChatterBox
cp /root/autodl-tmp/chatterbox_long_node.py custom_nodes/ComfyUI_Fill-ChatterBox/
INIT=custom_nodes/ComfyUI_Fill-ChatterBox/__init__.py
sed -i '/^NODE_CLASS_MAPPINGS = {}/i from .chatterbox_long_node import NODE_CLASS_MAPPINGS as LONG_CLASS_MAPPINGS, NODE_DISPLAY_NAME_MAPPINGS as LONG_DISPLAY_NAME_MAPPINGS' "$INIT"
sed -i '/NODE_DISPLAY_NAME_MAPPINGS.update(DIALOG_DISPLAY_NAME_MAPPINGS)/a NODE_CLASS_MAPPINGS.update(LONG_CLASS_MAPPINGS)\nNODE_DISPLAY_NAME_MAPPINGS.update(LONG_DISPLAY_NAME_MAPPINGS)' "$INIT"

# 9. Workflows + start script
mkdir -p user/default/workflows
cp /root/autodl-tmp/*.json user/default/workflows/
cp /root/autodl-tmp/start.sh . && chmod +x start.sh

# 10. Launch
bash start.sh
```

### Option C: Claude Code (automated)
If using Claude Code for deployment:
1. Read this GPUHUB.md file in full before starting
2. Always use Option B (SCP) — do not attempt git clone
3. SSH commands MUST always start with `export PATH="/root/miniconda3/bin:$PATH"`
4. Default port is 6006
5. HuggingFace works fine from GPUhub — models download at ~15 MB/s
6. NEVER attempt Docker on GPUhub

---

## After Installation

### Testing
Access ComfyUI via browser on port 6006 (or SSH tunnel: `ssh -L 6006:localhost:6006`).

### Save Image
Once everything works, save as a custom image in the GPUhub console:
1. Stop the instance
2. Click "More > Save Image"
3. Wait ~1-2h (disk compression)
4. Future instances use this image — only `start.sh` needed (model downloads)

**Important**: Only the system disk (`/`) is captured in the image. Models on `autodl-fs` are persistent (survive shutdown/release) but not part of the image. The `start.sh` script downloads them on first launch, then they stay cached on your account forever.

### File Structure
```
/opt/ComfyUI/                          ← system disk (captured in image)
├── main.py
├── start.sh
├── models → /root/autodl-fs/models/   ← symlink to persistent storage
├── custom_nodes/
│   ├── ComfyUI-WanVideoWrapper/
│   ├── ComfyUI-MelBandRoFormer/
│   ├── ComfyUI-VideoHelperSuite/
│   ├── ComfyUI-KJNodes/
│   └── ComfyUI_Fill-ChatterBox/       # + chatterbox_long_node.py patched
└── user/default/workflows/
    ├── chatterbox-voice-clone.json
    ├── chatterbox-long-tts.json
    └── skyreels-v3-talking-avatar.json

/root/autodl-fs/models/                ← persistent storage (survives shutdown/release)
├── diffusion_models/SkyReelsV3/       # SkyReels A2V (18GB)
├── diffusion_models/                  # MelBandRoFormer (436MB)
├── text_encoders/                     # umt5-xxl (11GB)
├── vae/                               # Wan2_1_VAE (243MB)
└── clip_vision/                       # clip_vision_h (1.2GB)
```
