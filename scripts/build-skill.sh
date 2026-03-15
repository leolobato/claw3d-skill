#!/usr/bin/env bash
# Build the unified claw3d skill from modules.
# Run from claw3d-skill/ directory.
#
# Usage:
#   ./scripts/build-skill.sh [--modules ai-forger,directory,slicing,printing]
#   CLAW3D_MODULES=ai-forger,printing ./scripts/build-skill.sh
#
# Default: all modules if CLAW3D_MODULES not set and no --modules.
set -euo pipefail

# jq is required for manifest parsing — fail fast if missing
if ! command -v jq &>/dev/null; then
  echo "Error: jq is required but not installed. Install it with: brew install jq (macOS) or apt-get install jq (Linux)" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAW3D_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SRC_DIR="$CLAW3D_ROOT/src"
OUT_FILE="$CLAW3D_ROOT/SKILL.md"

# Parse --modules
MODULES_ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --modules)
      MODULES_ARG="${2:-}"
      shift 2
      ;;
    *)
      echo "Error: Unknown option: $1" >&2
      echo "Usage: $0 [--modules ai-forger,directory,slicing,printing]" >&2
      exit 1
      ;;
  esac
done

# Module selection: env > arg > default all
MODULES_STR="${CLAW3D_MODULES:-${MODULES_ARG:-ai-forger,directory,slicing,printing,mesh-repair}}"
IFS=',' read -ra MODULES_ARR <<< "$MODULES_STR"

# Validate modules against manifest
MANIFEST="$CLAW3D_ROOT/manifest.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "Error: manifest.json not found at $MANIFEST" >&2
  exit 1
fi

# Build requires JSON for OpenClaw metadata
# Collect env vars from selected modules
REQUIRES_ENV=()
for mod in "${MODULES_ARR[@]}"; do
  mod="${mod// /}"
  [[ -z "$mod" ]] && continue
  # Security: validate module names contain only lowercase alphanumeric and hyphens
  if [[ ! "$mod" =~ ^[a-z0-9-]+$ ]]; then
    echo "Error: invalid module name '$mod' — must match [a-z0-9-]+" >&2
    exit 1
  fi
  envs=$(jq -r --arg m "$mod" '.modules[$m].requires_env[]? // empty' "$MANIFEST") || {
    echo "Error: Failed to parse manifest.json for module '$mod'" >&2
    exit 1
  }
  for e in $envs; do
    [[ -n "$e" ]] && REQUIRES_ENV+=("$e")
  done
done

# Determine primaryEnv based on selected modules
PRIMARY_ENV=""
for mod in "${MODULES_ARR[@]}"; do
  mod="${mod// /}"
  if [[ "$mod" == "ai-forger" ]]; then
    PRIMARY_ENV="FAL_API_KEY"
    break
  fi
done
# Fallback: use the first required env var if ai-forger not selected
if [[ -z "$PRIMARY_ENV" && ${#REQUIRES_ENV[@]} -gt 0 ]]; then
  PRIMARY_ENV="${REQUIRES_ENV[0]}"
fi

# Deduplicate and build requires JSON
# Format: { "anyBins": ["claw3d"], "env": ["FAL_API_KEY", ...] }
if [[ ${#REQUIRES_ENV[@]} -gt 0 ]]; then
  ENV_JSON=$(printf '%s\n' "${REQUIRES_ENV[@]}" | sort -u | jq -R . | jq -s -c '.')
  REQUIRES_JSON=$(jq -c -n --argjson env "$ENV_JSON" '{ "anyBins": ["claw3d"], "env": $env }')
else
  REQUIRES_JSON='{ "anyBins": ["claw3d"] }'
fi

# Build frontmatter
FRONTMATTER="$SRC_DIR/00-frontmatter.md"
if [[ ! -f "$FRONTMATTER" ]]; then
  echo "Error: 00-frontmatter.md not found" >&2
  exit 1
fi

# Create temp file for assembled skill
TMP_OUT=$(mktemp)
trap 'rm -f "$TMP_OUT"' EXIT

# 1. Frontmatter with requires and primaryEnv injected (awk avoids sed special-char issues)
awk -v req="$REQUIRES_JSON" -v env="$PRIMARY_ENV" '{ gsub(/\{\{REQUIRES_JSON\}\}/, req); gsub(/\{\{PRIMARY_ENV\}\}/, env); print }' "$FRONTMATTER" > "$TMP_OUT"

# 2. Core (always included)
echo "" >> "$TMP_OUT"
cat "$SRC_DIR/01-core.md" >> "$TMP_OUT"

# 3. Intent, video handling, and analysis (always included)
for intent_mod in 06-intent-routing.md 07-video-handling.md 08-analysis.md; do
  if [[ -f "$SRC_DIR/$intent_mod" ]]; then
    echo "" >> "$TMP_OUT"
    echo "---" >> "$TMP_OUT"
    echo "" >> "$TMP_OUT"
    cat "$SRC_DIR/$intent_mod" >> "$TMP_OUT"
  fi
done

# 4. Selected modules in order
MODULE_ORDER=(ai-forger directory slicing printing mesh-repair)
for mod in "${MODULE_ORDER[@]}"; do
  for sel in "${MODULES_ARR[@]}"; do
    sel="${sel// /}"
    [[ -z "$sel" ]] && continue
    if [[ "$sel" == "$mod" ]]; then
      mod_rel=$(jq -r --arg m "$mod" '.modules[$m].file // empty' "$MANIFEST")
      mod_file="$CLAW3D_ROOT/$mod_rel"
      # Security: verify module path stays within project root (prevents path traversal via manifest.json)
      if [[ -n "$mod_rel" ]] && [[ "$(realpath "$mod_file" 2>/dev/null)" != "$CLAW3D_ROOT"/* ]]; then
        echo "Error: module '$mod' path escapes project root: $mod_rel" >&2
        exit 1
      fi
      if [[ -n "$mod_rel" && -f "$mod_file" ]]; then
        echo "" >> "$TMP_OUT"
        echo "---" >> "$TMP_OUT"
        echo "" >> "$TMP_OUT"
        cat "$mod_file" >> "$TMP_OUT"
      fi
      break
    fi
  done
done

# Write output
mv "$TMP_OUT" "$OUT_FILE"
trap - EXIT

echo "Built $OUT_FILE with modules: ${MODULES_ARR[*]}"
