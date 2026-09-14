# Thumbwheel Remapper product architecture

## Product intent

Thumbwheel Remapper is a small, native, menu-bar macOS utility for turning
device-specific mouse gestures into deterministic scroll actions. It observes
only the Quartz events needed by the configured mappings, consumes mapped
gestures, and forwards everything else unchanged.

The product deliberately starts with a narrow, reliable input surface:

- a horizontal thumbwheel becomes vertical scroll;
- the MX Master Back button single-clicks down;
- the MX Master Forward button single-clicks up;
- double-click and hold mappings are available but disabled by default;
- keyboard keys and shortcuts are deferred until a later input-trigger issue.

## Architecture

### `ThumbwheelRemapperCore`

`ThumbwheelRemapperCore` is a Foundation-only Swift package target. It has no
AppKit, Quartz, or Accessibility dependencies, so configuration and gesture
behavior can be tested without a running GUI or event tap.

The core owns:

- Codable, Equatable, Identifiable mapping models:
  `ButtonClickMapping`, `ButtonHoldMapping`, and `WheelMapping`;
- action option models for discrete, continuous, and wheel actions;
- explicit default mappings and duplicate/parameter validation;
- a versioned JSON configuration document and a new UserDefaults storage key;
- deterministic click/double/hold timing;
- discrete animation, continuous scrolling, drag momentum, and joystick math;
- normalized button/wheel events, source-shape filtering, transforms, routing,
  and isolated event-tap re-enable decisions.

The persisted document is `ConfigurationDocument` version `1` at
`ThumbwheelRemapper.Configuration.v1`. There is intentionally no migration
from the pre-package scalar UserDefaults keys. Missing, malformed,
unsupported, invalid, or unwritable documents are logged and replaced with
the explicit defaults.

### `ThumbwheelRemapper`

The executable target contains the macOS platform layer:

- a session Quartz event tap and run-loop lifecycle;
- AppKit cursor association, cursor hiding, and the joystick HUD;
- display/accessibility page-distance lookup;
- timers for gesture deadlines, animation frames, hold scrolling, and momentum;
- synthetic pixel scroll events;
- a status item and native mapping manager preferences window.

The preferences window edits the core document directly. It provides a
mapping list, add/remove actions, contextual editing, button capture, disabled
already-used choices, inline validation, immediate persistence, Restore
Defaults, and help text. Invalid documents stay visible for correction but are
never written or activated.

## Input behavior

Button gestures are independent per button:

- if no double mapping exists, a single mapping is not held for
  `NSEvent.doubleClickInterval`;
- if a double mapping exists, the first press waits only that interval so a
  second press can become a double;
- a hold mapping uses its own hold delay and acceleration/release settings;
- click, double-click, and hold mappings can coexist on one button;
- duplicate entries for the same button/gesture are rejected.

The wheel detector requires a horizontal-only event by default and ignores
continuous trackpad-style events. Shift remains native. The router consumes a
button or wheel event only when an active mapping matches it. Tap timeout and
user-input disable callbacks are handled separately and re-enable the tap
without changing routing decisions.

Joystick displacement is zero-start: the first pointer sample establishes the
anchor and produces no jump. Both 1D and 2D math are available in the core.
Hold release uses deterministic momentum decay, while discrete clicks use a
sampleable easing curve.

## Build and compatibility

The package declares macOS 10.13 as its minimum platform. The signed app
bundle workflow remains `scripts/build-app.sh`; it now builds the executable
target with Swift Package Manager before copying it into the existing bundle
layout, generating the icon, and signing the result.

```sh
swift test --filter ThumbwheelRemapperCoreTests
make app
```

The app still uses the local `Thumbwheel Remapper Local Signing` identity.
`make setup-signing` creates it once, and `make install` preserves the
existing user-local installation workflow.

## Deferred scope

Keyboard key and shortcut triggers are intentionally not part of this
architecture yet. They require a separate trigger model, keyboard event
normalization, shortcut capture/accessibility behavior, and conflict rules.
The follow-up GitHub issue tracks that work rather than silently treating
keyboard events as mouse mappings.
