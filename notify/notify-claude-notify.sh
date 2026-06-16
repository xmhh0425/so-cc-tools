#!/bin/bash
# Claude Code hook → ClaudeNotify HTTP bridge
# Reads JSON from stdin, posts to the ClaudeNotify app on localhost:18765.

INPUT=$(cat 2>/dev/null)
EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // ""' 2>/dev/null)

case "$EVENT" in
  Stop)          ENDPOINT="/hook/stop" ;;
  Notification)  ENDPOINT="/hook/notification" ;;
  StopFailure)   ENDPOINT="/hook/stopfailure" ;;
  *)             exit 0 ;;
esac

curl -s -o /dev/null -X POST "http://127.0.0.1:18765${ENDPOINT}" \
  -H "Content-Type: application/json" \
  -d "$INPUT" 2>/dev/null &

exit 0
