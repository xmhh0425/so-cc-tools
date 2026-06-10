#!/bin/bash
# PreToolUse Hook (matcher: Skill) - Log skill name when Claude invokes a Skill tool.
# Stdin is JSON: {"tool_name":"Skill","tool_input":{"skill":"skill-name"},...}

LOG_FILE="/tmp/cc-skills.log"
MAX_LINES=50

input=$(cat)

# Extract skill name from PreToolUse JSON input
cmd=$(echo "$input" | jq -r '.tool_input.skill // empty' 2>/dev/null)

if [ -n "$cmd" ]; then
  # Avoid duplicates: only log if not the same as the last entry
  if [ -f "$LOG_FILE" ] && [ "$(tail -1 "$LOG_FILE" 2>/dev/null)" = "$cmd" ]; then
    exit 0
  fi

  echo "$cmd" >> "$LOG_FILE"

  # Trim log
  if [ -f "$LOG_FILE" ]; then
    lines=$(wc -l < "$LOG_FILE")
    if [ "$lines" -gt "$MAX_LINES" ]; then
      tail -"$MAX_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
  fi
fi
