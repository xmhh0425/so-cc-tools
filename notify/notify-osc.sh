#!/bin/bash
# Claude Code Notification hook — OSC 777 (Warp/Ghostty/urxvt)
# Reads notification JSON from stdin, emits desktop notification via terminal escape sequence.

INPUT=$(cat 2>/dev/null)
MESSAGE=$(echo "$INPUT" | jq -r '.message // "Claude Code needs your attention"' 2>/dev/null)

# OSC 777 format: ESC ] 777 ; notify ; <title> ; <body> BEL
TITLE="Claude Code"
SEQUENCE=$(printf '\033]777;notify;%s;%s\007' "$TITLE" "$MESSAGE")

# Return JSON with terminalSequence — Claude Code emits it to the terminal
jq -nc --arg seq "$SEQUENCE" '{terminalSequence: $seq}'
