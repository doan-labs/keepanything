#!/bin/bash
# Runs biome check --write on the file Claude just edited/wrote.
# Receives PostToolUse JSON on stdin.

FILE_PATH=$(cat | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{process.stdout.write(JSON.stringify((JSON.parse(d)?.tool_input?.file_path)||''))}catch{}})" | tr -d '"')

if [ -z "$FILE_PATH" ]; then
  exit 0
fi

# The Electron project (and biome.json) lives under electron/; anything else is not biome's business.
case "$FILE_PATH" in
  "$CLAUDE_PROJECT_DIR"/electron/*) ;;
  *) exit 0 ;;
esac

cd "$CLAUDE_PROJECT_DIR/electron" || exit 0

pnpm exec biome check --write --files-ignore-unknown=true --no-errors-on-unmatched "$FILE_PATH" 2>/dev/null

exit 0  # Never block Claude — we're formatting, not gating
