import re
import os
import torch
import tempfile
from comfy.utils import ProgressBar
from .chatterbox_node import (
    AudioNodeBase,
    load_tts_model,
    get_cached_model,
    cache_model,
    clear_cached_model,
    save_audio_wav,
)


def split_text_into_chunks(text, max_chars=200):
    """Split text into chunks at sentence boundaries, respecting max length."""
    # Split on sentence endings
    sentences = re.split(r'(?<=[.!?])\s+', text.strip())

    chunks = []
    current_chunk = ""

    for sentence in sentences:
        if not sentence.strip():
            continue
        # If adding this sentence exceeds max, save current and start new
        if current_chunk and len(current_chunk) + len(sentence) + 1 > max_chars:
            chunks.append(current_chunk.strip())
            current_chunk = sentence
        else:
            current_chunk = (current_chunk + " " + sentence).strip() if current_chunk else sentence

    if current_chunk.strip():
        chunks.append(current_chunk.strip())

    # If no chunks were created (no sentence endings), split by max_chars
    if not chunks:
        for i in range(0, len(text), max_chars):
            chunk = text[i:i + max_chars].strip()
            if chunk:
                chunks.append(chunk)

    return chunks


class FL_ChatterboxLongTTSNode(AudioNodeBase):
    """
    Generates long-form speech by splitting text into chunks,
    generating each chunk separately, and concatenating the results.
    """

    @classmethod
    def INPUT_TYPES(cls):
        return {
            "required": {
                "text": ("STRING", {"multiline": True, "default": "Enter your long text here. It will be automatically split into sentences. Each sentence is generated separately and then concatenated into one audio file."}),
                "exaggeration": ("FLOAT", {"default": 0.5, "min": 0.25, "max": 2.0, "step": 0.05,
                    "tooltip": "Emotion intensity. 0.25 = monotone, 0.5 = natural, 1.0+ = very expressive."}),
                "cfg_weight": ("FLOAT", {"default": 0.5, "min": 0.2, "max": 1.0, "step": 0.05,
                    "tooltip": "Pace control. Lower = faster. Higher = slower/more controlled."}),
                "temperature": ("FLOAT", {"default": 0.8, "min": 0.05, "max": 5.0, "step": 0.05,
                    "tooltip": "Randomness. 0.5 = stable, 0.8 = natural, 1.5+ = unpredictable."}),
                "seed": ("INT", {"default": 42, "min": 0, "max": 4294967295}),
            },
            "optional": {
                "audio_prompt": ("AUDIO",),
                "max_chars_per_chunk": ("INT", {"default": 200, "min": 50, "max": 500, "step": 10,
                    "tooltip": "Max characters per chunk. Splits at sentence boundaries. Lower = more stable generation."}),
                "keep_model_loaded": ("BOOLEAN", {"default": False}),
            }
        }

    RETURN_TYPES = ("AUDIO", "STRING")
    RETURN_NAMES = ("audio", "message")
    FUNCTION = "generate_long_speech"
    CATEGORY = "ChatterBox"

    def generate_long_speech(self, text, exaggeration, cfg_weight, temperature, seed, max_chars_per_chunk=200, audio_prompt=None, keep_model_loaded=False):
        import numpy as np
        import random

        # Split text into chunks
        chunks = split_text_into_chunks(text, max_chars_per_chunk)
        total_chunks = len(chunks)

        if total_chunks == 0:
            return ({"waveform": torch.zeros((1, 2, 1)), "sample_rate": 16000}, "Error: No text provided.")

        message = f"Split text into {total_chunks} chunks:\n"
        for i, chunk in enumerate(chunks):
            message += f"  [{i+1}] {chunk[:60]}{'...' if len(chunk) > 60 else ''}\n"

        # Determine device
        device = "cuda" if torch.cuda.is_available() else "cpu"

        # Prepare audio prompt
        temp_files = []
        audio_prompt_path = None
        if audio_prompt is not None:
            try:
                with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as temp_prompt:
                    audio_prompt_path = temp_prompt.name
                    temp_files.append(audio_prompt_path)
                prompt_waveform = audio_prompt['waveform'].squeeze(0)
                save_audio_wav(audio_prompt_path, prompt_waveform, audio_prompt['sample_rate'])
            except Exception as e:
                message += f"\nError creating audio prompt: {e}"
                audio_prompt_path = None

        pbar = ProgressBar(total_chunks)
        all_wavs = []
        sample_rate = 16000
        tts_model = None

        try:
            # Load model once
            tts_model = get_cached_model("tts", device)
            if tts_model is None:
                message += f"\nLoading TTS model on {device}..."
                tts_model = load_tts_model(device=device)
                cache_model("tts", device, tts_model)

            sample_rate = tts_model.sr

            # Generate each chunk
            for i, chunk in enumerate(chunks):
                # Set seed per chunk (base_seed + chunk_index for variety but reproducibility)
                chunk_seed = seed + i
                torch.manual_seed(chunk_seed)
                if torch.cuda.is_available():
                    torch.cuda.manual_seed(chunk_seed)
                np.random.seed(chunk_seed)
                random.seed(chunk_seed)

                message += f"\nGenerating chunk {i+1}/{total_chunks}..."

                wav = tts_model.generate(
                    text=chunk,
                    audio_prompt_path=audio_prompt_path,
                    exaggeration=exaggeration,
                    cfg_weight=cfg_weight,
                    temperature=temperature,
                )
                all_wavs.append(wav)
                pbar.update_absolute(i + 1)
                message += f" OK ({wav.shape[-1]/sample_rate:.1f}s)"

            # Concatenate all generated audio
            concatenated = torch.cat(all_wavs, dim=-1)
            total_duration = concatenated.shape[-1] / sample_rate
            message += f"\n\nTotal audio: {total_duration:.1f}s ({total_chunks} chunks concatenated)"

            audio_data = {
                "waveform": concatenated.unsqueeze(0),
                "sample_rate": sample_rate
            }

            return (audio_data, message)

        except Exception as e:
            message += f"\nError during generation: {e}"
            # Return whatever we have so far
            if all_wavs:
                concatenated = torch.cat(all_wavs, dim=-1)
                audio_data = {
                    "waveform": concatenated.unsqueeze(0),
                    "sample_rate": sample_rate
                }
                message += f"\nReturning partial audio ({len(all_wavs)}/{total_chunks} chunks)"
                return (audio_data, message)
            return ({"waveform": torch.zeros((1, 2, 1)), "sample_rate": 16000}, message)
        finally:
            for temp_file in temp_files:
                if os.path.exists(temp_file):
                    os.unlink(temp_file)
            if not keep_model_loaded:
                clear_cached_model("tts")


NODE_CLASS_MAPPINGS = {
    "FL_ChatterboxLongTTS": FL_ChatterboxLongTTSNode,
}

NODE_DISPLAY_NAME_MAPPINGS = {
    "FL_ChatterboxLongTTS": "FL Chatterbox Long TTS",
}
