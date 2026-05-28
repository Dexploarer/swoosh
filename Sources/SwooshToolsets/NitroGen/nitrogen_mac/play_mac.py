#!/usr/bin/env python3
"""
nitrogen_mac/play_mac.py — macOS NitroGen game agent harness
Drop-in replacement for NitroGen's scripts/play.py (Windows-only).

Usage:
    # By window title
    python -m nitrogen_mac.play_mac --window "Celeste" --port 5555

    # By bundle ID  
    python -m nitrogen_mac.play_mac --bundle-id com.exok.celeste --port 5555

    # Capture entire display
    python -m nitrogen_mac.play_mac --display 1 --port 5555

    # With custom key mapping
    python -m nitrogen_mac.play_mac --window "Celeste" --keymap celeste.json

Requires:
    - NitroGen inference server running (python scripts/serve.py ng.pt)
    - macOS 14+ (ScreenCaptureKit)
    - Screen Recording + Accessibility permissions
"""

import os
import sys
import time
import json
import signal
import argparse
from pathlib import Path
from collections import OrderedDict

import cv2
import numpy as np
from PIL import Image

# NitroGen's own inference client (ZMQ-based, platform-agnostic)
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
try:
    from nitrogen.inference_client import ModelClient
    from nitrogen.inference_viz import create_viz, VideoRecorder
    from nitrogen.shared import BUTTON_ACTION_TOKENS
except ImportError:
    # If NitroGen isn't installed, provide a minimal ModelClient
    print("[play_mac] Warning: NitroGen package not found, using built-in ZMQ client")
    from nitrogen_mac.zmq_client import ModelClient
    BUTTON_ACTION_TOKENS = None
    create_viz = None
    VideoRecorder = None

from nitrogen_mac.game_env import MacGameEnv, make_zero_action
from nitrogen_mac.input_inject import load_key_map


BUTTON_PRESS_THRES = 0.5


def parse_args():
    parser = argparse.ArgumentParser(
        description="NitroGen macOS Game Agent",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )

    # Target selection (mutually exclusive)
    target = parser.add_mutually_exclusive_group(required=True)
    target.add_argument("--window", type=str, help="Game window title (partial match)")
    target.add_argument("--bundle-id", type=str, help="macOS bundle identifier")
    target.add_argument("--display", type=int, help="Display ID for full-screen capture")

    # Server
    parser.add_argument("--host", type=str, default="localhost", help="Inference server host")
    parser.add_argument("--port", type=int, default=5555, help="Inference server port")

    # Controls
    parser.add_argument("--keymap", type=str, help="Path to game-specific key mapping JSON")
    parser.add_argument("--sensitivity", type=float, default=5.0, help="Mouse sensitivity")
    parser.add_argument("--fps", type=float, default=30.0, help="Target frame rate")
    parser.add_argument("--allow-menu", action="store_true", help="Allow START/BACK/GUIDE buttons")

    # Recording
    parser.add_argument("--record", action="store_true", help="Record gameplay video")
    parser.add_argument("--out-dir", type=str, default="./nitrogen_out", help="Output directory")

    # Debug
    parser.add_argument("--show-overlay", action="store_true", help="Show debug overlay window")
    parser.add_argument("--dry-run", action="store_true", help="Capture frames but don't inject input")

    return parser.parse_args()


def main():
    args = parse_args()

    # ── Connect to inference server ──────────────────────────────────
    print(f"[play_mac] Connecting to NitroGen server at {args.host}:{args.port}...")
    policy = ModelClient(host=args.host, port=args.port)
    policy.reset()
    policy_info = policy.info()
    print(f"[play_mac] Server info: {json.dumps(policy_info, indent=2, default=str)}")

    action_downsample_ratio = policy_info.get("action_downsample_ratio", 1)

    # ── Load key mapping ─────────────────────────────────────────────
    key_map = None
    if args.keymap:
        key_map = load_key_map(args.keymap)
        print(f"[play_mac] Loaded key map from {args.keymap}: {len(key_map)} bindings")

    # ── Create environment ───────────────────────────────────────────
    env = MacGameEnv(
        window_title=args.window,
        bundle_id=args.bundle_id,
        display_id=args.display,
        target_fps=args.fps,
        key_map=key_map,
        mouse_sensitivity=args.sensitivity,
        no_menu=not args.allow_menu,
    )

    print(f"[play_mac] Capturing: {env._capture.window_title}")
    print(f"[play_mac] Target FPS: {args.fps}")
    print(f"[play_mac] Dry run: {args.dry_run}")
    print(f"[play_mac] Press Ctrl+C to stop")
    print()

    # ── Recording setup ──────────────────────────────────────────────
    recorder = None
    actions_log = []
    if args.record:
        out_dir = Path(args.out_dir)
        out_dir.mkdir(parents=True, exist_ok=True)

        # Find next recording number
        existing = sorted(out_dir.glob("*_CLEAN.mp4"))
        next_num = 1
        if existing:
            nums = [int(f.stem.split("_")[0]) for f in existing if f.stem.split("_")[0].isdigit()]
            next_num = max(nums, default=0) + 1

        clean_path = out_dir / f"{next_num:04d}_CLEAN.mp4"
        debug_path = out_dir / f"{next_num:04d}_DEBUG.mp4"
        action_path = out_dir / f"{next_num:04d}_ACTIONS.json"
        print(f"[play_mac] Recording to {clean_path}")

        if VideoRecorder:
            recorder = VideoRecorder(str(clean_path), fps=args.fps)

    # ── Graceful shutdown ────────────────────────────────────────────
    running = True

    def signal_handler(sig, frame):
        nonlocal running
        print("\n[play_mac] Stopping...")
        running = False

    signal.signal(signal.SIGINT, signal_handler)
    signal.signal(signal.SIGTERM, signal_handler)

    # ── Main loop ────────────────────────────────────────────────────
    obs, info = env.reset()
    step = 0
    fps_window = []

    try:
        while running:
            step_start = time.monotonic()

            # Preprocess: resize to 256x256 (should already be from capture)
            main_cv = cv2.cvtColor(np.array(obs), cv2.COLOR_RGB2BGR)
            final_image = cv2.resize(main_cv, (256, 256), interpolation=cv2.INTER_AREA)
            pil_image = Image.fromarray(cv2.cvtColor(final_image, cv2.COLOR_BGR2RGB))

            # Get model prediction
            try:
                result = policy.predict(np.array(pil_image))
            except Exception as e:
                print(f"[play_mac] Prediction error: {e}")
                time.sleep(0.1)
                obs = env._capture.grab()
                continue

            action = result["action"]

            # Apply action (unless dry run)
            if not args.dry_run:
                obs, reward, done, truncated, info = env.step(action)
            else:
                obs = env._capture.grab()

            # Record
            if recorder:
                recorder.write(final_image)
                actions_log.append({
                    "step": step,
                    "action": {k: v.tolist() if isinstance(v, np.ndarray) else v
                               for k, v in action.items()},
                })

            # Debug overlay
            if args.show_overlay:
                debug_frame = final_image.copy()
                _draw_action_overlay(debug_frame, action)
                cv2.imshow("NitroGen macOS", debug_frame)
                if cv2.waitKey(1) & 0xFF == ord('q'):
                    break

            # FPS tracking
            step_time = time.monotonic() - step_start
            fps_window.append(step_time)
            if len(fps_window) > 60:
                fps_window.pop(0)

            step += 1
            if step % 60 == 0:
                avg_fps = len(fps_window) / sum(fps_window) if fps_window else 0
                capture_fps = info.get("fps", 0)
                print(
                    f"[play_mac] step={step:6d}  "
                    f"loop={avg_fps:.1f}fps  "
                    f"capture={capture_fps:.1f}fps  "
                    f"window='{info.get('window', '?')}'"
                )

    finally:
        # Clean up
        env.close()
        if recorder:
            recorder.close()
        if actions_log and args.record:
            with open(str(action_path), "w") as f:
                json.dump(actions_log, f, indent=2)
            print(f"[play_mac] Saved {len(actions_log)} actions to {action_path}")
        if args.show_overlay:
            cv2.destroyAllWindows()

        print(f"[play_mac] Done. {step} steps played.")


def _draw_action_overlay(frame: np.ndarray, action: OrderedDict):
    """Draw button states and stick positions on the debug frame."""
    y = 10
    for name, value in action.items():
        if isinstance(value, np.ndarray):
            val_str = f"{value.flat[0]:.2f}" if value.dtype.kind == 'f' else str(value.flat[0])
        else:
            val_str = f"{value:.2f}" if isinstance(value, float) else str(value)

        # Color: green if active, gray if not
        active = False
        if isinstance(value, (int, float)):
            active = float(value) >= BUTTON_PRESS_THRES
        elif isinstance(value, np.ndarray):
            v = float(value.flat[0])
            active = abs(v) > 0.15 if "AXIS" in name else v >= BUTTON_PRESS_THRES

        color = (0, 255, 0) if active else (128, 128, 128)
        cv2.putText(frame, f"{name}: {val_str}", (5, y + 10),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.3, color, 1)
        y += 12


if __name__ == "__main__":
    main()
