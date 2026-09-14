# Thumbwheel Remapper

Thumbwheel Remapper is a native macOS menu-bar utility that remaps mouse
gestures through a Quartz event tap. It has no third-party runtime
dependencies and targets macOS Tahoe 26 or newer.

The default configuration is intentionally small:

- horizontal thumbwheel movement becomes vertical scrolling;
- Back (`other` button 3) single-clicks scroll down;
- Forward (`other` button 4) single-clicks scroll up;
- double-click and hold mappings are available, but disabled by default.

See [PRODUCT.md](PRODUCT.md) for the architecture and product decisions.

## Requirements

- macOS Tahoe 26 or newer;
- Swift command-line tools (`swift`, `swiftc`) for source builds;
- a mouse that exposes compatible Quartz events;
- Accessibility permission for the installed app.

## Build, install, and run

The signed app-bundle workflow is unchanged:

```sh
make setup-signing
make install
open "$HOME/Applications/Thumbwheel Remapper.app"
```

`make setup-signing` creates a local **Thumbwheel Remapper Local Signing**
certificate in the login keychain. Reusing it keeps macOS Accessibility
permission attached to the app across rebuilds. The certificate is for
personal builds, not distribution.

To build without installing:

```sh
make app
open "build/Thumbwheel Remapper.app"
```

The bundle script builds the Swift Package Manager executable target, copies
it into the existing bundle layout, generates the app icon, and signs the
bundle. To install somewhere else:

```sh
INSTALL_DIR=/Applications make install
```

The first launch may ask to open **System Settings > Privacy & Security >
Accessibility**. Enable **Thumbwheel Remapper**, then launch it again. Older
macOS releases use **System Preferences > Security & Privacy > Privacy >
Accessibility**.

## Architecture

The package has three targets:

```text
ThumbwheelRemapperCore       Foundation-only library
ThumbwheelRemapper            SwiftUI/AppKit/ApplicationServices executable
ThumbwheelRemapperCoreTests   Focused deterministic unit tests
```

The core owns the versioned Codable configuration document, mapping models,
validation, gesture timing, animation and momentum engines, joystick math,
wheel transforms, Quartz-shaped event normalization, and routing decisions.
The executable uses the SwiftUI app lifecycle for its `MenuBarExtra`,
scene-managed mappings window, native sidebar, toolbar, and forms. AppKit and
ApplicationServices remain responsible for the event tap lifecycle, timers,
synthetic scroll output, cursor lock/hide, joystick HUD, and page-distance
lookup.

The persisted document is stored as JSON data under the new key
`ThumbwheelRemapper.Configuration.v1`. There is no migration from the
previous scalar preference keys. Missing, malformed, unsupported, invalid, or
failed writes are logged; the explicit default document is used when needed.

## Mapping manager

Choose **Mappings…** from the status-item menu. The native preferences window
supports:

- a list of click, hold, and wheel mappings;
- add, remove, and contextual edit actions;
- independent single and double click mappings;
- hold mappings with direction, speed, acceleration, release, and joystick
  options;
- button capture for other mouse buttons only. The primary left and right
  buttons are intentionally not remappable because intercepting them can
  interfere with normal macOS interaction;
- disabled button choices that are already used by the selected gesture;
- inline duplicate and parameter validation;
- immediate save, **Restore Defaults**, and help text.

Changes are persisted as soon as they are valid. Invalid edits remain visible
for correction and are never activated.

### Gesture timing

If a button has no double-click mapping, its single mapping fires immediately;
it is not delayed by the system double-click interval. If a double mapping is
present, the first press waits for `NSEvent.doubleClickInterval` so a second
press can be recognized. Hold mappings use an independent hold delay and can
coexist with single or double mappings.

### Wheel behavior

By default, only pure horizontal, non-continuous wheel events are transformed.
The horizontal deltas are copied to the vertical axis, including integer,
fixed-point, and point representations; horizontal fields are cleared. Shift
scrolling and diagonal/vertical events remain native. The input-shape and
continuous filters are part of the wheel action options.

### Scroll engines

Discrete click animations are deterministic and sampleable. Hold scrolling is
display-paced, can use joystick speed control, and releases into deterministic
momentum. Joystick displacement starts at zero for both one-dimensional and
two-dimensional pointer math, preventing a cursor-lock jump.

The event router consumes only mapped gestures. Unmapped left, right, other,
pointer, wheel, and unrelated events are forwarded. Event-tap timeout and
user-input re-enable handling is isolated from routing.

## Development checks

Run the focused core tests:

```sh
swift test --filter ThumbwheelRemapperCoreTests
```

Build the signed bundle:

```sh
./scripts/build-app.sh
```

The test suite covers defaults, duplicate validation, persistence failures,
gesture timing, routing and tap re-enable, wheel shape/continuous filtering,
discrete animation, joystick zero-start math, continuous scrolling, and
momentum.

## Troubleshooting

- **Could not create the event tap:** grant Accessibility permission to the
  installed app and restart it. Quit competing input-remapping utilities if
  the permission is already enabled.
- **Thumbwheel does nothing:** confirm that a horizontal thumbwheel mapping is
  present. If the device reports continuous events, edit its wheel action or
  disable the continuous-event filter.
- **Buttons still navigate:** verify that the device reports
  `otherMouseDown`/`otherMouseUp` and capture the button again. Connection
  modes can expose different Quartz button numbers.
- **Scrolling is backwards:** edit the mapping direction in **Mappings…**.
- **Keyboard shortcut assignments do nothing:** keyboard triggers are
  deliberately deferred; see the follow-up issue for that scope.

## Launch at login

For a personal installation, add **Thumbwheel Remapper** to **System Settings
> General > Login Items**. This keeps Accessibility permission tied to the
installed app bundle.

## Optional launchd LaunchAgent

If a launchd entry is preferred, create
`~/Library/LaunchAgents/com.example.thumbwheel-remapper.plist` with paths
adjusted for the account:

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
  <string>/Users/you/Library/Logs/thumbwheel-remapper.log</string>
  <key>StandardErrorPath</key>
  <string>/Users/you/Library/Logs/thumbwheel-remapper.err</string>
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
