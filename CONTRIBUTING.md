# Contributing to Haptic Cursor

Contributions and bug reports are welcome. Reproduce on macOS when possible.

When filing an issue, please include:

- Version and macOS build
- Mac model and internal or external trackpad
- Haptic mode (Standard / Enhanced) and selected pattern/level
- Exact control type or Accessibility role (for example `AXScrollBar`)
- Expected and actual behaviour
- If relevant, a short crash stack (redact filenames, paths, names and personal details)

This project uses Swift/AppKit/SwiftUI and a small C process for **optional private API experimentation**. No code change should synthesize cursor movements or click UI elements. Keep feedback to one request per entry. Avoid introducing crashes from Accessibility calls on worker threads; macOS 27.3 hit-testing can re-enter SwiftUI's main actor.

## Development

- Run the two Foundation-only Swift tests from the README.
- Build on a Mac using the local installer script. Note: it removes known older apps after a successful build.
- Work on a branch and submit a pull request with a concise explanation and tests.
- Update website copy if any feature or limitation changes.

Code is available under the MIT License. Do not commit Apple private frameworks, code signing certificates, personal crash reports, or third-party copyrighted assets without permission.
