## overoclock

A tiny always‑on‑top clock for macOS. It shows a minimal black pill with the current time and turns red when any app in the Dock has an unread badge (e.g., WhatsApp, Mail, Messages, Slack, Telegram). This is useful when you’re in full‑screen apps or on a second monitor and want a subtle attention indicator.

**Key points**
- Floating panel stays above full‑screen spaces.
- Menu bar item for quick controls.
- Background turns red when any Dock item has a non‑empty badge.
- Adjustable: 24‑hour format, seconds on/off, font size, background opacity.
- Optional click‑through mode (clock ignores mouse clicks).
- Remembers position or can be pinned to the top‑right.
- Diagnostics menu to check Accessibility status and dump Dock items.


## Requirements
- macOS 15 (Sequoia) or newer.
- Accessibility permission (required to read Dock badges via AX API).


## How It Works
The app periodically inspects the Dock’s Accessibility (AX) hierarchy and looks for Dock items with a non‑empty `AXStatusLabel` (the badge). If any are found, the clock’s background turns red. A small ignore‑list avoids false positives (Trash, Downloads, Launchpad, App Store, System Settings).

Notes:
- Only apps that set a Dock badge are detected. Banner‑only notifications without a Dock badge are not counted.
- The app must be granted Accessibility permission to access the Dock’s AX tree.


## Build & Install
You can build with Xcode and copy the app to `/Applications`.

- In Xcode: Product → Scheme → Edit Scheme… → Run → set Build configuration to `Release` (or use Product → Build For → Profiling).
- Product → Build.
- In the Products group, right‑click `overoclock.app` → Show in Finder.
- Copy `overoclock.app` to `/Applications`.

First launch on this Mac:
- System Settings → Privacy & Security → Accessibility → add `/Applications/overoclock.app` and enable it.
- If needed, use the app’s Diagnostics → “Open Accessibility Settings…” menu to jump there.


## Usage
- The clock appears as a small floating pill. Drag to move (unless pinned). Use the menu bar icon to:
  - Toggle 24‑hour time and seconds.
  - Change font size and background opacity.
  - Enable click‑through (ignores mouse clicks over the clock).
  - Pin to top‑right (auto‑positions across screens/spaces).
  - Open Diagnostics (AX status, Dock dump, force refresh).


## Troubleshooting
- Clock doesn’t turn red:
  - Check Accessibility permission for `overoclock.app` (Diagnostics → “Check Accessibility Access”).
  - The app you expect must place a badge on its Dock icon and be present in the Dock.
  - Use Diagnostics → “Show Dock items in console” to verify `title=… badge=…` entries.
- Permission prompts repeat or don’t stick:
  - Remove any previous entries for `overoclock` in Accessibility, then re‑add the currently installed app (Debug and Release builds live in different paths).


## Development Notes
- The app uses Accessibility APIs (AX) to read Dock badges; it does not use private APIs.
- For convenience, this project’s Debug and Release entitlements are configured without App Sandbox, to ensure AX access during development and local use. If you plan to distribute the app publicly (e.g., via notarized downloads or the Mac App Store), revisit entitlements and code signing to match your distribution target.


## Roadmap (ideas)
- User‑editable include/ignore lists for Dock titles.
- Custom attention colors and thresholds (e.g., only if badge ≥ N).
- Optional sound or subtle pulse when attention starts.

