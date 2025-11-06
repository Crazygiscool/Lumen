#!/usr/bin/env bash
# tree.sh - Print folder structure with ignore support, .gitignore awareness,
#           and detailed file info output to a file.

# Usage:
#   ./tree.sh [root_dir] [output_file] [ignore_patterns...]
# Example:
#   ./tree.sh . tree.txt "node_modules" "dist"

ROOT="${1:-.}"
OUTFILE="${2:-tree.txt}"
shift 2
USER_IGNORES=("$@")

# Build ignore args for 'find'
IGNORE_ARGS=()
for pat in "${USER_IGNORES[@]}"; do
  IGNORE_ARGS+=(-path "$ROOT/$pat" -prune -o)
done

# Always ignore .git folders
IGNORE_ARGS+=(-path "$ROOT/.git" -prune -o)

# If .gitignore exists, parse it into ignore args
if [[ -f "$ROOT/.gitignore" ]]; then
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    IGNORE_ARGS+=(-path "$ROOT/$line" -prune -o)
  done < "$ROOT/.gitignore"
fi

# Collect all files and directories with detailed info
# Format: permissions, owner, group, size, date, path
{
  echo "Folder structure for: $ROOT"
  echo "Generated on: $(date)"
  echo "========================================="
  find "$ROOT" "${IGNORE_ARGS[@]}" -print \
    | while read -r f; do
        stat --printf "%A %U %G %s %y %n\n" "$f" 2>/dev/null
      done \
    | sed -e "s|[^/]*/|   |g" -e "s|/|- |"
} > "$OUTFILE"

echo "Tree written to $OUTFILE"
