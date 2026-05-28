"""
nitrogen_mac/serve_mac.py — macOS-compatible NitroGen inference server
Patches the model loading to use MPS (Apple Silicon) instead of CUDA.

Usage:
    python -m nitrogen_mac.serve_mac path/to/ng.pt --port 5555

This is a drop-in replacement for NitroGen's scripts/serve.py that:
1. Loads the model on MPS (or CPU fallback) instead of CUDA
2. Keeps the same ZMQ REQ/REP protocol
3. Handles the same pickle-serialized message format
"""

import sys
import json
import time
import pickle
import argparse
from pathlib import Path
from collections import deque

import torch
import numpy as np
import zmq

# Patch torch device selection for Apple Silicon
DEVICE = "mps" if torch.backends.mps.is_available() else "cpu"
print(f"[serve_mac] Using device: {DEVICE}")

# Add NitroGen repo to path
NITROGEN_REPO = None
for p in [Path.cwd(), Path(__file__).resolve().parents[2]]:
    if (p / "nitrogen").is_dir():
        NITROGEN_REPO = p
        sys.path.insert(0, str(p))
        break

if NITROGEN_REPO is None:
    print("[serve_mac] Warning: NitroGen repo not found in parent directories")
    print("[serve_mac] Make sure to run from inside the NitroGen repo or set PYTHONPATH")

from nitrogen.flow_matching_transformer.nitrogen import NitroGen, NitroGen_Config
from nitrogen.mm_tokenizers import NitrogenTokenizerConfig, NitrogenTokenizer
from nitrogen.cfg import CkptConfig
from nitrogen.shared import PATH_REPO

try:
    from transformers import AutoImageProcessor
except ImportError:
    AutoImageProcessor = None
    print("[serve_mac] Warning: transformers not installed, image preprocessing may fail")

from PIL import Image


def load_model_mps(checkpoint_path: str, device: str = DEVICE):
    """
    Load NitroGen model on MPS/CPU instead of CUDA.
    Equivalent to nitrogen.inference_session.load_model but Mac-compatible.
    """
    print(f"[serve_mac] Loading checkpoint: {checkpoint_path}")
    checkpoint = torch.load(checkpoint_path, map_location="cpu", weights_only=False)
    ckpt_config = CkptConfig.model_validate(checkpoint["ckpt_config"])
    model_cfg = ckpt_config.model_cfg
    tokenizer_cfg = ckpt_config.tokenizer_cfg

    print("[serve_mac] Checkpoint config:")
    print(json.dumps(ckpt_config.model_dump(), indent=2, default=str))

    # Image processor
    img_proc = None
    if AutoImageProcessor:
        img_proc = AutoImageProcessor.from_pretrained(model_cfg.vision_encoder_name)

    # Build model
    if not isinstance(model_cfg, NitroGen_Config):
        raise ValueError(f"Unsupported model config: {type(model_cfg)}")

    assert isinstance(tokenizer_cfg, NitrogenTokenizerConfig)
    tokenizer_cfg.training = False

    # Fix hardcoded paths from training
    if tokenizer_cfg.game_mapping_cfg is not None:
        tokenizer_cfg.game_mapping_cfg.src_files = [
            x.replace("/mnt/amlfs-02/shared/gaming/gamingvla", str(PATH_REPO))
            for x in tokenizer_cfg.game_mapping_cfg.src_files
        ]

    tokenizer = NitrogenTokenizer(tokenizer_cfg)
    game_mapping = tokenizer.game_mapping
    model = NitroGen(config=model_cfg, game_mapping=game_mapping)

    # Load weights
    model.load_state_dict(checkpoint["model"])
    model.eval()
    tokenizer.eval()

    # Move to MPS/CPU instead of CUDA
    model = model.to(device)

    # Parameter count
    total_params = sum(p.numel() for p in model.parameters())
    print(f"[serve_mac] Model loaded: {total_params:,} parameters on {device}")

    return model, tokenizer, img_proc, ckpt_config


class InferenceSessionMac:
    """Mac-compatible inference session."""

    def __init__(self, model, tokenizer, img_proc, ckpt_config, cfg_scale=1.0, context_length=1):
        self.model = model
        self.tokenizer = tokenizer
        self.img_proc = img_proc
        self.ckpt_config = ckpt_config
        self.cfg_scale = cfg_scale
        self.context_length = context_length
        self.device = next(model.parameters()).device

        # Action history for multi-frame context
        self.action_history = deque(maxlen=context_length)

        # Checkpoint info
        self.ckpt_path = ""
        self.action_downsample_ratio = 1

    @classmethod
    def from_ckpt(cls, ckpt_path: str, cfg_scale=1.0, context_length=1, **kwargs):
        model, tokenizer, img_proc, ckpt_config = load_model_mps(ckpt_path)
        session = cls(model, tokenizer, img_proc, ckpt_config, cfg_scale, context_length)
        session.ckpt_path = ckpt_path
        return session

    def predict(self, image: np.ndarray) -> dict:
        """Run inference on a single 256x256 RGB frame."""
        # Preprocess image
        if self.img_proc:
            pil_image = Image.fromarray(image)
            inputs = self.img_proc(images=pil_image, return_tensors="pt")
            pixel_values = inputs["pixel_values"].to(self.device)
        else:
            # Manual preprocessing: normalize to [0, 1]
            tensor = torch.from_numpy(image).float() / 255.0
            tensor = tensor.permute(2, 0, 1).unsqueeze(0)
            pixel_values = tensor.to(self.device)

        # Run model
        with torch.no_grad():
            output = self.model.predict(
                pixel_values,
                tokenizer=self.tokenizer,
                cfg_scale=self.cfg_scale,
            )

        return output

    def reset(self):
        """Clear action history."""
        self.action_history.clear()

    def info(self) -> dict:
        return {
            "ckpt_path": self.ckpt_path,
            "action_downsample_ratio": self.action_downsample_ratio,
            "device": str(self.device),
            "cfg_scale": self.cfg_scale,
            "context_length": self.context_length,
        }


def main():
    parser = argparse.ArgumentParser(description="NitroGen macOS inference server")
    parser.add_argument("ckpt", type=str, help="Path to checkpoint file (ng.pt)")
    parser.add_argument("--port", type=int, default=5555, help="ZMQ port")
    parser.add_argument("--cfg", type=float, default=1.0, help="CFG scale")
    parser.add_argument("--ctx", type=int, default=1, help="Context length (frames)")
    args = parser.parse_args()

    # Load model
    session = InferenceSessionMac.from_ckpt(
        args.ckpt, cfg_scale=args.cfg, context_length=args.ctx
    )

    # Start ZMQ server
    context = zmq.Context()
    socket = context.socket(zmq.REP)
    socket.bind(f"tcp://*:{args.port}")

    print(f"[serve_mac] Listening on tcp://*:{args.port}")
    print(f"[serve_mac] Device: {DEVICE}")
    print(f"[serve_mac] Ready for predictions")
    print()

    request_count = 0
    predict_times = deque(maxlen=100)

    try:
        while True:
            # Wait for request
            message = socket.recv()
            request = pickle.loads(message)
            msg_type = request.get("type", "predict")

            if msg_type == "info":
                response = session.info()

            elif msg_type == "reset":
                session.reset()
                response = {"status": "ok"}

            elif msg_type == "predict":
                image = request["image"]
                t0 = time.monotonic()
                result = session.predict(image)
                dt = time.monotonic() - t0
                predict_times.append(dt)
                response = result

                request_count += 1
                if request_count % 60 == 0:
                    avg_ms = 1000 * sum(predict_times) / len(predict_times)
                    avg_fps = 1000 / avg_ms if avg_ms > 0 else 0
                    print(
                        f"[serve_mac] requests={request_count:6d}  "
                        f"avg={avg_ms:.1f}ms  "
                        f"~{avg_fps:.0f}fps"
                    )
            else:
                response = {"error": f"Unknown message type: {msg_type}"}

            socket.send(pickle.dumps(response))

    except KeyboardInterrupt:
        print(f"\n[serve_mac] Shutting down after {request_count} requests")
    finally:
        socket.close()
        context.term()


if __name__ == "__main__":
    main()
