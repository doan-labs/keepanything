#!/bin/bash
# Read-only KeepAnything inspection. Never writes a library, never prints .env or config.json.
#
# Usage: ka.sh ps
#        ka.sh path   [dev|e2e|prod]
#        ka.sh db     [dev|e2e|prod] <sql or .dot-command>...
#        ka.sh log    [dev|e2e|prod] [lines=50] [min-level=warn]   (stacks cut to 5 lines)
#        ka.sh health [dev|e2e|prod]
#
# Profile defaults to dev. prod is the user's real library and needs KA_PROD=1.
set -euo pipefail

REPO="$(cd "$(dirname "$0")/../../../.." && pwd)"
cmd="${1:-}"
shift || true

profile_dir() {
  local support="$HOME/Library/Application Support/KeepAnything"
  case "$1" in
    prod) echo "$support" ;;
    dev) echo "$support/dev" ;;
    e2e) echo "${TMPDIR%/}/keepanything-e2e" ;;
  esac
}

profile=dev
case "${1:-}" in dev | e2e | prod)
  profile=$1
  shift
  ;;
esac
if [[ "$cmd" != ps && "$profile" == prod && "${KA_PROD:-}" != 1 ]]; then
  echo "prod is the user's real library: ask first, then rerun with KA_PROD=1" >&2
  exit 2
fi
dir="$(profile_dir "$profile")"
db="$dir/library.db"

sql() {
  [[ -f "$db" ]] || {
    echo "no library at $db" >&2
    exit 1
  }
  if [[ -e "$db-shm" ]]; then
    sqlite3 -readonly "$db" "$@"
  else
    # App closed: a read-only WAL open needs the -shm file, so open immutable instead.
    # ponytail: only spaces are URI-escaped; a profile path with % ? or # would need full encoding.
    sqlite3 "file:${db// /%20}?immutable=1" "$@"
  fi
}

case "$cmd" in
  ps)
    ports() { lsof -a -p "$1" -iTCP -sTCP:LISTEN -P -n -Fn 2>/dev/null | sed -n 's/^n.*:\([0-9]*\)$/\1/p' | sort -u | tr '\n' ' ' || true; }
    # Main processes only (helpers are "Electron Helper ..."): dev/e2e are an Electron started from this repo.
    found=
    for pid in $(pgrep -x 'Electron|KeepAnything' || true); do
      cwd=$(lsof -a -p "$pid" -d cwd -Fn 2>/dev/null | sed -n 's/^n//p' || true)
      if [[ "$(ps -o comm= -p "$pid" || true)" == *Electron && "$cwd" != "$REPO" ]]; then continue; fi
      found=1
      open=$(lsof -p "$pid" -Fn 2>/dev/null | sed -n 's/^n\(.*\)\/library\.db$/\1/p' | head -1 || true)
      open=${open#/private} # lsof resolves /var/folders (the e2e profile) to /private/var/folders
      name=unknown
      for p in dev e2e prod; do if [[ "$open" == "$(profile_dir "$p")" ]]; then name=$p; fi; done
      listening=$(ports "$pid")
      echo "pid=$pid profile=$name${listening:+ listening=${listening% }}"
    done
    [[ -n "$found" ]] || echo "no KeepAnything instance running"
    for pid in $(pgrep -f "$REPO/node_modules/.bin/electron-vite dev" || true); do
      listening=$(ports "$pid")
      echo "electron-vite pid=$pid${listening:+ renderer-port=${listening% }}"
    done
    ;;
  path)
    echo "$dir"
    ;;
  db)
    [[ $# -gt 0 ]] || {
      echo "usage: ka.sh db [profile] <sql>..." >&2
      exit 2
    }
    sql -json "$@"
    ;;
  log)
    file="$dir/logs/keepanything.log"
    [[ -f "$file" ]] || {
      echo "no log at $file" >&2
      exit 1
    }
    jq -cR --arg min "${2:-warn}" '
      {debug: 10, info: 20, warn: 30, error: 40} as $rank
      | fromjson? | select(($rank[.level] // 0) >= $rank[$min])
      | if (.error | type) == "object" and (.error.stack | type) == "string"
        then .error.stack |= (split("\n")[:5] | join("\n")) else . end' "$file" | tail -n "${1:-50}"
    ;;
  health)
    sql -header -column \
      ".print '== items by status (trash excluded)'" \
      "select processing_status, count(*) n from items where deleted_at is null group by 1 order by n desc;" \
      ".print '== open jobs'" \
      "select stage, lane, status, count(*) n, min(created_at) oldest from jobs where status in ('queued','running') group by 1,2,3;" \
      ".print '== failed jobs (latest 10)'" \
      "select item_id, stage, attempts, updated_at, substr(last_error,1,160) error from jobs where status='failed' order by updated_at desc limit 10;" \
      ".print '== items with errors (latest 10)'" \
      "select id, processing_status, substr(title,1,40) title, substr(processing_error,1,160) error from items where processing_error is not null and deleted_at is null order by modified_at desc limit 10;" \
      ".print '== failed agent runs (latest 10)'" \
      "select id, task, started_at, substr(error,1,160) error from agent_runs where status='failed' order by started_at desc limit 10;"
    ;;
  *)
    sed -n '4,10p' "$0" | sed 's/^# \{0,1\}//' >&2
    exit 2
    ;;
esac
