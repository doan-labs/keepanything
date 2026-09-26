#!/usr/bin/env bash
# Runs the verification gates from docs/swift_rewrite/features.json.
#
#   scripts/gate.sh linux    baseline (swift build/test when Package.swift exists, electron typecheck+test)
#                            plus the gate of every passing feature with runs_on=linux
#   scripts/gate.sh macos    full swift test, electron build, plus the gate of every passing
#                            non-human feature
#   scripts/gate.sh lint     import rules from PLAN.md#modules
#   scripts/gate.sh <id>     the gate of one feature, passing or not
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FEATURES="$ROOT/docs/swift_rewrite/features.json"
cd "$ROOT"

log() { printf '\n==> %s\n' "$*"; }

run_gate() {
  local id="$1" gate="$2"
  [ -n "$gate" ] || return 0
  log "gate $id: $gate"
  (cd "$ROOT" && bash -eo pipefail -c "$gate")
}

# Prints "id<TAB>gate" for features matching a filter: passing | all, and a runs_on list.
features() {
  local mode="$1" runs_on="$2"
  node -e '
    const [mode, runsOn] = process.argv.slice(1);
    const allowed = new Set(runsOn.split(","));
    const list = JSON.parse(require("fs").readFileSync(process.env.FEATURES, "utf8"));
    for (const f of list) {
      if (!allowed.has(f.runs_on)) continue;
      if (mode === "passing" && f.passes !== true) continue;
      if (!f.gate) continue;
      process.stdout.write(`${f.id}\t${f.gate}\n`);
    }
  ' "$mode" "$runs_on"
}

run_passing() {
  local runs_on="$1"
  while IFS=$'\t' read -r id gate; do
    run_gate "$id" "$gate"
  done < <(FEATURES="$FEATURES" features passing "$runs_on")
}

lint() {
  log "lint: import rules"
  local bad=0
  if [ -d Sources ]; then
    # Only KAUI may import SwiftUI; no module imports AppKit.
    if grep -rln --include='*.swift' -E '^\s*import (SwiftUI|AppKit)' Sources | grep -v '^Sources/KAUI/' | grep -q .; then
      echo "import rule: SwiftUI/AppKit outside Sources/KAUI:" >&2
      grep -rln --include='*.swift' -E '^\s*import (SwiftUI|AppKit)' Sources | grep -v '^Sources/KAUI/' >&2
      bad=1
    fi
    if grep -rln --include='*.swift' -E '^\s*import AppKit' Sources | grep -q .; then
      echo "import rule: AppKit is App/-only:" >&2
      grep -rln --include='*.swift' -E '^\s*import AppKit' Sources >&2
      bad=1
    fi
    # No module reads the environment, UserDefaults or the Keychain; App/ passes values in.
    if grep -rn --include='*.swift' -E 'ProcessInfo\.processInfo\.environment|UserDefaults\.|SecItem(Add|CopyMatching|Update|Delete)\(' Sources | grep -q .; then
      echo "import rule: environment/UserDefaults/Keychain access inside Sources/:" >&2
      grep -rn --include='*.swift' -E 'ProcessInfo\.processInfo\.environment|UserDefaults\.|SecItem(Add|CopyMatching|Update|Delete)\(' Sources >&2
      bad=1
    fi
    # KALibrary must not depend on UI: no `import KAUI` outside Sources/KAUI and App/.
    if grep -rln --include='*.swift' -E '^\s*import KAUI' Sources | grep -v '^Sources/KAUI/' | grep -q .; then
      echo "import rule: KAUI imported outside Sources/KAUI (and App/):" >&2
      grep -rln --include='*.swift' -E '^\s*import KAUI' Sources | grep -v '^Sources/KAUI/' >&2
      bad=1
    fi
    # Apple-only frameworks must sit behind `#if canImport(<Framework>)`.
    apple_fws='PDFKit|WebKit|QuickLookThumbnailing|AppKit|CoreServices'
    for f in $(grep -rln --include='*.swift' -E "^\s*import ($apple_fws)" Sources || true); do
      if ! grep -q '#if canImport(' "$f"; then
        echo "import rule: Apple framework imported without a canImport guard:" >&2
        echo "$f" >&2
        bad=1
      fi
    done
  fi
  if [ -d electron/src ]; then
    # Electron testability rule: nothing under these folders imports electron or reads process.env.
    local dirs="core capture extraction retrieval agent pipeline storage ai"
    for d in $dirs; do
      [ -d "electron/src/main/$d" ] || continue
      hits="$(grep -rn --include='*.ts' -E "from 'electron'|process\.env" "electron/src/main/$d" | grep -vE '^[^:]+:[0-9]+:\s*(\*|//)' | grep -v 'storage/paths.ts' || true)"
      if [ -n "$hits" ]; then
        echo "electron rule: electron import or process.env under src/main/$d:" >&2
        echo "$hits" >&2
        bad=1
      fi
    done
  fi
  [ "$bad" -eq 0 ] || return 1
  echo "lint ok"
}

electron_baseline() {
  log "electron: typecheck + test"
  (cd electron && pnpm run typecheck && pnpm run test)
}

swift_baseline() {
  [ -f Package.swift ] || { echo "no Package.swift yet, skipping swift"; return 0; }
  log "swift build"
  swift build
  log "swift test"
  swift test
}

case "${1:-}" in
  linux)
    swift_baseline
    electron_baseline
    run_passing linux
    ;;
  macos)
    swift_baseline
    electron_baseline
    log "electron: build"
    (cd electron && pnpm run build)
    run_passing linux,macos
    ;;
  lint)
    lint
    ;;
  "")
    sed -n '2,10p' "$0"
    exit 2
    ;;
  *)
    line="$(FEATURES="$FEATURES" features all linux,macos,human | awk -F'\t' -v id="$1" '$1 == id')"
    [ -n "$line" ] || { echo "unknown feature id: $1" >&2; exit 2; }
    run_gate "$1" "${line#*$'\t'}"
    ;;
esac
