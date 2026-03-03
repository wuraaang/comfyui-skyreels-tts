# ComfyUI — SkyReels V3 + Chatterbox TTS (GPUhub Image)

Pre-configured GPUhub image with **3 ready-to-use workflows** for AI voice cloning and talking avatar video generation.

## What's Included

- **Chatterbox Voice Clone** — reference audio + text → cloned voice (~4-6 GB VRAM)
- **Chatterbox Long TTS** — long text + reference audio → cloned voice with auto-chunking (~4-6 GB VRAM)
- **SkyReels V3 Talking Avatar** — image + audio → talking avatar video (~20-24 GB VRAM)
- 5 custom nodes pre-installed
- Smart Start: ComfyUI UI accessible in under 3 minutes

## Quick Start

1. Create a GPUhub instance using this image (RTX 4090+ recommended, RTX 5090 ideal)
2. Run: `bash /opt/ComfyUI/start.sh`
3. Open ComfyUI at `https://<your-gpuhub-url>:8443` (port 6006)
4. Load a workflow from the workflow browser and start generating

## Startup Timing

This image uses **Smart Start** — ComfyUI launches immediately while large models download in the background.

### First launch (no models cached)

| Step | Time | What happens |
|------|------|-------------|
| Phase 1: small models (1.9 GB) | ~2 min | VAE, CLIP Vision, MelBandRoFormer download |
| ComfyUI starts | ~30s | UI is accessible, you can explore workflows |
| TTS ready | ~5 min | Chatterbox models (~2 GB) auto-download on first TTS use |
| Phase 2: large models (29 GB) | ~30 min | umt5-xxl (11 GB) + SkyReels A2V (18 GB) download in background |
| **Video generation ready** | **~35 min** | All models downloaded, SkyReels workflow functional |

### Why does it take 30 min?

The 5 AI models total **31 GB**. GPUhub Singapore instances have a network speed of **~15 MB/s** — this is a hardware limitation of the provider, not a software issue. We tested every optimization (hf_xet, aria2c multi-connection, Cloudflare CDN, HuggingFace mirrors) and all hit the same ~15 MB/s cap.

**Smart Start** solves this by letting you use ComfyUI (TTS workflows) while the heavy video models download in the background. You're not staring at a blank screen for 30 minutes.

### Second launch (models cached on autodl-fs)

| Step | Time |
|------|------|
| ComfyUI starts | ~30s |
| **Everything ready** | **~30s** |

Models are saved to **autodl-fs** (persistent storage that survives shutdown and release). Once downloaded, they're cached forever on your account.

## Workflows

### 1. Chatterbox Voice Clone

Clone any voice from a short reference audio clip.

| Parameter | Description |
|-----------|-------------|
| `reference.wav` | Reference audio (5-15s, clean voice) |
| `text` | Text to speak in the cloned voice |
| `exaggeration` | Emotional intensity (0.25 = flat, 0.5 = natural, 1.0+ = expressive) |
| `cfg_weight` | Pace control (low = fast, high = controlled) |
| `temperature` | Randomness (0.5 = stable, 0.8 = natural, 1.5+ = wild) |

**VRAM:** ~4-6 GB

### 2. Chatterbox Long TTS

Same as Voice Clone but for long texts. Text is automatically split into chunks at sentence boundaries (`max_chars_per_chunk = 200`), each chunk is generated separately and concatenated.

**VRAM:** ~4-6 GB

### 3. SkyReels V3 Talking Avatar

Full pipeline: image + audio → talking avatar video. Uses MelBandRoFormer for voice isolation, wav2vec2 for audio embeddings, then SkyReels V3 A2V for video generation.

**VRAM:** ~20-24 GB (fp8)

> **Note:** TTS and video workflows cannot run simultaneously on a 24 GB GPU. Run one at a time, or use an RTX 5090 (32 GB).

## Models (31 GB total)

All models are downloaded automatically by `start.sh` from HuggingFace.

| Model | Size | Source | Used by |
|-------|------|--------|---------|
| SkyReels V3 A2V (fp8) | 18 GB | Kijai/WanVideo_comfy_fp8_scaled | Video generation |
| umt5-xxl text encoder | 11 GB | Kijai/WanVideo_comfy | Video generation |
| CLIP Vision H | 1.2 GB | Comfy-Org/Wan_2.1_ComfyUI_repackaged | Video generation |
| MelBandRoFormer (fp16) | 436 MB | Kijai/MelBandRoFormer_comfy | Audio separation |
| Wan2.1 VAE (bf16) | 243 MB | Kijai/WanVideo_comfy | Video generation |
| Chatterbox TTS | ~2 GB | Auto-downloaded on first use | TTS voice clone |

## How It Works

### Storage architecture (GPUhub)

```
/opt/ComfyUI/                    ← system disk (30 GB, saved in image)
├── main.py, start.sh
├── custom_nodes/                 ← 5 nodes pre-installed
├── models → /root/autodl-fs/models/   ← symlink to persistent storage
└── user/default/workflows/       ← 3 workflows ready to use

/root/autodl-fs/models/          ← persistent storage (survives shutdown/release)
├── diffusion_models/SkyReelsV3/  ← SkyReels A2V (18 GB)
├── diffusion_models/             ← MelBandRoFormer (436 MB)
├── text_encoders/                ← umt5-xxl (11 GB)
├── vae/                          ← Wan2.1 VAE (243 MB)
└── clip_vision/                  ← CLIP Vision H (1.2 GB)
```

### Smart Start (Phase 1 / Phase 2)

1. **Phase 1** (blocking, ~2 min): Downloads 3 small models (1.9 GB total)
2. **ComfyUI launches** — UI is accessible
3. **Phase 2** (background): Downloads 2 large models (29 GB) while you use ComfyUI
4. Progress: `tail -f /tmp/model-download.log`

## Tech Specs

| Component | Version |
|-----------|---------|
| CUDA | 12.8 |
| PyTorch | 2.8.0+cu128 |
| Python | 3.12 |
| ComfyUI | latest |
| GPU minimum | RTX 4090 (24 GB) |
| GPU recommended | RTX 5090 (32 GB) |

### Custom Nodes

- [ComfyUI-WanVideoWrapper](https://github.com/kijai/ComfyUI-WanVideoWrapper)
- [ComfyUI-MelBandRoFormer](https://github.com/kijai/ComfyUI-MelBandRoFormer)
- [ComfyUI-VideoHelperSuite](https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite)
- [ComfyUI-KJNodes](https://github.com/kijai/ComfyUI-KJNodes)
- [ComfyUI_Fill-ChatterBox](https://github.com/filliptm/ComfyUI_Fill-ChatterBox) + custom `FL_ChatterboxLongTTS` node

## Troubleshooting

**"CUDA out of memory"** — TTS and video workflows can't run simultaneously on 24 GB GPUs. Close one before launching the other, or restart ComfyUI between runs.

**Models re-downloading every launch** — Models should persist on `autodl-fs`. If they keep re-downloading, check that `/root/autodl-fs` exists and is writable: `ls -la /root/autodl-fs/models/`

**Red nodes in ComfyUI** — A custom node failed to load. Check startup logs: `tail -n 50 /tmp/comfyui-start.log`

**Video workflow not working** — Phase 2 models may still be downloading. Check progress: `tail -f /tmp/model-download.log`

**Port not accessible** — GPUhub exposes port 6006, not 8188. The start script uses 6006 by default.

## Building the Image from Scratch

If you want to rebuild this image on a fresh GPUhub instance, see [GPUHUB.md](GPUHUB.md) for the full setup guide including known issues and workarounds.

```bash
# Quick version (if GitHub is accessible):
export PATH="/root/miniconda3/bin:$PATH"
curl -sL https://raw.githubusercontent.com/wuraaang/comfyui-skyreels-tts/master/setup-gpuhub.sh | bash
bash /opt/ComfyUI/start.sh
# Then: More > Save Image in GPUhub console
```
