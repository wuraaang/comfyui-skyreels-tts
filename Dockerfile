FROM nvidia/cuda:12.8.0-devel-ubuntu24.04

ENV DEBIAN_FRONTEND=noninteractive
ENV HF_HUB_ENABLE_HF_TRANSFER=1
ENV PYTHONUNBUFFERED=1

# System deps — Ubuntu 24.04 ships with Python 3.12
RUN apt-get update && apt-get install -y \
    git python3 python3-pip python3-venv ffmpeg wget curl \
    && rm -rf /var/lib/apt/lists/*

# PyTorch 2.7 + CUDA 12.8
RUN pip install --break-system-packages \
    torch torchvision torchaudio \
    --index-url https://download.pytorch.org/whl/cu128

# ComfyUI
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /app
WORKDIR /app
RUN pip install --break-system-packages -r requirements.txt

# Custom nodes — stable (rarely modified)
RUN cd custom_nodes && \
    git clone https://github.com/kijai/ComfyUI-WanVideoWrapper && \
    git clone https://github.com/kijai/ComfyUI-MelBandRoFormer && \
    git clone https://github.com/Kosinkadink/ComfyUI-VideoHelperSuite && \
    git clone https://github.com/kijai/ComfyUI-KJNodes

# Install deps for stable nodes
RUN cd custom_nodes/ComfyUI-WanVideoWrapper && \
    pip install --break-system-packages -r requirements.txt
RUN cd custom_nodes/ComfyUI-MelBandRoFormer && \
    pip install --break-system-packages -r requirements.txt
RUN cd custom_nodes/ComfyUI-VideoHelperSuite && \
    pip install --break-system-packages -r requirements.txt
RUN cd custom_nodes/ComfyUI-KJNodes && \
    pip install --break-system-packages -r requirements.txt

# ChatterBox — separate layer (more likely to change)
RUN cd custom_nodes && \
    git clone https://github.com/filliptm/ComfyUI_Fill-ChatterBox
RUN cd custom_nodes/ComfyUI_Fill-ChatterBox && \
    pip install --break-system-packages -r requirements.txt

# SageAttention — required by SkyReels workflow for faster attention
RUN pip install --break-system-packages sageattention

# Fast model download
RUN pip install --break-system-packages huggingface-hub hf_transfer

# Files that change often — LAST for maximum cache efficiency
COPY chatterbox_long_node.py /app/custom_nodes/ComfyUI_Fill-ChatterBox/chatterbox_long_node.py
RUN cd custom_nodes/ComfyUI_Fill-ChatterBox && \
    sed -i '/^NODE_CLASS_MAPPINGS = {}/i from .chatterbox_long_node import NODE_CLASS_MAPPINGS as LONG_CLASS_MAPPINGS, NODE_DISPLAY_NAME_MAPPINGS as LONG_DISPLAY_NAME_MAPPINGS' __init__.py && \
    sed -i '/NODE_DISPLAY_NAME_MAPPINGS.update(DIALOG_DISPLAY_NAME_MAPPINGS)/a NODE_CLASS_MAPPINGS.update(LONG_CLASS_MAPPINGS)\nNODE_DISPLAY_NAME_MAPPINGS.update(LONG_DISPLAY_NAME_MAPPINGS)' __init__.py

COPY workflows/ /app/user/default/workflows/
COPY start.sh /app/start.sh
RUN chmod +x /app/start.sh

ENV COMFYUI_PORT=6006
EXPOSE 6006 8188
CMD ["/app/start.sh"]
