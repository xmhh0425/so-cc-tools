#!/bin/bash
# Claude Code hook → CC Tools HTTP bridge
# Reads JSON from stdin, posts to the CC Tools app on localhost.
#
# Port resolution: reads ~/.config/cc-tools/port (written by the app),
# falls back to 18765 (the default).

INPUT=$(cat 2>/dev/null)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null)

case "$EVENT" in
  Stop)          ENDPOINT="/hook/stop" ;;
  Notification)  ENDPOINT="/hook/notification" ;;
  StopFailure)   ENDPOINT="/hook/stopfailure" ;;
  *)             exit 0 ;;
esac

PORT_FILE="$HOME/.config/cc-tools/port"
if [ -f "$PORT_FILE" ] && [ -r "$PORT_FILE" ]; then
  PORT=$(tr -d '[:space:]' < "$PORT_FILE")
fi
PORT="${PORT:-18765}"

curl -s -o /dev/null -X POST "http://127.0.0.1:${PORT}${ENDPOINT}" \
  -H "Content-Type: application/json" \
  -d "$INPUT" 2>/dev/null &

exit 0
