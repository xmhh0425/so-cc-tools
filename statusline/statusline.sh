#!/bin/bash
# Claude Code Status Line (multi-line, colorized)
# Line 1: Model | Context progress (colored by usage)
# Line 2: Latest turn skills
# Line 3: All skills in session

set -euo pipefail

SKILLS_LOG="/tmp/cc-skills.log"
MERGE_FILE=$(mktemp /tmp/cc-skills-merge.XXXXXX)
trap 'rm -f "$MERGE_FILE"' EXIT

# Colors
C_CYAN=$'\033[36m'
C_GREEN=$'\033[32m'
C_YELLOW=$'\033[33m'
C_RED=$'\033[31m'
C_BLUE=$'\033[34m'
C_MAGENTA=$'\033[35m'
C_WHITE=$'\033[37m'
C_GRAY=$'\033[90m'
C_BOLD_WHITE=$'\033[1;37m'
C_RESET=$'\033[0m'

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

# === All skills in session ===

if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  jq -r '
    select(.type == "assistant")
    | .message.content[]?
    | select(.type == "tool_use" and .name == "Skill")
    | .input.skill // empty
  ' "$transcript" 2>/dev/null \
    | awk '!seen[$0]++{printf "C:%s\n",$0}' > "$MERGE_FILE" 2>/dev/null || true
fi

if [ -f "$SKILLS_LOG" ]; then
  tail -20 "$SKILLS_LOG" 2>/dev/null \
    | awk '!seen[$0]++{printf "U:%s\n",$0}' >> "$MERGE_FILE" 2>/dev/null || true
fi

# Format all skills with colors
all_skills=""
if [ -s "$MERGE_FILE" ]; then
  all_skills=$(awk -v blue="$C_BLUE" -v mag="$C_MAGENTA" -v dim="$C_WHITE" -v reset="$C_RESET" '
    NR > 1 { printf " %s>%s ", dim, reset }
    {
      if ($1 == "C") printf "%s%s%s", blue, $0, reset
      else printf "%s%s%s", mag, $0, reset
    }' "$MERGE_FILE" 2>/dev/null || true)
fi
[ -n "$all_skills" ] || all_skills="${C_WHITE}-${C_RESET}"

# === Latest turn skills ===

latest_skills="${C_WHITE}-${C_RESET}"

if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  last_user_line=$(grep -n '"type":"user"' "$transcript" 2>/dev/null | tail -1 | cut -d: -f1)

  if [ -n "$last_user_line" ]; then
    total_lines=$(wc -l < "$transcript")

    if [ "$last_user_line" -lt "$total_lines" ]; then
      latest_skills=$(tail -n +"$((last_user_line + 1))" "$transcript" 2>/dev/null \
        | jq -r '
            select(.type == "assistant")
            | .message.content[]?
            | select(.type == "tool_use" and .name == "Skill")
            | .input.skill // empty
          ' 2>/dev/null \
        | awk '!seen[$0]++' \
        | awk -v blue="$C_BLUE" -v dim="$C_WHITE" -v reset="$C_RESET" \
          'NR==1{printf "%sC:%s%s",blue,$0,reset}
           NR>1{printf " %s>%s %sC:%s%s",dim,reset,blue,$0,reset}' 2>/dev/null || true)
    fi
  fi
fi

if [ "$latest_skills" = "${C_WHITE}-${C_RESET}" ] && [ -f "$SKILLS_LOG" ]; then
  latest_skills=$(tail -5 "$SKILLS_LOG" 2>/dev/null \
    | awk '!seen[$0]++' \
    | awk -v mag="$C_MAGENTA" -v dim="$C_WHITE" -v reset="$C_RESET" \
      'NR==1{printf "%sU:%s%s",mag,$0,reset}
       NR>1{printf " %s>%s %sU:%s%s",dim,reset,mag,$0,reset}' 2>/dev/null || true)
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
    duration_display="⏱${hours}h${mins}m"
  else
    duration_display="⏱${mins}m"
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
  model_display="${C_BOLD_WHITE}${model}${C_RESET} ${C_MAGENTA}[${effort}]${C_RESET}"
else
  model_display="${C_BOLD_WHITE}${model}${C_RESET}"
fi

# Multi-line output
printf "%sModel:%s %s | %sContext:%s %s%s\n%sLatest:%s %s\n%sSkills:%s %s" \
  "$C_CYAN" "$C_RESET" "$model_display" \
  "$C_CYAN" "$C_RESET" "$ctx" \
  "${duration_display:+ ${C_GRAY}${duration_display}${C_RESET}}" \
  "$C_YELLOW" "$C_RESET" "$latest_skills" \
  "$C_WHITE" "$C_RESET" "$all_skills"
