# NitroGen macOS Game Capture Harness

Drop-in replacement for NitroGen's Windows-only `play.py` / `game_env.py`.
Runs the NVIDIA NitroGen 493M gaming agent on macOS using:

- **ScreenCaptureKit** (via PyObjC) for zero-copy GPU-accelerated game capture
- **CGEvent** (via Quartz) for keyboard/mouse input injection
- **Virtual HID gamepad** (via IOKit) for controller emulation
- **ZMQ** for communication with the NitroGen inference server

## Architecture

```
┌─────────────────────┐     ZMQ (tcp://localhost:5555)
│  serve.py (model)   │◄────────────────────────────────┐
│  NitroGen 493M      │                                  │
│  PyTorch MPS/CPU    │─────────────────────────────────►│
└─────────────────────┘     pickle({actions})            │
                                                         │
┌─────────────────────┐                         ┌────────┴────────┐
│  Game (any macOS    │  ScreenCaptureKit       │  play_mac.py    │
│  window / fullscr)  │────────────────────────►│  (this harness) │
│                     │◄───── CGEvent inject ───│                 │
└─────────────────────┘                         └─────────────────┘
```

## Usage

```bash
# 1. Start the inference server (can be same or different machine)
python scripts/serve.py path/to/ng.pt --port 5555

# 2. Run the macOS harness
python -m nitrogen_mac.play_mac --window "Game Title" --port 5555

# Or by bundle ID
python -m nitrogen_mac.play_mac --bundle-id com.game.example --port 5555
```

## Requirements

- macOS 14+ (Sonoma) — ScreenCaptureKit
- Python 3.12+
- Screen Recording permission granted to the terminal/Python
- Accessibility permission for input injection

```bash
pip install pyobjc-framework-ScreenCaptureKit pyobjc-framework-Quartz \
            pyzmq numpy opencv-python pillow
```
