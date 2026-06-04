#!/bin/bash
# PreToolUse Hook - Track Claude-initiated Skill invocations.
# Fires ONLY when Claude calls the Skill tool (not user-typed /slash).
# Reads JSON from stdin, extracts skill name, appends to log.

LOG_FILE="/tmp/cc-skills.log"
MAX_LINES=50

input=$(cat)

# Extract skill name from tool_input
skill=$(echo "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null || true)

if [ -n "$skill" ]; then
  echo "$skill" >> "$LOG_FILE"

  # Trim log
  if [ -f "$LOG_FILE" ]; then
    lines=$(wc -l < "$LOG_FILE")
    if [ "$lines" -gt "$MAX_LINES" ]; then
      tail -"$MAX_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
  fi
fi
