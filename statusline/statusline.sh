#!/bin/bash
# Claude Code Status Line (multi-line, colorized)
# Line 1: Model | Context progress (colored by usage)
# Line 2: Latest turn skills
# Line 3: All skills in session
#
# Skills are parsed from the transcript (session-specific JSONL).
# No shared log file — each session shows only its own skills.

set -euo pipefail

MERGE_FILE=$(mktemp /tmp/cc-skills-merge.XXXXXX)
trap 'rm -f "$MERGE_FILE"' EXIT

# Colors - shared across dark/light themes
C_CYAN=$'\033[36m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_BLUE=$'\033[34m'
C_MAGENTA=$'\033[35m'
C_RESET=$'\033[0m'

# Detect system appearance and set theme-dependent colors
if defaults read -g AppleInterfaceStyle 2>/dev/null | grep -qi "Dark"; then
  C_MODEL=$'\033[1;37m'    # bold bright white - model name
  C_GRAY=$'\033[90m'       # dark gray - progress bar empty, placeholders
else
  C_MODEL=$'\033[1;30m'    # bold black - model name
  C_GRAY=$'\033[37m'       # light gray - progress bar empty, placeholders
fi
C_WHITE=$'\033[37m'

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "unknown"')

# Override model name with CC Switch proxy display name if available
# Detects tier from model id/name/display_name, then reads ANTHROPIC_DEFAULT_*_MODEL_NAME
_resolve_proxy_name() {
  local id
  id=$(echo "$input" | jq -r '.model.id // empty')
  [ -z "$id" ] && id=$(echo "$input" | jq -r '.model.name // empty')
  [ -z "$id" ] && id="$model"
  local lower
  lower=$(printf '%s' "$id" | tr '[:upper:]' '[:lower:]')
  local env_var=""
  case "$lower" in
    *opus*)   env_var="ANTHROPIC_DEFAULT_OPUS_MODEL_NAME" ;;
    *sonnet*) env_var="ANTHROPIC_DEFAULT_SONNET_MODEL_NAME" ;;
    *haiku*)  env_var="ANTHROPIC_DEFAULT_HAIKU_MODEL_NAME" ;;
  esac
  [ -n "$env_var" ] && [ -n "${!env_var:-}" ] && printf '%s' "${!env_var}"
}

_proxy=$(_resolve_proxy_name)
if [ -n "$_proxy" ]; then model="$_proxy"; fi
unset -f _resolve_proxy_name

effort=$(echo "$input" | jq -r '.effort.level // empty')
pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
transcript=$(echo "$input" | jq -r '.transcript_path // empty')

# Resolve relative transcript path
if [ -n "$transcript" ] && [ ! -f "$transcript" ]; then
  project_dir=$(echo "$input" | jq -r '.workspace.project_dir // empty')
  if [ -n "$project_dir" ] && [ -f "$project_dir/$transcript" ]; then
    transcript="$project_dir/$transcript"
  else
    transcript=""
  fi
fi

# Helper: extract all unique Skill tool_use names from a JSONL stream
_extract_skills() {
  jq -r '
    select(.type == "assistant")
    | .message.content[]?
    | select(.type == "tool_use" and .name == "Skill")
    | .input.skill // empty
  ' 2>/dev/null | awk '!seen[$0]++'
}

# Helper: extract the most recent Skill tool_use name from a JSONL stream
_extract_last_skill() {
  jq -r '
    select(.type == "assistant")
    | .message.content[]?
    | select(.type == "tool_use" and .name == "Skill")
    | .input.skill // empty
  ' 2>/dev/null | tail -1
}

# === All skills in session ===

all_skills="${C_WHITE}-${C_RESET}"

if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  _tmp=$(_extract_skills < "$transcript" 2>/dev/null || true)
  if [ -n "$_tmp" ]; then
    all_skills=$(echo "$_tmp" \
      | awk -v blue="$C_BLUE" -v dim="$C_WHITE" -v reset="$C_RESET" \
        'NR==1{printf "%s%s%s",blue,$0,reset}
         NR>1{printf " %s>%s %s%s%s",dim,reset,blue,$0,reset}' 2>/dev/null || true)
  fi
fi

# === Latest turn skills ===

latest_skills="${C_WHITE}-${C_RESET}"

if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  last_user_line=$(grep -n '"type":"user"' "$transcript" 2>/dev/null | tail -1 | cut -d: -f1 || true)

  if [ -n "$last_user_line" ]; then
    total_lines=$(wc -l < "$transcript")

    # Search after the last user message (current turn)
    if [ "$last_user_line" -lt "$total_lines" ]; then
      _tmp=$(tail -n +"$((last_user_line + 1))" "$transcript" 2>/dev/null \
        | _extract_last_skill 2>/dev/null || true)
      if [ -n "$_tmp" ]; then
        latest_skills=$(printf '%sC:%s%s' "$C_BLUE" "$_tmp" "$C_RESET")
      fi
    fi

    # Fallback: if no Skill in current turn, find the most recent Skill in entire transcript
    if [ "$latest_skills" = "${C_WHITE}-${C_RESET}" ]; then
      _tmp=$(_extract_last_skill < "$transcript" 2>/dev/null || true)
      if [ -n "$_tmp" ]; then
        latest_skills=$(printf '%sC:%s%s' "$C_BLUE" "$_tmp" "$C_RESET")
      fi
    fi
  fi
fi

[ -n "$latest_skills" ] || latest_skills="${C_WHITE}-${C_RESET}"

# === Session duration ===

duration_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // empty')
duration_display=""
if [ -n "$duration_ms" ]; then
  total_sec=$((duration_ms / 1000))
  hours=$((total_sec / 3600))
  mins=$(( (total_sec % 3600) / 60 ))
  if [ "$hours" -gt 0 ]; then
    duration_display="Session: ${hours}h${mins}m"
  else
    duration_display="Session: ${mins}m"
  fi
fi

# === Context progress bar ===

if [ -n "$pct" ]; then
  pct_int=$(printf '%.0f' "$pct")
  filled=$(( pct_int * 40 / 100 ))
  [ "$filled" -eq 0 ] && [ "$pct_int" -gt 0 ] && filled=1
  empty=$(( 40 - filled ))

  if [ "$pct_int" -ge 85 ]; then
    BAR_COLOR="$C_RED"
  elif [ "$pct_int" -ge 60 ]; then
    BAR_COLOR="$C_YELLOW"
  else
    BAR_COLOR="$C_GREEN"
  fi

  bar="${BAR_COLOR}"
  for ((i=0; i<filled; i++)); do bar+="█"; done
  bar+="${C_GRAY}"
  for ((i=0; i<empty; i++)); do bar+="░"; done
  bar+="${C_RESET}"

  ctx="${bar} ${pct_int}%"
else
  ctx="░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░ --%"
fi

# Build model display with effort level
if [ -n "$effort" ]; then
  model_display="${C_MODEL}${model}${C_RESET} ${C_MAGENTA}[${effort}]${C_RESET}"
else
  model_display="${C_MODEL}${model}${C_RESET}"
fi

# Multi-line output
printf "%sModel:%s %s | %sContext:%s %s%s\n%sLatest:%s %s\n%sSkills:%s %s" \
  "$C_CYAN" "$C_RESET" "$model_display" \
  "$C_CYAN" "$C_RESET" "$ctx" \
  "${duration_display:+ ${C_GRAY}${duration_display}${C_RESET}}" \
  "$C_YELLOW" "$C_RESET" "$latest_skills" \
  "$C_WHITE" "$C_RESET" "$all_skills"
