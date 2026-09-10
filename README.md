# Thumbwheel Remapper

This small native macOS utility uses a Quartz `CGEvent` tap to customize the
Logitech MX Master:

- The thumbwheel's pure horizontal scroll becomes vertical scroll.
- The Forward thumb button produces repeated vertical scroll-up events while
  held down (a single event on a quick click).
- The Back thumb button produces repeated vertical scroll-down events while
  held down (a single event on a quick click).

It runs as a menu-bar (status item) app, with a native settings window for
configuring each remapping behavior; it has no third-party runtime
dependencies.

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
  vertical pixel scroll. Releasing before the long-press delay runs the
  independently configured single-click animation. Holding beyond the delay
  starts continuous display-paced scrolling without first adding a click
  jump. Long-press speed and easing are configured separately. Matching
  `otherMouseUp` events are also suppressed; releasing a different button than
  the one held has no effect.
- The event tap automatically re-enables itself after macOS disables it because
  of a timeout or user-input request.

## Menu-bar settings UI

The app shows a mouse-shaped icon with its side thumbwheel highlighted in the
menu bar and as its app icon. Its menu has:

- **Preferences…** — opens a settings window with:
  - **Remapping** under **Thumbwheel** — turns horizontal-to-vertical
    thumbwheel conversion on or off without quitting the app.
  - **Vertical direction** — keeps or reverses the thumbwheel's resulting
    vertical scroll direction.
  - **Input filtering** — keeps pixel-based trackpad gestures from being
    mistaken for the mouse's thumbwheel. Turn it off if a particular
    mouse/connection reports its thumbwheel as continuous.
  - **Remapping** under **Thumb buttons** — independently turns thumb-button
    scrolling on or off.
  - **Back button** and **Forward button** — choose the zero-based Quartz
    button numbers used by the connected mouse. The two values must be
    different.
  - **Single click** has independent distance, easing, and animation-duration
    controls. Distance ranges from 5–1,000 pt (default 40 pt), and duration
    from 0.05–1.00 s (default 0.18 s). Its easing reaches scrolling speed
    quickly, then uses most of the duration to decelerate smoothly.
  - **Press and hold** has independent start-delay, speed, and easing controls.
    **Time to full speed** controls acceleration, while **Glide after release**
    controls deceleration. Both range from 0.05–1.00 s.
  - **Joystick mode** is enabled by default and makes press-and-hold speed
    respond to mouse movement while locking and hiding the pointer. The
    configured speed is neutral; moving in the active scroll direction
    accelerates up to 3×, while moving against it enters a broad paused zone
    before reversing up to 2×. A small HUD shows the active direction, paused
    zone, and speed.
  - **Middle button** can optionally activate joystick mode immediately from
    its paused center. Moving up scrolls in one direction and moving down
    scrolls in the other; releasing the wheel button exits joystick mode. When
    enabled, the app consumes the middle click instead of passing it through.
  - **Restore Defaults** resets every setting.
  - Behavior toggles apply immediately; button assignments and repeat timing
    apply on the next button press. Everything is saved right away, with no
    separate Save step.
- **Quit** — exits the app.

All values are persisted via `UserDefaults` (the standard macOS preferences
mechanism) so they are restored the next time the app launches. Numeric values
are clamped to safe ranges, and invalid duplicate button assignments are
rejected.

## Configuration

Use **Preferences…** from the menu-bar icon to change the remapping direction,
continuous-event filtering, Back/Forward button numbers, repeat timing, or to
temporarily disable either remapping behavior.

The button mapping applies to `otherMouseDown` and `otherMouseUp` events. It
generates a scroll event on button-down and then repeats at the configured
delay/interval (see "Menu-bar settings UI" above) for as long as the button is
held, stopping on the matching button-up.

## Troubleshooting and caveats

- **`Could not create the event tap`:** grant Accessibility permission to the
  terminal or executable, then restart the process.
- **Thumbwheel does nothing:** confirm the process is still running and that
  thumbwheel remapping is enabled. Turn off **Input filtering** if the
  thumbwheel is reported as continuous.
- **Thumb buttons still navigate:** verify that the buttons arrive as
  `otherMouseDown`/`otherMouseUp` events and that
  the configured Back/Forward button numbers match the values reported by that
  device and connection mode. USB, Bluetooth, Logitech Unifying, and Logitech
  Bolt connections can expose different button numbers.
- **The button numbers are not visible to this utility:** temporarily inspect
  the mouse events with an event-monitoring tool, or use the button-number
  conventions reported by your remapping utility, then update the values in
  **Preferences…**.
- **Logi Options+ assigned a keyboard shortcut:** the buttons may arrive as
  keyboard events instead of mouse events. This utility intentionally handles
  mouse button events only; assign the buttons as native mouse buttons if
  possible.
- **Scrolling is backwards:** choose **Reverse scroll direction** in
  **Preferences…**.
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
