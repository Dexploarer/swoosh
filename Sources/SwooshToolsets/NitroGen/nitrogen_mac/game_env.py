"""
nitrogen_mac/game_env.py — macOS Gymnasium environment for NitroGen
Drop-in replacement for nitrogen.game_env.GamepadEnv (Windows-only).

Wraps MacScreenCapture + MacInputInjector into a Gymnasium Env
that NitroGen's play loop expects.
"""

import time
from collections import OrderedDict
from typing import Optional

import numpy as np
from gymnasium import Env
from gymnasium.spaces import Box, Dict

from nitrogen_mac.capture import MacScreenCapture
from nitrogen_mac.input_inject import MacInputInjector, BUTTON_THRESHOLD


# Xbox button names in NitroGen's canonical order
BUTTON_NAMES = [
    "BACK", "DPAD_DOWN", "DPAD_LEFT", "DPAD_RIGHT", "DPAD_UP",
    "EAST", "GUIDE", "LEFT_SHOULDER", "LEFT_THUMB",
    "NORTH", "RIGHT_SHOULDER", "RIGHT_THUMB",
    "SOUTH", "START", "WEST",
]

AXIS_NAMES = [
    "AXIS_LEFTX", "AXIS_LEFTY",
    "LEFT_TRIGGER", "RIGHT_TRIGGER",
    "AXIS_RIGHTX", "AXIS_RIGHTY",
]


class MacGameEnv(Env):
    """
    macOS game environment for NitroGen.
    
    Observation: 256x256 RGB image (Box)
    Action: OrderedDict of button states + axis values
    
    Usage:
        env = MacGameEnv(window_title="Celeste")
        obs, info = env.reset()
        while True:
            action = model.predict(obs)
            obs, reward, done, truncated, info = env.step(action)
    """

    metadata = {"render_modes": ["rgb_array"]}

    def __init__(
        self,
        window_title: Optional[str] = None,
        bundle_id: Optional[str] = None,
        display_id: Optional[int] = None,
        target_fps: float = 30.0,
        key_map: Optional[dict] = None,
        mouse_sensitivity: float = 5.0,
        use_wasd: bool = True,
        no_menu: bool = True,
    ):
        """
        Args:
            window_title: Game window title (partial match OK).
            bundle_id: macOS bundle identifier.
            display_id: Capture entire display instead of window.
            target_fps: Frame rate cap for the game loop.
            key_map: Custom button→keycode mapping.
            mouse_sensitivity: Right-stick → mouse movement multiplier.
            use_wasd: Map left stick to WASD (True) or arrows (False).
            no_menu: Block START/BACK/GUIDE buttons to avoid menu interference.
        """
        super().__init__()

        self._target_fps = target_fps
        self._frame_time = 1.0 / target_fps
        self._no_menu = no_menu
        self._last_step_time = 0.0

        # Screen capture
        self._capture = MacScreenCapture(
            window_title=window_title,
            bundle_id=bundle_id,
            display_id=display_id,
        )

        # Input injection
        self._injector = MacInputInjector(
            key_map=key_map,
            mouse_sensitivity=mouse_sensitivity,
            use_wasd=use_wasd,
        )

        # Gym spaces
        self.observation_space = Box(
            low=0, high=255,
            shape=(256, 256, 3),
            dtype=np.uint8,
        )

        # Action space: buttons (binary) + axes (continuous)
        self.action_space = Dict({
            name: Box(low=0, high=1, shape=(), dtype=np.float32)
            for name in BUTTON_NAMES
        } | {
            name: Box(low=-1, high=1, shape=(), dtype=np.float32)
            for name in AXIS_NAMES
        })

        # Stats
        self._step_count = 0
        self._episode_start = 0.0

    def reset(self, seed=None, options=None):
        """Reset the environment (grab first frame)."""
        super().reset(seed=seed)
        self._step_count = 0
        self._episode_start = time.monotonic()
        self._injector.release_all()

        obs = self._capture.grab()
        return obs, {"fps": self._capture.fps, "step": 0}

    def step(self, action: OrderedDict):
        """
        Execute one step:
        1. Inject the action as keyboard/mouse events
        2. Wait for frame timing
        3. Capture the next frame
        
        Args:
            action: NitroGen-format OrderedDict
            
        Returns:
            (observation, reward, terminated, truncated, info)
        """
        # Rate limit to target FPS
        now = time.monotonic()
        elapsed = now - self._last_step_time
        if elapsed < self._frame_time:
            time.sleep(self._frame_time - elapsed)

        # Filter menu buttons if requested
        if self._no_menu:
            action = _filter_menu_buttons(action)

        # Inject the action
        self._injector.apply_action(action)

        # Capture next frame
        obs = self._capture.grab()

        self._step_count += 1
        self._last_step_time = time.monotonic()

        info = {
            "fps": self._capture.fps,
            "step": self._step_count,
            "window": self._capture.window_title,
        }

        # NitroGen doesn't use reward/done — these are for Gymnasium compat
        return obs, 0.0, False, False, info

    def close(self):
        """Clean up: release all pressed keys."""
        self._injector.release_all()
        super().close()

    def render(self):
        """Return the last captured frame."""
        return self._capture.grab()


def _filter_menu_buttons(action: OrderedDict) -> OrderedDict:
    """Zero out menu-related buttons to prevent accidental pausing."""
    filtered = OrderedDict(action)
    for key in ("START", "BACK", "GUIDE"):
        if key in filtered:
            filtered[key] = 0
    return filtered


def make_zero_action() -> OrderedDict:
    """Create a neutral (no-input) action dict."""
    action = OrderedDict()
    for name in BUTTON_NAMES:
        action[name] = 0
    for name in AXIS_NAMES:
        action[name] = np.array([128], dtype=np.int64)  # Center = 128
    return action
