"""
nitrogen_mac/input_inject.py — macOS input injection via CGEvent + IOKit
Replaces vgamepad (ViGEm) used by the Windows harness.

Translates NitroGen's Xbox gamepad action dict into macOS events.

Strategy:
  1. For games that accept keyboard: map gamepad buttons → key presses via CGEvent
  2. For games that accept mouse: map joystick axes → mouse movement via CGEvent
  3. For games that accept GCController: create a virtual HID gamepad via IOKit

Most Mac/Steam games support keyboard+mouse, so strategy 1+2 is the primary path.
"""

import time
from collections import OrderedDict
from typing import Optional

import numpy as np

try:
    import Quartz
    HAS_QUARTZ = True
except ImportError:
    HAS_QUARTZ = False


# ─── Xbox → Keyboard/Mouse mapping ───────────────────────────────────
# Default mapping for common game controls.
# Users can override this with a JSON config file per game.

DEFAULT_KEY_MAP = {
    # Face buttons
    "SOUTH": Quartz.kVK_Space,         # A → Jump / Confirm
    "EAST": Quartz.kVK_Escape,         # B → Cancel / Back
    "WEST": Quartz.kVK_ANSI_E,         # X → Interact / Use
    "NORTH": Quartz.kVK_ANSI_R,        # Y → Reload / Special

    # D-pad → Arrow keys
    "DPAD_UP": Quartz.kVK_UpArrow,
    "DPAD_DOWN": Quartz.kVK_DownArrow,
    "DPAD_LEFT": Quartz.kVK_LeftArrow,
    "DPAD_RIGHT": Quartz.kVK_RightArrow,

    # Shoulders + triggers
    "LEFT_SHOULDER": Quartz.kVK_ANSI_Q,     # LB
    "RIGHT_SHOULDER": Quartz.kVK_ANSI_F,    # RB
    "LEFT_TRIGGER": Quartz.kVK_ANSI_Z,      # LT → Block / Aim
    "RIGHT_TRIGGER": Quartz.kVK_ANSI_X,     # RT → Attack / Shoot

    # System
    "START": Quartz.kVK_Return,
    "BACK": Quartz.kVK_Tab,
    "GUIDE": Quartz.kVK_ANSI_G,

    # Thumbsticks (click)
    "LEFT_THUMB": Quartz.kVK_ANSI_C,        # L3 → Crouch
    "RIGHT_THUMB": Quartz.kVK_ANSI_V,       # R3 → Melee
}

# WASD for left stick
WASD_MAP = {
    "up": Quartz.kVK_ANSI_W,
    "down": Quartz.kVK_ANSI_S,
    "left": Quartz.kVK_ANSI_A,
    "right": Quartz.kVK_ANSI_D,
}

# Joystick dead zone — ignore inputs below this threshold
STICK_DEADZONE = 0.15

# Button press threshold (NitroGen outputs probabilities 0-1)
BUTTON_THRESHOLD = 0.5


class MacInputInjector:
    """
    Injects NitroGen gamepad actions into macOS as keyboard + mouse events.
    
    This is the primary input path. For games using GCController,
    use MacVirtualGamepad instead (requires IOKit / root).
    """

    def __init__(
        self,
        key_map: Optional[dict] = None,
        mouse_sensitivity: float = 5.0,
        use_wasd: bool = True,
    ):
        """
        Args:
            key_map: Override button→keycode mapping. Falls back to DEFAULT_KEY_MAP.
            mouse_sensitivity: Pixels per unit of right-stick movement.
            use_wasd: Map left stick to WASD keys instead of arrow keys.
        """
        if not HAS_QUARTZ:
            raise RuntimeError(
                "Quartz not available. Requires macOS and "
                "pip install pyobjc-framework-Quartz"
            )

        self._key_map = key_map or DEFAULT_KEY_MAP
        self._mouse_sensitivity = mouse_sensitivity
        self._use_wasd = use_wasd

        # Track currently pressed keys to avoid key-repeat spam
        self._pressed_keys: set[int] = set()

        # Track mouse position for relative movement
        self._mouse_x = 0.0
        self._mouse_y = 0.0

    def apply_action(self, action: OrderedDict):
        """
        Apply a NitroGen action dict to macOS.
        
        Args:
            action: OrderedDict matching NitroGen's output format:
                - Binary buttons: "SOUTH", "WEST", "EAST", etc. → 0 or 1
                - Continuous axes: "AXIS_LEFTX", "AXIS_LEFTY", etc. → float or np.array
        """
        self._apply_buttons(action)
        self._apply_left_stick(action)
        self._apply_right_stick(action)

    def _apply_buttons(self, action: OrderedDict):
        """Press/release keyboard keys based on button states."""
        for button_name, keycode in self._key_map.items():
            value = action.get(button_name, 0)
            if isinstance(value, np.ndarray):
                value = float(value.flat[0])
            pressed = float(value) >= BUTTON_THRESHOLD

            if pressed and keycode not in self._pressed_keys:
                _key_down(keycode)
                self._pressed_keys.add(keycode)
            elif not pressed and keycode in self._pressed_keys:
                _key_up(keycode)
                self._pressed_keys.discard(keycode)

    def _apply_left_stick(self, action: OrderedDict):
        """Map left stick to WASD or D-pad keys."""
        lx = _extract_axis(action.get("AXIS_LEFTX", 0))
        ly = _extract_axis(action.get("AXIS_LEFTY", 0))

        if self._use_wasd:
            self._stick_to_keys(lx, ly, WASD_MAP)
        else:
            dpad_map = {
                "up": self._key_map.get("DPAD_UP", Quartz.kVK_UpArrow),
                "down": self._key_map.get("DPAD_DOWN", Quartz.kVK_DownArrow),
                "left": self._key_map.get("DPAD_LEFT", Quartz.kVK_LeftArrow),
                "right": self._key_map.get("DPAD_RIGHT", Quartz.kVK_RightArrow),
            }
            self._stick_to_keys(lx, ly, dpad_map)

    def _apply_right_stick(self, action: OrderedDict):
        """Map right stick to mouse movement (for camera control)."""
        rx = _extract_axis(action.get("AXIS_RIGHTX", 0))
        ry = _extract_axis(action.get("AXIS_RIGHTY", 0))

        if abs(rx) < STICK_DEADZONE and abs(ry) < STICK_DEADZONE:
            return

        dx = rx * self._mouse_sensitivity
        dy = ry * self._mouse_sensitivity

        # Get current mouse position
        pos = Quartz.CGEventGetLocation(
            Quartz.CGEventCreate(None)
        )
        new_x = pos.x + dx
        new_y = pos.y + dy

        event = Quartz.CGEventCreateMouseEvent(
            None,
            Quartz.kCGEventMouseMoved,
            Quartz.CGPointMake(new_x, new_y),
            Quartz.kCGMouseButtonLeft,
        )
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)

    def _stick_to_keys(self, x: float, y: float, key_map: dict):
        """Convert stick axes to key presses (4-directional)."""
        # Up/Down (inverted: negative Y = up on gamepad)
        if y < -STICK_DEADZONE:
            self._ensure_pressed(key_map["up"])
        else:
            self._ensure_released(key_map["up"])

        if y > STICK_DEADZONE:
            self._ensure_pressed(key_map["down"])
        else:
            self._ensure_released(key_map["down"])

        # Left/Right
        if x < -STICK_DEADZONE:
            self._ensure_pressed(key_map["left"])
        else:
            self._ensure_released(key_map["left"])

        if x > STICK_DEADZONE:
            self._ensure_pressed(key_map["right"])
        else:
            self._ensure_released(key_map["right"])

    def _ensure_pressed(self, keycode: int):
        if keycode not in self._pressed_keys:
            _key_down(keycode)
            self._pressed_keys.add(keycode)

    def _ensure_released(self, keycode: int):
        if keycode in self._pressed_keys:
            _key_up(keycode)
            self._pressed_keys.discard(keycode)

    def release_all(self):
        """Release all currently pressed keys. Call on exit."""
        for keycode in list(self._pressed_keys):
            _key_up(keycode)
        self._pressed_keys.clear()

    def __del__(self):
        try:
            self.release_all()
        except Exception:
            pass


# ─── CGEvent helpers ──────────────────────────────────────────────────

def _key_down(keycode: int):
    """Post a key-down event."""
    event = Quartz.CGEventCreateKeyboardEvent(None, keycode, True)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)


def _key_up(keycode: int):
    """Post a key-up event."""
    event = Quartz.CGEventCreateKeyboardEvent(None, keycode, False)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)


def _mouse_click(x: float, y: float, button: int = Quartz.kCGMouseButtonLeft):
    """Click at absolute position."""
    point = Quartz.CGPointMake(x, y)
    down = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseDown, point, button)
    up = Quartz.CGEventCreateMouseEvent(None, Quartz.kCGEventLeftMouseUp, point, button)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, down)
    time.sleep(0.01)
    Quartz.CGEventPost(Quartz.kCGHIDEventTap, up)


# ─── Axis value extraction ───────────────────────────────────────────

def _extract_axis(value) -> float:
    """
    Extract a float from NitroGen's axis value.
    NitroGen outputs axes as either:
    - np.array([token_id]) (tokenized, integer 0-255 → map to -1.0..+1.0)
    - float directly
    """
    if isinstance(value, np.ndarray):
        v = int(value.flat[0])
        # NitroGen tokenizes axes to 0-255 range, center=128
        return (v - 128) / 128.0
    return float(value)


# ─── Game-specific key map loading ────────────────────────────────────

def load_key_map(path: str) -> dict:
    """
    Load a game-specific key map from a JSON file.
    
    Format:
    {
        "SOUTH": "space",
        "EAST": "escape",
        "AXIS_LEFTX": "wasd",
        ...
    }
    """
    import json
    KEY_NAME_TO_CODE = {
        "space": Quartz.kVK_Space,
        "escape": Quartz.kVK_Escape,
        "return": Quartz.kVK_Return,
        "tab": Quartz.kVK_Tab,
        "shift": Quartz.kVK_Shift,
        "control": Quartz.kVK_Control,
        "option": Quartz.kVK_Option,
        "command": Quartz.kVK_Command,
        "up": Quartz.kVK_UpArrow,
        "down": Quartz.kVK_DownArrow,
        "left": Quartz.kVK_LeftArrow,
        "right": Quartz.kVK_RightArrow,
    }
    # Add a-z
    for i, c in enumerate("abcdefghijklmnopqrstuvwxyz"):
        KEY_NAME_TO_CODE[c] = getattr(Quartz, f"kVK_ANSI_{c.upper()}")
    # Add 0-9
    for i in range(10):
        KEY_NAME_TO_CODE[str(i)] = getattr(Quartz, f"kVK_ANSI_{i}")

    with open(path) as f:
        raw = json.load(f)

    result = {}
    for button, key_name in raw.items():
        key_name = key_name.lower()
        if key_name in KEY_NAME_TO_CODE:
            result[button] = KEY_NAME_TO_CODE[key_name]
        else:
            print(f"[input] Warning: unknown key '{key_name}' for button '{button}'")

    return result
