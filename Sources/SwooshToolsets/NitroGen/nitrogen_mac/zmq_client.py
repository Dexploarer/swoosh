"""
nitrogen_mac/zmq_client.py — Standalone ZMQ client for NitroGen inference server
Used when the NitroGen package isn't installed locally.
Implements the same protocol as nitrogen.inference_client.ModelClient.

Protocol (ZMQ REQ/REP, pickle-serialized):
    Client sends:  {"type": "predict", "image": np.ndarray(256,256,3)}
    Server replies: {"action": OrderedDict, ...}
    
    Client sends:  {"type": "reset"}
    Server replies: {"status": "ok"}
    
    Client sends:  {"type": "info"}
    Server replies: {"ckpt_path": "...", "action_downsample_ratio": 1, ...}
"""

import pickle
import time

import numpy as np
import zmq


class ModelClient:
    """ZMQ client for NitroGen inference server. Platform-agnostic."""

    def __init__(self, host: str = "localhost", port: int = 5555):
        self.host = host
        self.port = port
        self.timeout_ms = 30_000

        self.context = zmq.Context()
        self.socket = self.context.socket(zmq.REQ)
        self.socket.connect(f"tcp://{host}:{port}")
        self.socket.setsockopt(zmq.RCVTIMEO, self.timeout_ms)

        print(f"[zmq_client] Connected to {host}:{port}")

    def predict(self, image: np.ndarray) -> dict:
        """
        Send a 256x256 RGB image, receive predicted gamepad actions.
        
        Args:
            image: np.ndarray of shape (256, 256, 3), dtype uint8, RGB order.
            
        Returns:
            dict with at least {"action": OrderedDict}
        """
        request = {"type": "predict", "image": image}
        self.socket.send(pickle.dumps(request))

        try:
            response = pickle.loads(self.socket.recv())
        except zmq.Again:
            raise TimeoutError(
                f"NitroGen server at {self.host}:{self.port} did not respond "
                f"within {self.timeout_ms}ms"
            )

        return response

    def reset(self):
        """Reset the server's inference session (clear action history)."""
        request = {"type": "reset"}
        self.socket.send(pickle.dumps(request))
        try:
            response = pickle.loads(self.socket.recv())
        except zmq.Again:
            print("[zmq_client] Warning: reset timed out")
            return {}
        return response

    def info(self) -> dict:
        """Get server info (checkpoint path, action params, etc.)."""
        request = {"type": "info"}
        self.socket.send(pickle.dumps(request))
        try:
            response = pickle.loads(self.socket.recv())
        except zmq.Again:
            print("[zmq_client] Warning: info timed out")
            return {"action_downsample_ratio": 1}
        return response

    def close(self):
        """Close the ZMQ connection."""
        self.socket.close()
        self.context.term()

    def __del__(self):
        try:
            self.close()
        except Exception:
            pass
