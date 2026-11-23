# Haptic Cursor v3.0.1 — developer preview

- Adds a multi-resolution illustrated app icon.
- Supports profiles for different Accessibility roles, bulk actions, saved settings, and Level 1 default.
- Haptics emit a single snap per control entry (no multiple-tick repetition).
- Standard public AppKit feedback plus optional private actuator waveforms for Levels 1–4, in a separate helper.
- Fixes a reported startup crash on macOS 27.3 by moving AX hit-testing onto the main thread and excluding the app's own window.

**Release status:** Full macOS compilation and hardware regression testing have not been performed in the publishing environment. The crash fix addresses the reported trace but needs validation. This is a source distribution, **not a prebuilt notarized application**. Users build locally using the supplied `install.sh`.
