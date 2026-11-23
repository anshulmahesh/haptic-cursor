#!/bin/bash
# Publish the prepared public repository using GitHub CLI. Run manually after reading the code.
set -euo pipefail
cd "$(dirname "$0")"
for cmd in gh git; do command -v "$cmd" >/dev/null || { echo "ERROR: $cmd required." >&2; exit 1; }; done
if ! gh auth status >/dev/null 2>&1; then
  echo 'Sign in first: gh auth login --web --clipboard'  >&2
  exit 1
fi
OWNER="$(gh api user -q .login)"
REPO="${1:-haptic-cursor}"
if [[ ! "$REPO" =~ ^[a-zA-Z0-9_.-]+$ ]]; then echo 'ERROR: Invalid repository name' >&2; exit 1; fi
if gh repo view "$OWNER/$REPO" >/dev/null 2>&1; then
  echo "ERROR: $OWNER/$REPO already exists. No files were overwritten." >&2
  exit 1
fi
if [[ -d .git ]] && [[ -n "$(git remote 2>/dev/null)" ]]; then
  echo 'ERROR: Existing git remote found. Refusing to publish unexpectedly.' >&2
  exit 1
fi
read -r -p "Publish PUBLIC repository $OWNER/$REPO and create v3.0.1 release? [y/N] " answer
[[ "$answer" == 'y' || "$answer" == 'Y' ]] || { echo 'Cancelled.'; exit 0; }
if [[ ! -d .git ]]; then git init -b main; fi
git add .
if ! git diff --cached --quiet; then
  git -c user.name="$(git config user.name || echo 'Haptic Cursor')" -c user.email="$(git config user.email || echo "${OWNER}@users.noreply.github.com")" commit -m "Publish Haptic Cursor v3.0.1" >/dev/null
fi
gh repo create "$OWNER/$REPO" --public --source=. --remote=origin --push   --description 'Haptic Cursor: customizable macOS Accessibility-aware trackpad haptics'
echo "Repository created: https://github.com/$OWNER/$REPO"
# Pages uses GitHub Actions, not the legacy branch publishing mode.
if gh api -X POST "repos/$OWNER/$REPO/pages" -f build_type=workflow >/dev/null 2>&1; then
  echo 'GitHub Pages enabled using Actions.'
else
  echo 'NOTICE: GitHub Pages API could not enable the site. Open Settings > Pages and choose GitHub Actions.'
fi
if gh release create v3.0.1 docs/downloads/MenuMagnetHapticProfiles-v3.0.1.zip   --repo "$OWNER/$REPO" --title 'v3.0.1 — Developer preview'   --notes-file RELEASE_NOTES.md; then
  echo 'Created downloadable GitHub Release.'
else
  echo 'NOTICE: Release creation failed; source ZIP is still available from the Pages website and repository.'
fi
if gh workflow run pages.yml --repo "$OWNER/$REPO"; then
  echo 'Pages deployment requested.'
else
  echo 'NOTICE: Workflow could not be triggered. Check Actions and Settings > Pages.'
fi
printf '
GitHub repository: https://github.com/%s/%s
' "$OWNER" "$REPO"
printf 'Expected Pages URL after deployment: https://%s.github.io/%s/
' "$OWNER" "$REPO"
printf 'Release URL (if created): https://github.com/%s/%s/releases/tag/v3.0.1
' "$OWNER" "$REPO"
