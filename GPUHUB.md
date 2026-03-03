# Déploiement sur GPUhub

## Problèmes connus

### 1. GitHub est bloqué/throttled
**Symptôme :** `git clone` et `wget` vers github.com échouent (timeout, `fetch-pack: invalid index-pack output`, `curl 92 HTTP/2 stream was not closed cleanly`).

**Cause :** Le réseau GPUhub (Singapour) throttle ou bloque les connexions vers GitHub. C'est un problème du provider, pas du script.

**Impact :** Le script `setup-gpuhub.sh` doit télécharger 6 repos GitHub (ComfyUI + 5 custom nodes). Si GitHub est bloqué, ces downloads échouent.

**Solution :** Utiliser le **fallback SCP** (voir ci-dessous). Télécharger les repos depuis ta machine locale (où GitHub marche) et les uploader via `scp`.

### 2. PATH cassé en mode non-interactif
**Symptôme :** `python3: command not found`, `pip: command not found`, `hf: command not found`

**Cause :** Sur GPUhub, Python est installé dans `/root/miniconda3/bin/` mais ce chemin n'est PAS dans le `$PATH` quand tu exécutes des commandes via SSH non-interactif (`ssh host "command"`). Il est seulement chargé en mode interactif (via `.bashrc`).

**Solution :** Toujours ajouter en début de script ou commande :
```bash
export PATH="/root/miniconda3/bin:$PATH"
```
Les scripts `setup-gpuhub.sh` et `start.sh` le font automatiquement.

### 3. `huggingface-cli` renommé en `hf`
**Symptôme :** `huggingface-cli: command not found`

**Cause :** La version récente de `huggingface-hub` (>= 0.25) a renommé le CLI de `huggingface-cli` à `hf`.

**Solution :** Le `start.sh` auto-détecte `hf` ou `huggingface-cli` et utilise celui qui est disponible.

### 4. Port 6006 (pas 8188)
**Symptôme :** ComfyUI démarre mais n'est pas accessible depuis l'extérieur.

**Cause :** GPUhub expose le port **6006** pour les services web. Le port 8188 (défaut ComfyUI) n'est pas routé.

**Solution :** Le `start.sh` utilise le port **6006 par défaut**. Overridable avec `COMFYUI_PORT=8188` si besoin (Docker, RunPod, etc.).

### 5. Docker-in-Docker impossible
**Symptôme :** `Failed to create bridge docker0: operation not permitted`

**Cause :** Les pods GPUhub tournent déjà dans des containers Docker. Lancer un daemon Docker à l'intérieur nécessite des permissions réseau que le pod n'a pas.

**Solution :** Ne PAS essayer d'installer/utiliser Docker sur GPUhub. Utiliser l'install native (`setup-gpuhub.sh`) puis "Save Image" dans l'interface GPUhub.

### 6. `/app` peut exister
**Symptôme :** Les modèles se téléchargent dans `/app/models/` au lieu du bon répertoire.

**Cause :** Certaines config GPUhub créent un dossier `/app`. Si le `start.sh` auto-détecte `/app/models`, il utilise le mauvais chemin.

**Solution :** Le `start.sh` utilise maintenant `$SCRIPT_DIR/models` (relatif au script) et ne fait plus d'auto-detect `/app`.

### 7. HuggingFace fonctionne, GitHub non
**Symptôme :** Les modèles se téléchargent (~60 MB/s depuis HuggingFace) mais les repos GitHub échouent.

**Info utile :** PyPI fonctionne aussi. Seul GitHub est problématique.

---

## Méthode d'installation

### Option A : GitHub accessible (rare sur GPUhub)
```bash
export PATH="/root/miniconda3/bin:$PATH"
curl -sL https://raw.githubusercontent.com/wuraaang/comfyui-skyreels-tts/master/setup-gpuhub.sh | bash
cd /opt/ComfyUI && bash start.sh
```

### Option B : Fallback SCP (quand GitHub est bloqué)

**Sur ta machine locale** (où GitHub marche) :
```bash
# 1. Télécharger tous les repos en zip
cd /tmp && mkdir -p gpuhub-pack && cd gpuhub-pack

# ComfyUI
curl -sL https://codeload.github.com/comfyanonymous/ComfyUI/zip/refs/heads/master -o ComfyUI.zip

# Custom nodes
for repo in kijai/ComfyUI-WanVideoWrapper kijai/ComfyUI-MelBandRoFormer Kosinkadink/ComfyUI-VideoHelperSuite kijai/ComfyUI-KJNodes filliptm/ComfyUI_Fill-ChatterBox; do
  name=$(basename $repo)
  curl -sL "https://codeload.github.com/$repo/zip/refs/heads/main" -o "$name.zip" 2>/dev/null || \
  curl -sL "https://codeload.github.com/$repo/zip/refs/heads/master" -o "$name.zip"
done

# Fichiers du repo
curl -sL https://raw.githubusercontent.com/wuraaang/comfyui-skyreels-tts/master/chatterbox_long_node.py -o chatterbox_long_node.py
curl -sL https://raw.githubusercontent.com/wuraaang/comfyui-skyreels-tts/master/start.sh -o start.sh
for wf in chatterbox-long-tts.json chatterbox-voice-clone.json skyreels-v3-talking-avatar.json; do
  curl -sL "https://raw.githubusercontent.com/wuraaang/comfyui-skyreels-tts/master/workflows/$wf" -o "$wf"
done

# 2. Packager en tarball
tar czf /tmp/gpuhub-pack.tar.gz -C /tmp/gpuhub-pack .

# 3. Uploader sur le pod (remplacer PORT et PASSWORD)
sshpass -p 'PASSWORD' scp -P PORT /tmp/gpuhub-pack.tar.gz root@connect.singapore-b.gpuhub.com:/root/autodl-tmp/
```

**Sur le pod GPUhub** (via SSH) :
```bash
export PATH="/root/miniconda3/bin:$PATH"

# 4. Décompresser sur le DISQUE SYSTÈME (/opt, pas /root/autodl-tmp)
cd /root/autodl-tmp
tar xzf gpuhub-pack.tar.gz
unzip -q ComfyUI.zip && mv ComfyUI-master /opt/ComfyUI

# 5. Symlink models vers data disk
mkdir -p /root/autodl-fs/models/{diffusion_models/SkyReelsV3,text_encoders,vae,clip_vision}
ln -sfn /root/autodl-fs/models /opt/ComfyUI/models

# 6. Custom nodes
cd /opt/ComfyUI/custom_nodes
for z in /root/autodl-tmp/ComfyUI-*.zip /root/autodl-tmp/ComfyUI_*.zip; do
  unzip -q "$z"
  name=$(basename "${z%.zip}")
  mv "${name}-main" "$name" 2>/dev/null || mv "${name}-master" "$name" 2>/dev/null || true
done

# 7. Install deps
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

# 10. Lancer
bash start.sh
```

### Option C : Claude Code (automatisé)
Si tu utilises Claude Code pour déployer :
1. Lire ce fichier GPUHUB.md en entier avant de commencer
2. Utiliser l'Option B (SCP) systématiquement — ne pas tenter git clone
3. Les commandes SSH doivent TOUJOURS commencer par `export PATH="/root/miniconda3/bin:$PATH"`
4. Le port par défaut est 6006
5. HuggingFace fonctionne parfaitement depuis GPUhub — les modèles se téléchargent vite
6. Ne JAMAIS tenter Docker sur GPUhub

---

## Après installation

### Tester
Accéder à ComfyUI via le navigateur sur le port 6006 (ou tunnel SSH `ssh -L 6006:localhost:6006`).

### Save Image
Once everything works, save as custom image in the GPUhub console:
1. Stop the instance
2. Click "More > Save Image"
3. Wait ~1-2h (disk compression)
4. Future instances use this image → only `start.sh` needed (model downloads)

**Important**: Only the system disk (`/`) is captured. Models on `autodl-fs` are persistent (survive shutdown/release) but not part of the image. The `start.sh` script downloads them on first launch, then they stay cached on your account forever.

### Structure des fichiers
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
│   └── ComfyUI_Fill-ChatterBox/  # + chatterbox_long_node.py patché
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
