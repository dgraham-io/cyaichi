#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

CYAI_FORCE="${CYAI_FORCE:-0}"
CYAI_DRY_RUN="${CYAI_DRY_RUN:-0}"
CYAI_DB_PATH_VALUE="${CYAI_DB_PATH:-}"

DELETED_COUNT=0
NOT_FOUND_COUNT=0
SKIPPED_COUNT=0

log() {
  printf '%s\n' "$*"
}

warn() {
  printf 'warning: %s\n' "$*" >&2
}

is_suspicious_path() {
  local target="$1"

  if [[ -z "$target" || "$target" == "/" || "$target" == "." || "$target" == ".." ]]; then
    return 0
  fi

  if [[ "${#target}" -lt 6 ]]; then
    return 0
  fi

  return 1
}

safe_remove() {
  local target="$1"
  local label="$2"

  if [[ -z "$target" ]]; then
    warn "empty path for ${label}; skipping"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    return
  fi

  if [[ ! -e "$target" ]]; then
    log "not found: $target"
    NOT_FOUND_COUNT=$((NOT_FOUND_COUNT + 1))
    return
  fi

  local abs
  abs="$(cd "$(dirname "$target")" && pwd)/$(basename "$target")"

  if is_suspicious_path "$abs"; then
    warn "refusing to delete suspicious path: $abs ($label)"
    SKIPPED_COUNT=$((SKIPPED_COUNT + 1))
    return
  fi

  if [[ "$CYAI_DRY_RUN" == "1" ]]; then
    log "dry-run: would delete $abs"
    return
  fi

  log "deleting: $abs"
  rm -rf -- "$abs"
  DELETED_COUNT=$((DELETED_COUNT + 1))
}

append_db_variants() {
  local db_file="$1"
  DB_TARGETS+=("$db_file" "${db_file}-wal" "${db_file}-shm")
}

path_points_to_tmp_cyaichi_db() {
  local value="$1"
  case "$value" in
    "/tmp/cyaichi.db"|"/private/tmp/cyaichi.db")
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

detect_macos_bundle_id() {
  local pbxproj="$REPO_ROOT/client/macos/Runner.xcodeproj/project.pbxproj"
  if [[ ! -f "$pbxproj" ]]; then
    return
  fi

  local bundle_id
  bundle_id="$(sed -n 's/.*PRODUCT_BUNDLE_IDENTIFIER = \([^;]*\);/\1/p' "$pbxproj" | head -n1 | tr -d '[:space:]')"
  if [[ -n "$bundle_id" ]]; then
    printf '%s' "$bundle_id"
  fi
}

collect_macos_matches() {
  local pattern="$1"
  local -a matches=()
  while IFS= read -r line; do
    matches+=("$line")
  done < <(compgen -G "$pattern" || true)
  for p in "${matches[@]-}"; do
    if [[ -z "$p" ]]; then
      continue
    fi
    MAC_TARGETS+=("$p")
  done
}

log "cyaichi dev reset"
log "repo root: $REPO_ROOT"

if [[ "$CYAI_FORCE" != "1" ]]; then
  printf 'This will delete local cyaichi data. Continue? (y/N) '
  read -r answer
  if [[ "$answer" != "y" && "$answer" != "Y" ]]; then
    log "aborted"
    exit 0
  fi
fi

if [[ "$CYAI_DRY_RUN" == "1" ]]; then
  log "dry-run mode enabled (no files will be deleted)"
fi

DB_TARGETS=()
if [[ -n "$CYAI_DB_PATH_VALUE" ]]; then
  append_db_variants "$CYAI_DB_PATH_VALUE"
fi
append_db_variants "$REPO_ROOT/server/.local/cyaichi.db"

if [[ -z "$CYAI_DB_PATH_VALUE" || $(path_points_to_tmp_cyaichi_db "$CYAI_DB_PATH_VALUE" && echo yes || echo no) == "yes" ]]; then
  append_db_variants "/tmp/cyaichi.db"
fi

log ""
log "[server/db targets]"
for target in "${DB_TARGETS[@]}"; do
  safe_remove "$target" "db"
done

SERVER_DIR_TARGETS=(
  "$REPO_ROOT/server/.local/workspace-data"
  "$REPO_ROOT/server/workspace-data"
  "$REPO_ROOT/workspace-data"
)

log ""
log "[server workspace-data targets]"
for target in "${SERVER_DIR_TARGETS[@]}"; do
  safe_remove "$target" "workspace-data"
done

MAC_TARGETS=()
if [[ "$(uname -s)" == "Darwin" ]]; then
  bundle_id="$(detect_macos_bundle_id || true)"
  if [[ -n "$bundle_id" ]]; then
    collect_macos_matches "$HOME/Library/Preferences/${bundle_id}*"
    collect_macos_matches "$HOME/Library/Application Support/${bundle_id}*"
    collect_macos_matches "$HOME/Library/Caches/${bundle_id}*"
  fi

  collect_macos_matches "$HOME/Library/Preferences/*cyaichi*"
  collect_macos_matches "$HOME/Library/Application Support/*cyaichi*"
  collect_macos_matches "$HOME/Library/Caches/*cyaichi*"

  if [[ ${#MAC_TARGETS[@]} -gt 0 ]]; then
    log ""
    log "[macOS client config/cache targets]"
    declare -A SEEN=()
    for target in "${MAC_TARGETS[@]}"; do
      if [[ -n "${SEEN[$target]:-}" ]]; then
        continue
      fi
      SEEN[$target]=1
      safe_remove "$target" "macOS client cache"
    done
  else
    log ""
    log "[macOS client config/cache targets]"
    log "not found: no matching client cache/config paths"
  fi
fi

log ""
if [[ "$CYAI_DRY_RUN" == "1" ]]; then
  log "dry-run complete"
else
  log "reset complete"
fi
log "deleted: $DELETED_COUNT"
log "not found: $NOT_FOUND_COUNT"
log "skipped: $SKIPPED_COUNT"
