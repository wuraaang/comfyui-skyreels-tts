# ComfyUI — SkyReels V3 A2V + Qwen3-TTS

Image Docker prête à l'emploi avec **2 workflows** :
1. **Qwen3-TTS Voice Clone** — texte + audio référence → voix clonée
2. **SkyReels V3 A2V** — image + audio → vidéo avatar parlant

## Quick Start

### Local (Docker + GPU NVIDIA)

```bash
docker run --gpus all -p 8188:8188 \
  -v ./models:/app/models \
  elcrackito/comfyui-skyreels-tts:latest
```

Accès : **http://localhost:8188**

Le flag `-v ./models:/app/models` persiste les modèles (~35GB) sur le disque local. Au prochain lancement, pas de re-téléchargement.

### GPUhub

1. Créer une instance avec **RTX 5090** (ou RTX 4090 minimum)
2. Image Docker : `elcrackito/comfyui-skyreels-tts:latest`
3. Variable d'environnement : `COMFYUI_PORT=6006`
4. Port exposé : `6006`
5. Lancer et attendre ~3 min au premier démarrage

> GPUhub utilise le port 6006 par défaut. La variable `COMFYUI_PORT` configure le port de ComfyUI.

### RunPod

1. **Create Pod** → Community Cloud ou Secure Cloud
2. GPU : **A40 48GB** ou **RTX 4090 24GB** minimum
3. Container Image : `elcrackito/comfyui-skyreels-tts:latest`
4. Expose HTTP Ports : `8188`
5. (Recommandé) Attacher un **Network Volume** monté sur `/app/models` pour persister les modèles
6. Deploy → attendre ~3 min au premier démarrage

## Workflows inclus

### 1. Qwen3-TTS Voice Clone

**Nodes :** `Qwen3Loader` → `LoadAudio` → `Qwen3VoiceClone` → `SaveAudio`

| Input | Description |
|-------|-------------|
| `reference.wav` | Audio de référence (la voix à cloner, 5-30s) |
| `ref_text` | Transcription exacte de l'audio de référence |
| `text` | Le texte à faire dire avec la voix clonée |

**VRAM :** ~8-10 GB

### 2. SkyReels V3 A2V (Audio-to-Video)

**VRAM :** ~20-24 GB (fp8)

> ⚠️ Workflow JSON en attente — sera ajouté prochainement.

## Specs techniques

| Composant | Version |
|-----------|---------|
| CUDA | 12.8 |
| PyTorch | 2.7.0+cu128 |
| Python | 3.12 |
| ComfyUI | latest |
| GPU min | RTX 4090 (24GB) |
| GPU recommandé | RTX 5090 (32GB) |

### Modèles téléchargés au démarrage (~35 GB)

| Modèle | Taille |
|--------|--------|
| SkyReels A2V fp8 | 18 GB |
| umt5-xxl-enc-bf16 | 11 GB |
| clip_vision_h | 1.2 GB |
| MelBandRoformer_fp16 | 436 MB |
| Wan2_1_VAE_bf16 | 243 MB |
| Qwen3-TTS-1.7B-Base | ~3.5 GB |
| Qwen3-TTS-Tokenizer | ~500 MB |

### Custom nodes installés

- [ComfyUI-WanVideoWrapper](https://github.com/kijai/ComfyUI-WanVideoWrapper)
- [ComfyUI-MelBandRoFormer](https://github.com/kijai/ComfyUI-MelBandRoFormer)
- [ComfyUI-VideoHelperSuite](https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite)
- [ComfyUI-KJNodes](https://github.com/kijai/ComfyUI-KJNodes)
- [ComfyUI-Qwen3-TTS](https://github.com/DarioFT/ComfyUI-Qwen3-TTS)

## Temps de démarrage

| Étape | Temps |
|-------|-------|
| Pull image (~5 GB) | ~30s |
| Download modèles (~35 GB) | ~2-3 min |
| Startup ComfyUI | ~15s |
| **Premier lancement** | **~3-4 min** |
| **Relancement (modèles cachés)** | **~30s** |

## Troubleshooting

**"CUDA out of memory"** → Les 2 workflows ne peuvent pas tourner en même temps. Ferme l'un avant de lancer l'autre, ou redémarre ComfyUI entre les deux.

**Modèles re-téléchargés à chaque fois** → Monte un volume persistant sur `/app/models` (voir instructions ci-dessus).

**Node rouge dans ComfyUI** → Un custom node n'a pas été chargé. Vérifier les logs au démarrage.
