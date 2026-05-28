---
name: gaming-agent
description: How to control NitroGen and navigate cloud gaming platforms for autonomous gameplay
category: gaming
triggerPatterns:
  - play
  - game
  - gaming
  - nitrogen
  - start playing
  - stop playing
  - controller
platforms:
  - macOS
---

# Gaming Agent

This skill teaches you how to control NitroGen — the autonomous gameplay engine — and navigate cloud gaming platforms to find, launch, and play games on the user's behalf.

## 1. NitroGen Overview

NitroGen is NVIDIA's 493M parameter gaming agent model (paper: arXiv:2601.02427). It observes the game screen and outputs Xbox controller actions in real time.

- **Input**: A single 256×256 RGB frame (NO multi-frame context, NO memory of past frames)
- **Output**: 16-step action chunks — 17 binary buttons + 4 continuous joystick axes per step
- **Architecture**: SigLIP 2 vision encoder → Diffusion Transformer (DiT) action head
- **Training**: 40,000 hours of gameplay video across 1,000+ games via behavior cloning (no RL)
- **macOS implementation**: Uses `ScreenCaptureKit` for frame capture and `CGEvent` for input injection
- **Two processes**:
  - `serve_mac.py` — inference server exposing the NitroGen model over ZMQ on port 5555
  - `play_mac.py` — capture-and-inject loop that grabs frames, sends them to the server, and injects the predicted actions into the game window

### Critical Limitations — What NitroGen CANNOT Do

> **YOU (the orchestrating agent) must handle everything NitroGen cannot.**

1. **Cannot navigate menus or start screens.** It was trained on gameplay footage, not menu footage. Title screens, pause menus, options screens, and character creation are outside its capability.
2. **Cannot type text.** It outputs only gamepad actions. Entering usernames, character names, or chat messages requires YOUR intervention via `gaming_type_text` or instructing the user.
3. **Cannot read or understand text on screen.** It perceives pixels, not language. It does not know what a button label says.
4. **Single-frame reactive.** No memory of what happened even 1 second ago. Long-horizon planning, quest objectives, inventory management, and route planning are outside its capability.
5. **Runs slower than real-time.** NitroGen hooks the game's system clock to achieve frame-by-frame synchronization. Expect slow-motion gameplay, not 60fps real-time play.
6. **Best at**: 3D action games, 2D platformers, exploration, combat. **Worst at**: RTS, MOBA, text-heavy RPGs, games requiring mouse+keyboard precision.

### Your Role as Orchestrator

- **Before gameplay**: Navigate menus, search for games, click Play, enter usernames, get past title screens — all using `gaming_*` tools or voice instructions to the user.
- **During gameplay**: Let NitroGen play. Monitor via `nitrogen_status` and `nitrogen_screenshot`. Intervene (stop NitroGen, navigate a menu, resume) if it gets stuck on a non-gameplay screen.
- **After gameplay**: Stop NitroGen, report results, offer to play again or switch games.

## 2. When to Start NitroGen

**ONLY start NitroGen after the game window is visible and actively rendering.**

- For cloud platforms (Xbox Cloud Gaming, GeForce NOW, Amazon Luna, Boosteroid): wait until the stream is connected and the game is rendering — `streamStatus == .playing`
- For native apps (Steam Link, PlayStation Remote Play): wait until the app window is detected by the system
- **NEVER** start before the game is loaded — `play_mac.py` will crash with `No window found` if the target window doesn't exist

**Startup sequence:**

1. User selects a platform (or tells you which game to play)
2. Platform connects and the game loads
3. Agent verifies the game window is visible via `nitrogen_status`
4. Agent calls `nitrogen_start`

## 3. How to Start

Call `nitrogen_start` with the following parameters:

| Parameter     | Type   | Required | Description                                              |
|---------------|--------|----------|----------------------------------------------------------|
| `windowTitle` | String | Yes      | Partial match for the game window title (e.g., `Celeste`, `Minecraft`) |
| `bundleID`    | String | No       | macOS bundle identifier if known (e.g., `com.valvesoftware.steamlink`) |
| `keymap`      | String | No       | Path to a game-specific keymap JSON file                 |
| `fps`         | Int    | No       | Target frame rate for capture/inference. Default: `30`   |

Example:
```
nitrogen_start(windowTitle: "Celeste", keymap: "keymaps/celeste.json", fps: 30)
```

## 4. Available Keymaps

Keymaps are JSON files in `Sources/SwooshToolsets/NitroGen/keymaps/`. They map NitroGen's Xbox controller outputs to keyboard/mouse inputs for a specific game.

### Game-specific keymaps

| File                | Game           | Genre         |
|---------------------|----------------|---------------|
| `celeste.json`      | Celeste        | Platformer    |
| `minecraft.json`    | Minecraft      | Sandbox       |
| `hollow_knight.json`| Hollow Knight  | Metroidvania  |
| `terraria.json`     | Terraria       | Sandbox       |
| `stardew_valley.json`| Stardew Valley| Farming sim   |
| `cuphead.json`      | Cuphead        | Run-and-gun   |
| `hades.json`        | Hades          | Roguelike     |
| `elden_ring.json`   | Elden Ring     | Action RPG    |
| `rocket_league.json`| Rocket League  | Sports        |
| `fortnite.json`     | Fortnite       | Battle royale |
| `valorant.json`     | Valorant       | Tactical FPS  |

### Default keymap (used when no file is specified)

| Controller Input | Keyboard/Mouse Output | Typical use        |
|------------------|-----------------------|--------------------|
| SOUTH (A)        | Space                 | Jump / Confirm     |
| EAST (B)         | Escape                | Cancel / Back      |
| WEST (X)         | E                     | Interact           |
| NORTH (Y)        | R                     | Reload             |
| Left stick       | WASD                  | Movement           |
| Right stick      | Mouse movement        | Camera / Aim       |
| Left shoulder    | Q                     | Ability / Lean     |
| Right shoulder   | F                     | Ability / Lean     |
| Left trigger     | Z                     | Secondary action   |
| Right trigger    | X                     | Primary action     |

When the user asks to play a specific game, check if a keymap exists in the keymaps directory. If one exists, pass it. If not, use the defaults — they work for most games.

## 5. How to Stop

Call `nitrogen_stop`. This will:

- Terminate both `serve_mac.py` and `play_mac.py`
- Release all currently pressed keys
- Clean up the ZMQ connection

**Always stop NitroGen before:**
- Switching to a different game
- Switching platforms
- The user closing the game manually

## 6. Status Monitoring

Call `nitrogen_status` to check the current state of NitroGen. The response includes:

| Field            | Type   | Description                                      |
|------------------|--------|--------------------------------------------------|
| `isRunning`      | Bool   | Whether the capture/inject loop is active        |
| `fps`            | Float  | Current capture/inference frames per second       |
| `stepCount`      | Int    | Total frames processed since start               |
| `serverHealthy`  | Bool   | Whether the inference server is responding on ZMQ |

Use this to answer "how's the game going?" questions and to detect if NitroGen has stalled.

## 7. Frame Observation

Call `nitrogen_screenshot` to capture the current game frame as seen by NitroGen. Use this to:

- **Verify the game loaded correctly** before starting NitroGen
- **Check if the agent is stuck** (e.g., stuck on a menu, death screen, or loading screen)
- **Report what's happening** to the user when they ask

Do not call `nitrogen_screenshot` repeatedly — once per user question is sufficient.

## 8. Platform Navigation

### Web platforms (Xbox Cloud Gaming, GeForce NOW, Amazon Luna, Boosteroid)

These platforms run in a browser or webview. Use the web navigation tools:

1. `gaming_search_game` — search for a game by name on the current platform
2. `gaming_screenshot_web` — capture the current page state to see what's on screen
3. `gaming_click_element` — click UI elements (play buttons, game tiles, menus)
4. `gaming_type_text` — type into search boxes or text fields

**Flow:**
1. Take a screenshot to see the current page state
2. Search for the game
3. Click the game tile in search results
4. Click the "Play" button
5. Wait for the stream to connect and the game to load
6. Verify with `nitrogen_screenshot`, then start NitroGen

### Native platforms (Steam Link, PlayStation Remote Play)

- **Steam Link**: Games launch from Steam's Big Picture mode. Use `gaming_click_element` if the app has accessible UI elements, otherwise guide the user to navigate manually.
- **PlayStation Remote Play**: Guide the user to select their game from the PlayStation home screen.

For native apps, the primary job is to detect when the game window is ready, then start NitroGen.

## 9. Conversational Flow Example

**User**: "Play Celeste"

**Agent**:
1. Check the current platform — if none is selected, ask the user which platform to use
2. If it's a web platform → `gaming_search_game("Celeste")` → `gaming_screenshot_web` to verify results → `gaming_click_element` on the play button
3. Wait for the game to load → `nitrogen_screenshot` to verify the game window is rendering
4. `nitrogen_start(windowTitle: "Celeste", keymap: "keymaps/celeste.json")`
5. Report: "Celeste is running! NitroGen is playing at 30fps. I'll keep an eye on it."

---

**User**: "How's it going?"

**Agent**:
1. `nitrogen_status` → check FPS and step count
2. `nitrogen_screenshot` → observe the current frame
3. Report: "NitroGen has processed 4,200 frames at 28fps. Looks like Madeline is in Chapter 2 — she's wall-jumping through the dream blocks."

---

**User**: "Stop playing"

**Agent**:
1. `nitrogen_stop`
2. Report: "NitroGen stopped. Celeste is still open if you want to play manually."

## 10. Safety Rules

1. **Never start NitroGen without a visible game window.** Always verify with `nitrogen_status` or `nitrogen_screenshot` first.
2. **Always call `nitrogen_stop` before the user switches platforms or games.** Leaving it running against a stale window wastes resources and can inject inputs into the wrong app.
3. **The user can override the agent at any time.** If they say "stop", stop immediately — no confirmation needed.
4. **Don't spam `nitrogen_screenshot`.** One capture per user question is enough. Excessive captures waste bandwidth and slow down inference.
5. **Respect the keymap.** If a game uses unusual controls that the default keymap doesn't cover well, suggest creating a custom keymap JSON rather than fighting the defaults.
6. **Don't start multiple NitroGen instances.** Only one game can be played at a time. Stop the current session before starting a new one.
