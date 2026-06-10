#!/bin/bash
# UserPromptSubmit Hook - Track user-typed /slash skill invocations.
# Fires when the user submits a prompt.
# If the message starts with /, extracts the skill name and logs it.
# Reads JSON from stdin; skill name is in .message (e.g. "/statusline-setup").

LOG_FILE="/tmp/cc-skills.log"
MAX_LINES=50

input=$(cat)

# Extract skill name from prompt - handles /command and /command args
# Note: UserPromptSubmit stdin uses "prompt" field, not "message"
message=$(echo "$input" | jq -r '.prompt // .message // empty' 2>/dev/null || true)

if [[ "$message" =~ ^/([a-zA-Z0-9_-]+) ]]; then
  skill="${BASH_REMATCH[1]}"

  # Avoid duplicates: only log if not the same as the last entry
  if [ -f "$LOG_FILE" ] && [ "$(tail -1 "$LOG_FILE" 2>/dev/null)" = "$skill" ]; then
    exit 0
  fi

  echo "$skill" >> "$LOG_FILE"

  # Trim log
  if [ -f "$LOG_FILE" ]; then
    lines=$(wc -l < "$LOG_FILE")
    if [ "$lines" -gt "$MAX_LINES" ]; then
      tail -"$MAX_LINES" "$LOG_FILE" > "$LOG_FILE.tmp" && mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
  fi
fi
