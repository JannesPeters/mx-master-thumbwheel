# Thumbwheel Remapper

This small native macOS utility uses a Quartz `CGEvent` tap to customize the
Logitech MX Master:

- The thumbwheel's pure horizontal scroll becomes vertical scroll.
- The Forward thumb button produces repeated vertical scroll-up events while
  held down (a single event on a quick click).
- The Back thumb button produces repeated vertical scroll-down events while
  held down (a single event on a quick click).

It runs as a menu-bar (status item) app, so it has a small native UI for
changing scroll-repeat settings; it has no third-party runtime dependencies.

## Requirements

- macOS 10.13 or newer
- Swift command-line tools (`swiftc`) for building from source
- A Logitech MX Master, or another device that emits compatible events
- Accessibility permission for Thumbwheel Remapper

## Build, install, and run

The recommended workflow is to build an installable app bundle:

From this directory:

```sh
make setup-signing
make install
open "$HOME/Applications/Thumbwheel Remapper.app"
```

`make setup-signing` is a one-time step that creates a local code-signing
certificate in your login keychain. Reusing this identity prevents macOS from
treating every rebuild as a different app and forgetting its Accessibility
permission. The certificate is valid only on your Mac and is intended for
personal builds, not distribution.

This installs the app in `~/Applications`, so no administrator password is
needed. To install it in `/Applications`, use:

```sh
INSTALL_DIR=/Applications make install
```

The app runs in the background with a ⇕ menu-bar icon. Use its **Quit** item to
stop remapping. To build without installing:

```sh
make app
open "build/Thumbwheel Remapper.app"
```

The build script uses the local **Thumbwheel Remapper Local Signing**
certificate. Apps intended for distribution to other Macs should instead be
signed with a Developer ID certificate and notarized by Apple.

The app needs Accessibility permission because the event tap observes, changes,
suppresses, and synthesizes system-wide input events. On first launch, it offers
to open **System Settings > Privacy & Security > Accessibility**. Enable
**Thumbwheel Remapper**, then launch the app again. On older macOS versions, use
**System Preferences > Security & Privacy > Privacy > Accessibility**.

## Behavior

- Only pure horizontal thumbwheel events (axis 2 with no axis 1 movement) are
  remapped. Vertical, diagonal, and unrelated scroll events are unchanged.
- Integer, fixed-point, and point delta fields are transferred so the original
  thumbwheel scroll representation is retained.
- Holding Shift bypasses thumbwheel remapping, preserving native horizontal
  scrolling.
- Forward and Back `otherMouseDown` events are suppressed and replaced by a
  line-based vertical scroll event that repeats every "repeat interval"
  seconds (after an initial "repeat delay") for as long as the button stays
  down. Matching `otherMouseUp` events are also suppressed and stop the
  repeat; releasing a different button than the one held has no effect.
- The event tap automatically re-enables itself after macOS disables it because
  of a timeout or user-input request.

## Menu-bar settings UI

The app shows a ⇕ icon in the menu bar while it runs. Its menu has:

- **Preferences…** — opens a small window with two sliders:
  - **Repeat delay before scrolling starts** (0.05–2.00 s, default 0.30 s):
    how long a thumb button must be held before repeating begins.
  - **Repeat interval (scroll speed)** (0.01–0.50 s, default 0.05 s): how often
    a scroll event repeats while the button is held; smaller is faster.
  - **Restore Defaults** resets both sliders to the defaults above.
  - Changes apply immediately (read on the next button press) and are saved
    right away — there is no separate "Save" step. **Done** just closes the
    window.
- **Quit** — exits the app.

Both values are persisted via `UserDefaults` (the standard macOS preferences
mechanism) so they are restored the next time the app launches, and are
clamped to the ranges above no matter how they were set, so a stale or
corrupted preference value can never produce a zero, negative, or unreasonably
large repeat rate.

## Configuration

Edit the constants at the top of `main.swift` and rebuild:

- `verticalScrollDirection = 1` keeps the thumbwheel direction; change it to
  `-1` if the resulting vertical scrolling is inverted.
- `requireLineBasedScrollEvents = true` ignores continuous, pixel-based
  scrolling so trackpad horizontal gestures are less likely to be remapped. If
  macOS reports the MX thumbwheel as continuous, change this to `false`. That
  fallback may also remap other continuous horizontal gestures.
- `backButtonNumber = 3` and `forwardButtonNumber = 4` are the default Quartz
  button numbers for MX Master Back and Forward. These numbers are zero-based:
  left is 0, right is 1, and middle is 2. Change the two constants if the
  connected device or connection mode reports different numbers. Keep them
  distinct.

The button mapping applies to `otherMouseDown` and `otherMouseUp` events. It
generates a scroll event on button-down and then repeats at the configured
delay/interval (see "Menu-bar settings UI" above) for as long as the button is
held, stopping on the matching button-up.

## Troubleshooting and caveats

- **`Could not create the event tap`:** grant Accessibility permission to the
  terminal or executable, then restart the process.
- **Thumbwheel does nothing:** confirm the process is still running and rebuild
  after changing a configuration constant. Try setting
  `requireLineBasedScrollEvents` to `false` if the thumbwheel is reported as
  continuous.
- **Thumb buttons still navigate:** verify that the buttons arrive as
  `otherMouseDown`/`otherMouseUp` events and that
  `backButtonNumber`/`forwardButtonNumber` match the values reported by that
  device and connection mode. USB, Bluetooth, Logitech Unifying, and Logitech
  Bolt connections can expose different button numbers.
- **The button numbers are not visible to this utility:** temporarily inspect
  the mouse events with an event-monitoring tool, or use the button-number
  conventions reported by your remapping utility, then update the constants
  and rebuild.
- **Logi Options+ assigned a keyboard shortcut:** the buttons may arrive as
  keyboard events instead of mouse events. This utility intentionally handles
  mouse button events only; assign the buttons as native mouse buttons if
  possible.
- **Scrolling is backwards:** set `verticalScrollDirection` to `-1` and
  rebuild.
- **Horizontal scrolling no longer works with Shift:** verify that the
  thumbwheel event reaches macOS as a scroll-wheel event and that another input
  utility is not intercepting it.

macOS does not expose a universal device identifier in this event tap, so the
continuous-scroll filter is only a heuristic for distinguishing the physical
thumbwheel from trackpad gestures. The button-number configuration is likewise
device/connection dependent.

## Launch at login

For a personal installation, add **Thumbwheel Remapper** to
**System Settings > General > Login Items**. This is preferable to a
`launchd` entry because macOS keeps the app's Accessibility permission tied to
the installed app bundle.

## Optional launchd LaunchAgent

If you prefer a `launchd` configuration, create
`~/Library/LaunchAgents/com.example.thumbwheel-remapper.plist` with the paths
adjusted for your account and point it at the installed app executable:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>com.example.thumbwheel-remapper</string>
  <key>ProgramArguments</key>
  <array>
    <string>/Users/you/Applications/Thumbwheel Remapper.app/Contents/MacOS/ThumbwheelRemapper</string>
  </array>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>/tmp/thumbwheel-remapper.log</string>
  <key>StandardErrorPath</key>
  <string>/tmp/thumbwheel-remapper.err</string>
</dict>
</plist>
```

Load it with:

```sh
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.thumbwheel-remapper.plist
```

Remove it with:

```sh
launchctl bootout gui/$(id -u)/com.example.thumbwheel-remapper
```
