"""
nitrogen_mac/capture.py — macOS screen capture via ScreenCaptureKit
Replaces dxcam (DirectX) used by the Windows harness.

Uses SCScreenshotManager for per-frame capture of a specific window.
Requires macOS 14+ and Screen Recording permission.
"""

import asyncio
import time
from typing import Optional

import numpy as np

try:
    import ScreenCaptureKit as SCK
    import Quartz
    import objc
    from Foundation import NSRunLoop, NSDate
    HAS_SCK = True
except ImportError:
    HAS_SCK = False

try:
    import cv2
    HAS_CV2 = True
except ImportError:
    HAS_CV2 = False


class MacScreenCapture:
    """
    Captures frames from a macOS window using ScreenCaptureKit.
    
    Drop-in replacement for dxcam in the NitroGen pipeline.
    Captures at 256x256 for direct model input.
    """

    CAPTURE_WIDTH = 256
    CAPTURE_HEIGHT = 256

    def __init__(
        self,
        window_title: Optional[str] = None,
        bundle_id: Optional[str] = None,
        display_id: Optional[int] = None,
    ):
        """
        Args:
            window_title: Partial or exact match for the game window title.
            bundle_id: macOS bundle identifier (e.g. "com.game.example").
            display_id: Capture an entire display instead of a window.
        """
        if not HAS_SCK:
            raise RuntimeError(
                "ScreenCaptureKit not available. Requires macOS 14+ and "
                "pip install pyobjc-framework-ScreenCaptureKit pyobjc-framework-Quartz"
            )

        self._window_title = window_title
        self._bundle_id = bundle_id
        self._display_id = display_id

        self._sc_content: Optional[object] = None
        self._sc_filter: Optional[object] = None
        self._sc_config: Optional[object] = None
        self._target_window: Optional[object] = None
        self._target_display: Optional[object] = None

        # Performance tracking
        self._frame_count = 0
        self._last_fps_time = time.monotonic()
        self._fps = 0.0

        self._setup_capture()

    def _setup_capture(self):
        """Initialize ScreenCaptureKit content and filter."""
        # Get shareable content (all windows + displays)
        content = _get_shareable_content_sync()
        self._sc_content = content

        if self._display_id is not None:
            self._target_display = self._find_display(content)
            self._sc_filter = SCK.SCContentFilter.alloc().initWithDisplay_excludingWindows_(
                self._target_display, []
            )
        else:
            self._target_window = self._find_window(content)
            self._sc_filter = SCK.SCContentFilter.alloc().initWithDesktopIndependentWindow_(
                self._target_window
            )

        # Configure capture: 256x256, BGRA pixel format
        self._sc_config = SCK.SCStreamConfiguration.alloc().init()
        self._sc_config.setWidth_(self.CAPTURE_WIDTH)
        self._sc_config.setHeight_(self.CAPTURE_HEIGHT)
        self._sc_config.setPixelFormat_(Quartz.kCVPixelFormatType_32BGRA)
        self._sc_config.setShowsCursor_(False)
        self._sc_config.setScalesToFit_(True)

    def _find_window(self, content) -> object:
        """Find the target window by title or bundle ID."""
        windows = content.windows()

        if self._bundle_id:
            for w in windows:
                app = w.owningApplication()
                if app and app.bundleIdentifier() == self._bundle_id:
                    title = w.title() or "(untitled)"
                    print(f"[capture] Found window by bundle ID: '{title}' ({self._bundle_id})")
                    return w

        if self._window_title:
            # Exact match first
            for w in windows:
                if w.title() == self._window_title:
                    print(f"[capture] Found window (exact): '{w.title()}'")
                    return w
            # Partial match
            needle = self._window_title.lower()
            for w in windows:
                title = w.title() or ""
                if needle in title.lower():
                    print(f"[capture] Found window (partial): '{title}'")
                    return w

        # List available windows for debugging
        print("[capture] Available windows:")
        for w in windows:
            app = w.owningApplication()
            bid = app.bundleIdentifier() if app else "?"
            print(f"  - '{w.title() or '(untitled)'}' [{bid}]")

        raise ValueError(
            f"No window found matching title='{self._window_title}' "
            f"or bundle_id='{self._bundle_id}'"
        )

    def _find_display(self, content) -> object:
        """Find target display by CGDirectDisplayID."""
        for d in content.displays():
            if d.displayID() == self._display_id:
                print(f"[capture] Found display: {self._display_id}")
                return d
        raise ValueError(f"No display found with ID: {self._display_id}")

    def grab(self) -> np.ndarray:
        """
        Capture a single frame as a 256x256 RGB numpy array.
        
        Returns:
            np.ndarray of shape (256, 256, 3) in RGB order, dtype uint8.
        """
        image = _screenshot_sync(self._sc_filter, self._sc_config)

        if image is None:
            # Return black frame on failure (keep the loop alive)
            return np.zeros((self.CAPTURE_HEIGHT, self.CAPTURE_WIDTH, 3), dtype=np.uint8)

        # Convert CGImage → numpy
        frame = _cgimage_to_numpy(image)

        # Track FPS
        self._frame_count += 1
        now = time.monotonic()
        elapsed = now - self._last_fps_time
        if elapsed >= 1.0:
            self._fps = self._frame_count / elapsed
            self._frame_count = 0
            self._last_fps_time = now

        return frame

    @property
    def fps(self) -> float:
        """Current capture frames per second."""
        return self._fps

    @property
    def window_title(self) -> str:
        """Title of the captured window."""
        if self._target_window:
            return self._target_window.title() or "(untitled)"
        return f"Display {self._display_id}"

    def refresh_target(self):
        """Re-acquire the target window (useful if the game restarts)."""
        self._setup_capture()


# ─── Synchronous helpers (bridge async SCK to sync Python) ────────────

def _get_shareable_content_sync():
    """Blocking wrapper around SCShareableContent."""
    result = {"content": None, "error": None}
    event = asyncio.Event()

    def handler(content, error):
        result["content"] = content
        result["error"] = error
        event._loop = None  # Signal done

    # Use the completion-handler API
    SCK.SCShareableContent.getShareableContentExcludingDesktopWindows_onScreenWindowsOnly_completionHandler_(
        False, True, handler
    )

    # Pump the run loop until the handler fires
    timeout = time.monotonic() + 5.0
    while result["content"] is None and result["error"] is None:
        NSRunLoop.currentRunLoop().runUntilDate_(
            NSDate.dateWithTimeIntervalSinceNow_(0.01)
        )
        if time.monotonic() > timeout:
            raise TimeoutError("SCShareableContent timed out after 5s")

    if result["error"]:
        raise RuntimeError(f"SCShareableContent error: {result['error']}")

    return result["content"]


def _screenshot_sync(content_filter, config) -> Optional[object]:
    """Blocking single-frame screenshot via SCScreenshotManager."""
    result = {"image": None, "error": None, "done": False}

    def handler(image, error):
        result["image"] = image
        result["error"] = error
        result["done"] = True

    SCK.SCScreenshotManager.captureImageWithFilter_configuration_completionHandler_(
        content_filter, config, handler
    )

    timeout = time.monotonic() + 2.0
    while not result["done"]:
        NSRunLoop.currentRunLoop().runUntilDate_(
            NSDate.dateWithTimeIntervalSinceNow_(0.005)
        )
        if time.monotonic() > timeout:
            return None

    if result["error"]:
        return None

    return result["image"]


def _cgimage_to_numpy(cgimage) -> np.ndarray:
    """Convert a CGImage to a 256x256 RGB numpy array."""
    width = Quartz.CGImageGetWidth(cgimage)
    height = Quartz.CGImageGetHeight(cgimage)
    bytes_per_row = Quartz.CGImageGetBytesPerRow(cgimage)

    # Get pixel data
    data_provider = Quartz.CGImageGetDataProvider(cgimage)
    data = Quartz.CGDataProviderCopyData(data_provider)

    # BGRA → numpy
    arr = np.frombuffer(data, dtype=np.uint8)
    arr = arr.reshape((height, bytes_per_row // 4, 4))[:height, :width, :]

    # BGRA → RGB
    rgb = arr[:, :, [2, 1, 0]]

    # Resize to 256x256 if needed (SCK should already do this)
    if rgb.shape[:2] != (256, 256):
        if HAS_CV2:
            rgb = cv2.resize(rgb, (256, 256), interpolation=cv2.INTER_AREA)
        else:
            from PIL import Image
            pil = Image.fromarray(rgb)
            pil = pil.resize((256, 256), Image.LANCZOS)
            rgb = np.array(pil)

    return rgb.copy()  # Ensure contiguous


# ─── Fallback: Quartz CGWindowListCreateImage (for macOS < 14) ────────

class QuartzFallbackCapture:
    """
    Legacy capture using CGWindowListCreateImage.
    Deprecated on macOS 14+ but works on older systems.
    """

    def __init__(self, window_id: int):
        self._window_id = window_id

    def grab(self) -> np.ndarray:
        bounds = Quartz.CGRectNull
        image = Quartz.CGWindowListCreateImage(
            bounds,
            Quartz.kCGWindowListOptionIncludingWindow,
            self._window_id,
            Quartz.kCGWindowImageBoundsIgnoreFraming,
        )
        if image is None:
            return np.zeros((256, 256, 3), dtype=np.uint8)
        return _cgimage_to_numpy(image)
