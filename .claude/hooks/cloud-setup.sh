#!/bin/bash
# Cloud sessions only: install the Electron project's JS deps without downloading the Electron binary.
[ "${CLAUDE_CODE_REMOTE:-}" = "true" ] || exit 0
cd "$CLAUDE_PROJECT_DIR"
dir=electron; [ -f electron/package.json ] || dir=.
(cd "$dir" && ELECTRON_SKIP_BINARY_DOWNLOAD=1 pnpm install --frozen-lockfile >/dev/null 2>&1) || echo "cloud-setup: pnpm install failed in $dir" >&2
exit 0
