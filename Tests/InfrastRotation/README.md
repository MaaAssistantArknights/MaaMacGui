# Rotation checks without Xcode

Run `bash Tests/InfrastRotation/run.sh` on macOS with Swift Command Line Tools.

- Uses the production rotation model, JSON decoder and configuration encoder.
- Checks old configuration defaults, property-list persistence and exclusion of GUI metadata from Core parameters.
- Compiles the real settings view with minimal surrounding type shims.
- Extracts the exact production submission and completion handlers, executes them against a fake Core, and checks success, failure, stop, duplicate events, file edits, manual overrides and profile isolation.
- `fixtures.json` contains portable numeric cases for Windows tests; times are relative to a supplied completion instant.

The shims are test-only. These checks do not build the full MAA target, its dependencies or the real callback dispatcher. Full Xcode build, actual application persistence/relaunch, and real game validation remain required before release. Windows integration is not implemented here.
