# base-gui — ComputerCraft Create mod monitoring system

## Overview
Central PC receives telemetry from Create mod structures (fluid tanks, item silos, steam boilers, stressometers, barrel changers) via wireless rednet and renders a real-time ASCII dashboard on an advanced monitor (`textScale(0.5)` = 51×19). Includes interactive detail views for tanks, silos, and barrel flow events.

## File Structure

| File | Purpose |
|------|---------|
| `startup.lua` | Central PC — all rendering, touch handling, data normalization, main loop |
| `tank_sender.lua` | Fluid tank sender (reads Target Block, broadcasts, listens for tank_config) |
| `engine_sender.lua` | Steam boiler sender |
| `stress_sender.lua` | Stressometer sender |
| `silo_sender.lua` | Item silo sender (reads drawer controller) |
| `barrel_sniffer.lua` | Barrel change detector (sends barrel_flow events) |
| `update.lua` | Force-overwrite updater (`fs.delete` + `wget`) |
| `sniff.lua` | Byte-level Target Block reader for debugging |
| `ccdebug.lua` | CCCBridge test suite |
| `debug.lua` | General peripheral scanner |
| `dev-server.js` | Node.js HTTP dev server (port 8000) |

## Architecture

```
[senders] --rednet--> [central PC] --monitor--> [advanced monitor 51×19]
```

- **Protocols**: `tank_data`, `item_data`, `steam_data`, `stress_data`, `barrel_flow`, `tank_config`
- **Timer**: 0.1s for animation + re-render
- **Senders broadcast every ~3s**; central PC stores latest data in tables
- **Tank sender** additionally listens for `tank_config` (blocks + fluidColor changes from UI)

## Screen Layout (main view)

```
x=1  x=2..11   x=12..15  x=16..30     x=34..50    x=51
+--- storage --- gap --- boiler --- tank visual ---+
|                     (steam)                       |
|                       ...                         |
+--- stress (y=15..17) ----- barrel flow (y=13..17) +
|                       status bar (y=19)           |
```

**y=1**: Top border (title)
**y=2..18**: Content area (cleared every frame)
**y=19**: Status line (connection counters)

## Palette / Color Conventions

| Constant | CC Color | Purpose |
|----------|----------|---------|
| BG_EMPTY | `colors.black` | Default background |
| BG_FILL | `colors.magenta` | Tank fluid fill (default gold #9b8149 via palette, animated) |
| BG_STORAGE_FILL | `colors.purple` | Silo storage fill (#485b6e) |
| BG_BAR | `colors.blue` | Misc bars (#34414e) |
| BG_BTN | `colors.orange` | All buttons in detail views (#C8641E) |
| STRESS_GOLD | `colors.lime` | Stress gauge track (#ebbd64) |
| TANK_BORDER | `colors.brown` | Tank border (#9f5c44) |
| WHITE | `colors.white` | Primary text |
| GRAY | `colors.gray` | Secondary text |
| LIGHT_GRAY | `colors.lightGray` | Info text |
| Burner bg | `colors.pink` | Boiler burner bg (#475a6d) |
| Boiler border | `colors.cyan` | Boiler border (#3f2014) |

### Boiler colors (palette-reassigned):
- `colors.blue` → #34414e (reused as BG_BAR)
- `colors.purple` → #485b6e (reused as BG_STORAGE_FILL)
- `colors.magenta` → #9b8149 (tank fill, stable — no more per-frame palette animation)
- `colors.brown` → #9f5c44 (tank border)
- `colors.orange` → #C8641E (buttons, boiler fill, fire text)
- `colors.lime` → #ebbd64 (stress gold)
- `colors.cyan` → #3f2014 (boiler border)
- `colors.yellow` → dynamic (burner heat gradient — NOT suitable for tank fill)
- `colors.green` → #1e501e (stable dark green, was dynamic fire; fire now uses `##` text in orange/brown)
- `colors.pink` → #475a6d (burner bg)

## Key Functions

- **renderContent()** (line 1134): Main render dispatcher. Checks detail view (selectedSiloId/selectedTankId), then clears area and draws boiler → tanks → storage → stress → barrel flow → status. Called from timer (0.1s) and every rednet_message.
- **drawTank(x, y, name, amount, capacity, fluidColor)** (line 173): Draws one tank with bordered ASCII visual, animated partial fill (BG_FILL only). Returns next y.
- **drawTankDetail(info)** (line 915): Full-screen tank detail with large left visual + right panel (back, colors, footprint, height).
- **drawSiloDetail(info)** (line 738): Full-screen silo detail with storage grid.
- **renderStress()** (line 664): Animated stress gauge at bottom-left with oscillating shaft.
- **drawFrame()** (line 82): Draws the permanent outer border (called once at startup).
- **normalize(info)** (line 456): Normalizes incoming tank data to `{label, id, tanks[...]}` format.

## Fluid Color Swatches

15 standard CC colors are available as tank fluid color choices (defined in `COLOR_SWATCHES`, line 53):

| Row | Swatches |
|-----|----------|
| y=10 | magenta (Gold), brown (Brown), orange (Orange), lime (Lime) |
| y=11 | blue (Dark blue), purple (Slate blue), red (Red), lightBlue (Aqua) |
| y=12 | pink (Slate), gray (Gray), lightGray (Light gray), white (White) |
| y=13 | green (Dark green, stable #1e501e), cyan (Dark brown #3f2014), black (Black) |

**Note**: `colors.yellow` is excluded — it's dynamically palette-reassigned each frame by the burner heat animation and would cause flickering if used for tank fill.

## Tank Detail View Details

- LX=2, L_W=24, L_INNER=22, L_ROWS=12 (left panel)
- RX=27 (right panel start)
- BACK_BTN_Y=2, TANK_COLOR_Y=10, TANK_FOOT_Y=13, TANK_HEIGHT_Y=14
- 11 color swatches (3 rows), footprint presets [1x1][2x2][3x3], height [-][+]
- Orange buttons (BG_BTN = colors.orange)
- `tank_config` protocol: sends `{blocks=N, foot=F, height=H, fluidColor=const}` to sender

## Tank Config Persistence

The tank footprint/height/color is stored on the TANK SENDER computer (`tank_sender.lua`):

- **File**: `.tank_config` on the tank computer (serialized Lua table)
- **Saved**: every time `tank_config` is received from the central PC
- **Loaded**: on sender startup (overrides hardcoded defaults)
- **Broadcast**: included in every `tank_data` message as `blocks`, `foot`, `height`, `fluidColor`

The central PC initializes its local `tankFootprint`, `tankHeight`, `tankFluidColor` from the first incoming message after restart (line 1295-1302). Once set locally, sender broadcasts don't override — only the user's UI actions update local state. This means after the first message, the central PC always wins, even if the sender restarts with different values.

**tank_config message**: `{ blocks = N, foot = F, height = H, fluidColor = color_const }`
- All 4 fields are sent by the central PC UI on every config change
- The sender saves all 4 to `.tank_config` and includes them in broadcasts

## Critial Rendering Order (main view)
The draw order in renderContent is FIXED:
1. Clear screen (y=2..h-1)
2. Draw steam boiler (center)
3. Draw fluid tanks (right)
4. Draw storage silos (left)
5. Draw stress gauge (bottom-left, y=15..17)
6. Draw barrel flow box (bottom-right, y=13..17)
7. Draw status line (y=19)

Barrel flow at bottom-right ALWAYS covers the bottom portion of the tank visual. This is intentional.

## Tank Animation (blit gradient)

The partial-fill row (top of liquid) uses `monitor.blit()` for a per-character color gradient instead of palette manipulation. Each character position in the fill row gets its own background color index, transitioning from `BG_FILL` (gold #9b8149, index 2) toward white (index 0) across the fill width. The transition depth oscillates with `math.sin(os.clock() * 2)`.

- `colorIdx(bitFlag)` converts CC bit-flag constants (e.g., `colors.magenta=4`) to 0..15 blit indices
- Non-BG_FILL colors do NOT animate (solid fill only)
- `monitor.blit(text, fgColors, bgColors)` — text = spaces, fg = white, bg = gradient string
- Used in both `drawTank` (line 214) and `drawTankDetail` (line 990)

## Touch Zones

- **Silo (x=2..11)**: Click label area → opens silo detail
- **Tank (x=34..50)**: Click label area → opens tank detail
- **Silo/Tank detail**: Back button at y=2 (x=27..37 for silo, TANK_BTN_BACK_X1..X2 for tank)
- **Tank color**: y=TANK_COLOR_Y..TANK_COLOR_Y+2 (swatch zone)
- **Tank footprint**: y=TANK_FOOT_Y (preset buttons)
- **Tank height**: y=TANK_HEIGHT_Y (+/- buttons)

## Barrel Flow Display

- Right side of stress gauge, at x=30..51, y=13..17 (5 rows)
- 3 content rows with white background, text only when events exist
- Events expire after 2 seconds (pruned in render pass)
- White background ALWAYS drawn (even when no events) — prevents black "holes"
- Left margin at column 29 (avoids overlap with stress gauge percentage/text)

## Common Pitfalls

- `monitor.setBackgroundColor()` and `monitor.setTextColor()` MUST be reset after use (usually to BG_EMPTY / WHITE)
- Barrel flow section must ALWAYS reset text color — it sets `colors.orange` on entry
- do NOT use `goto` or certain Lua 5.3+ features (CC-Tweaked compatibility)
- Bar bytes: 167=█ (1.0), 127=▓ (0.5), 21=░ (0.0) — but ASCII fallback is preferred
- `monitor.setPaletteColor` is SLOW and affects the ENTIRE monitor — must reset immediately
