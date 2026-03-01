# ComfyUI — SkyReels V3 A2V + Chatterbox TTS

Image Docker prête à l'emploi avec **3 workflows** :
1. **Chatterbox Voice Clone** — audio référence + texte → voix clonée
2. **Chatterbox Long TTS** — texte long + audio référence → voix clonée (split auto par phrases)
3. **SkyReels V3 Talking Avatar** — image + audio → vidéo avatar parlant

## Quick Start

### Local (Docker + GPU NVIDIA)

```bash
docker run --gpus all -p 8188:8188 \
  -v ./models:/app/models \
  elcrackito/comfyui-skyreels-tts:latest
```

Accès : **http://localhost:8188**

Le flag `-v ./models:/app/models` persiste les modèles (~31GB) sur le disque local. Au prochain lancement, pas de re-téléchargement.

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

### 1. Chatterbox Voice Clone

**Nodes :** `LoadAudio` → `FL_ChatterboxTTS` → `PreviewAudio` / `SaveAudio`

| Input | Description |
|-------|-------------|
| `reference.wav` | Audio de référence (la voix à cloner, 5-15s, propre) |
| `text` | Le texte à faire dire avec la voix clonée |
| `exaggeration` | Intensité émotionnelle (0.25 = monotone, 0.5 = naturel, 1.0+ = expressif) |
| `cfg_weight` | Contrôle du rythme (bas = rapide, haut = contrôlé) |
| `temperature` | Randomness (0.5 = stable, 0.8 = naturel, 1.5+ = imprévisible) |

**VRAM :** ~4-6 GB

### 2. Chatterbox Long TTS

**Nodes :** `LoadAudio` → `FL_ChatterboxLongTTS` → `PreviewAudio` / `SaveAudio`

Même principe que Voice Clone, mais pour les textes longs. Le texte est automatiquement découpé en chunks aux limites de phrases (`max_chars_per_chunk = 200` par défaut), chaque chunk est généré séparément puis concaténé.

**VRAM :** ~4-6 GB

### 3. SkyReels V3 Talking Avatar

Pipeline complète : image + audio → vidéo avatar parlant. Utilise MelBandRoFormer pour isoler les voix, wav2vec2 pour les embeddings audio, puis SkyReels V3 A2V pour générer la vidéo.

**VRAM :** ~20-24 GB (fp8)

## Specs techniques

| Composant | Version |
|-----------|---------|
| CUDA | 12.8 |
| PyTorch | 2.7.0+cu128 |
| Python | 3.12 |
| ComfyUI | latest |
| GPU min | RTX 4090 (24GB) |
| GPU recommandé | RTX 5090 (32GB) |

### Modèles téléchargés au démarrage (~31 GB)

| Modèle | Taille |
|--------|--------|
| SkyReels A2V fp8 | 18 GB |
| umt5-xxl-enc-bf16 | 11 GB |
| clip_vision_h | 1.2 GB |
| MelBandRoformer_fp16 | 436 MB |
| Wan2_1_VAE_bf16 | 243 MB |

> Les modèles Chatterbox (~2 GB) se téléchargent automatiquement au premier usage du node TTS.

### Custom nodes installés

- [ComfyUI-WanVideoWrapper](https://github.com/kijai/ComfyUI-WanVideoWrapper)
- [ComfyUI-MelBandRoFormer](https://github.com/kijai/ComfyUI-MelBandRoFormer)
- [ComfyUI-VideoHelperSuite](https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite)
- [ComfyUI-KJNodes](https://github.com/kijai/ComfyUI-KJNodes)
- [ComfyUI_Fill-ChatterBox](https://github.com/filliptm/ComfyUI_Fill-ChatterBox) + custom `FL_ChatterboxLongTTS` node

## Temps de démarrage

Les 5 modèles sont téléchargés **en parallèle** — le temps est limité par le plus gros fichier (18 GB) au lieu de la somme de tous.

| Étape | Temps |
|-------|-------|
| Pull image (~5 GB) | ~30s |
| Download modèles (~31 GB, parallèle) | ~2-3 min |
| Startup ComfyUI | ~15s |
| **Premier lancement** | **~3-4 min** |
| **Relancement (modèles cachés)** | **~30s** |

## Troubleshooting

**"CUDA out of memory"** → Les workflows vidéo et TTS ne peuvent pas tourner en même temps sur un GPU 24 GB. Ferme l'un avant de lancer l'autre, ou redémarre ComfyUI entre les deux.

**Modèles re-téléchargés à chaque fois** → Monte un volume persistant sur `/app/models` (voir instructions ci-dessus).

**Node rouge dans ComfyUI** → Un custom node n'a pas été chargé. Vérifier les logs au démarrage.
