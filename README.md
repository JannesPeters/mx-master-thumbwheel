# MX Master thumbwheel remapper

This small macOS command-line utility uses a Quartz `CGEvent` tap to customize
the Logitech MX Master:

- The thumbwheel's pure horizontal scroll becomes vertical scroll.
- The Forward thumb button produces one vertical scroll-up event per click.
- The Back thumb button produces one vertical scroll-down event per click.

It runs in the foreground, is not a GUI app, and has no third-party runtime
dependencies.

## Requirements

- macOS 10.13 or newer
- Swift command-line tools (`swiftc`)
- A Logitech MX Master, or another device that emits compatible events
- Accessibility permission for the executable or the terminal that launches it

## Build and run

From this directory:

```sh
swiftc main.swift -o thumbwheel-remapper
./thumbwheel-remapper
```

The process must remain running for remapping to be active. Stop it with
Control-C.

The executable needs Accessibility permission because the event tap observes,
changes, suppresses, and synthesizes system-wide input events. On macOS Ventura
and newer, open **System Settings > Privacy & Security > Accessibility**. On
older macOS versions, use **System Preferences > Security & Privacy > Privacy >
Accessibility**. Enable the terminal application or `thumbwheel-remapper` (use
the `+` button if it is not listed), then run the command again. Permission
changes may require restarting the terminal or the utility.

## Behavior

- Only pure horizontal thumbwheel events (axis 2 with no axis 1 movement) are
  remapped. Vertical, diagonal, and unrelated scroll events are unchanged.
- Integer, fixed-point, and point delta fields are transferred so the original
  thumbwheel scroll representation is retained.
- Holding Shift bypasses thumbwheel remapping, preserving native horizontal
  scrolling.
- Forward and Back `otherMouseDown` events are suppressed and replaced by one
  line-based vertical scroll event. Matching `otherMouseUp` events are also
  suppressed, but never generate another scroll.
- The event tap automatically re-enables itself after macOS disables it because
  of a timeout or user-input request.

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
generates exactly one scroll event on button-down only.

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

## Optional launchd LaunchAgent

To start the utility when you log in, build it at a stable path and create
`~/Library/LaunchAgents/com.example.thumbwheel-remapper.plist` with the paths
adjusted for your account:

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
    <string>/Users/you/bin/thumbwheel-remapper</string>
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
