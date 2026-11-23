# Security and privacy

Haptic Cursor uses macOS Accessibility permission to inspect control roles and boundaries. This code does not intentionally send usage telemetry to a server. The website is static and performs demo interactions locally in the browser.

The native app uses no synthetic mouse or click events. Experimental Enhanced Mode loads an undocumented Apple private framework from the operating system in a separate helper process and can break across system updates. The installer uses ad-hoc signing, which is not Apple notarization.

Do not post private filenames, full usernames, or personal data when publishing diagnostics. Review the install script before running it: after successful build, it replaces recognised older Menu Magnet apps and may request administrator approval when cleaning `/Applications`. The installer attempts targeted `tccutil reset` for old bundle IDs.

If you discover a security issue, do not post exploit details in a public issue. Contact the repository owner through a private channel if available.
