#!/bin/bash
# UserPromptExpansion Hook - Log skill/command names for status line display.
# Fires when user types a slash command (e.g. /effort, /brainstorming).
# Appends skill name to log file for statusline to read.

LOG_FILE="/tmp/cc-skills.log"
MAX_LINES=50

# Read stdin (contains the expanded prompt/command info)
input=$(cat)

# Extract command name from the input
# UserPromptExpansion receives the expanded content; try to extract the command name
cmd=$(echo "$input" | grep -o '<command-name>[^<]*</command-name>' 2>/dev/null \
  | sed 's/<[^>]*>//g; s|^/||' || true)

# Fallback: if no command-name tag, check for /command pattern
if [ -z "$cmd" ]; then
  cmd=$(printf '%s' "$input" | sed -n 's|^/\([^ ]*\).*|\1|p' 2>/dev/null || true)
fi

if [ -n "$cmd" ]; then
  echo "$cmd" >> "$LOG_FILE"

  # Trim log
  if [ -f "$LOG_FILE" ]; then
    lines=$(wc -l < "$LOG_FILE")
    if [ "$lines" -gt "$MAX_LINES" ]; then
      tail -"$MAX_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
  fi
fi
