# MX Master thumbwheel remapper

This small macOS command-line utility converts Logitech MX Master thumbwheel
scrolling from horizontal to vertical scrolling. It installs a Quartz
`CGEvent` tap and runs in the foreground; it is not a GUI app and has no
third-party runtime dependencies.

## Requirements

- macOS 10.13 or newer
- Swift command-line tools (`swiftc`)
- A Logitech MX Master (or another device that emits horizontal scroll-wheel
  events)
- Accessibility permission for the executable

## Build and run

From this directory:

```sh
swiftc main.swift -o thumbwheel-remapper
./thumbwheel-remapper
```

The process must remain running for remapping to be active. Stop it with
Control-C.

The executable needs Accessibility permission because it observes and changes
system-wide input events. On macOS Ventura and newer, open **System Settings >
Privacy & Security > Accessibility**. On older macOS versions, use **System
Preferences > Security & Privacy > Privacy > Accessibility**. Enable the
terminal application or `thumbwheel-remapper` (use the `+` button if it is not
listed), then run the command again. Permission changes may require restarting
the terminal or the utility.

## Configuration

Edit the constants at the top of `main.swift` and rebuild:

- `verticalScrollDirection = 1` keeps the event direction; change it to `-1`
  if the resulting vertical scrolling is inverted.
- `requireLineBasedScrollEvents = true` ignores continuous, pixel-based
  scrolling so trackpad horizontal gestures are less likely to be remapped.
  If macOS reports the MX thumbwheel as continuous, change this to `false`.
  That fallback may also remap other continuous horizontal gestures.

Holding Shift bypasses the remapping and preserves native horizontal scrolling.
Only pure horizontal events (axis 2 with no axis 1 movement) are changed.
Integer, fixed-point, and point delta fields are transferred so the original
scroll representation is retained.

## Troubleshooting

- **`Could not create the event tap`:** grant Accessibility permission to the
  terminal or executable, then restart the process.
- **Nothing changes:** confirm the process is still running and rebuild after
  changing a configuration constant. Try setting
  `requireLineBasedScrollEvents` to `false` if the thumbwheel is reported as
  continuous.
- **Scrolling is backwards:** set `verticalScrollDirection` to `-1` and
  rebuild.
- **Horizontal scrolling no longer works with Shift:** verify that the
  thumbwheel event reaches macOS as a scroll-wheel event and that another input
  utility is not intercepting it.

The event tap automatically re-enables itself after macOS disables it because
of a timeout or user-input request.

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
