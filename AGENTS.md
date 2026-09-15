# Agent instructions

## App versioning and installation

Follow the **Updating an existing installation** section in `README.md` when
preparing an app update.

- Update both version keys in `Resources/Info.plist`:
  - `CFBundleShortVersionString` is the user-facing release version.
  - `CFBundleVersion` is an integer build number and must increase.
- Before replacing the installed bundle, check whether Thumbwheel Remapper is
  running. Stop only the exact process ID for the intended app bundle; do not
  use name-based process termination.
- Run `make install`, which installs to
  `~/Applications/Thumbwheel Remapper.app` by default.
- Relaunch that exact bundle after installation.
- Verify the installed `Info.plist` version and confirm the running executable
  comes from the same bundle before reporting success.
- Be aware that `/Applications/Thumbwheel Remapper.app` may be a separate,
  older installation. Do not launch or replace it unless the requested install
  target is explicitly `/Applications`.

An update is not complete while an older executable remains loaded in memory.
