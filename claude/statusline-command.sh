#!/bin/bash
# Claude Code Status Line — robbyrussell theme style
# Displays:  host  ➜  <dir> git:(branch) ✗  [ctx%]  [5h%]  [cpu ram disk]  session-context

# ANSI color codes using $'...' syntax for proper interpretation
RST=$'\e[0m'
BOLD_GREEN=$'\e[1;32m'
BOLD_RED=$'\e[1;31m'
BOLD_BLUE=$'\e[1;34m'
CYAN=$'\e[36m'
RED=$'\e[31m'
YELLOW=$'\e[33m'
GRAY=$'\e[90m'
ORANGE=$'\e[38;5;214m'
LIGHT_MAGENTA=$'\e[95m'
BOLD_CYAN=$'\e[1;96m'

input=$(cat)
cwd=$(echo "$input" | jq -r ".workspace.current_dir")

cd "$cwd" 2>/dev/null || true
dir_name=$(basename "$cwd")

# Hostname badge: color is hashed from the name, so each machine keeps its own color.
host="${HOSTNAME:-$(uname -n)}"
host="${host%%.*}"
HOST_BGS=(203 208 220 112 43 75 141 213)
host_bg=${HOST_BGS[$(( $(printf '%s' "$host" | cksum | cut -d' ' -f1) % ${#HOST_BGS[@]} ))]}
host_badge=$'\e[1;30;48;5;'"${host_bg}m ${host} ${RST}"

# Git info — robbyrussell style: git:(branch) ✗
if git rev-parse --git-dir > /dev/null 2>&1; then
    branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD 2>/dev/null)
    if git --no-optional-locks diff --quiet 2>/dev/null && git --no-optional-locks diff --cached --quiet 2>/dev/null; then
        dirty_marker=""
    else
        dirty_marker=" ${YELLOW}✗${RST}"
    fi
    git_part=" ${BOLD_BLUE}git:(${RED}${branch}${BOLD_BLUE})${RST}${dirty_marker}"
else
    git_part=""
fi

# Model name and reasoning effort level
model=$(echo "$input" | jq -r ".model.display_name // empty")
effort=$(echo "$input" | jq -r ".effort.level // empty")
if [ -n "$model" ]; then
    if [ -n "$effort" ]; then
        model_display=" ${GRAY}[${BOLD_CYAN}${model}${GRAY}:${LIGHT_MAGENTA}${effort}${GRAY}]${RST}"
    else
        model_display=" ${GRAY}[${BOLD_CYAN}${model}${GRAY}]${RST}"
    fi
else
    model_display=""
fi

# AWS profile (from environment Claude Code was launched with)
aws_profile="${AWS_PROFILE:-${AWS_DEFAULT_PROFILE:-}}"
# Fall back to "default" only if a real default section exists (matches starship).
if [ -z "$aws_profile" ] && grep -qsE '^\[(profile )?default\]' "$HOME/.aws/config" "$HOME/.aws/credentials"; then
    aws_profile="default"
fi
if [ -n "$aws_profile" ]; then
    aws_display=" ${GRAY}[${LIGHT_MAGENTA}☁️ ${BOLD_CYAN}${aws_profile}${GRAY}]${RST}"
else
    aws_display=""
fi

# Context window usage
used=$(echo "$input" | jq -r ".context_window.used_percentage // empty")
if [ -n "$used" ]; then
    ctx_display=" ${GRAY}[${LIGHT_MAGENTA}🧠${BOLD_CYAN}${used}%${GRAY}]${RST}"
else
    ctx_display=""
fi

# 5-hour rate limit usage (Claude.ai subscription only — absent for API users)
five_pct=$(echo "$input" | jq -r ".rate_limits.five_hour.used_percentage // empty")
five_resets_at=$(echo "$input" | jq -r ".rate_limits.five_hour.resets_at // empty")
if [ -n "$five_pct" ]; then
    reset_time=""
    if [ -n "$five_resets_at" ]; then
        reset_time=" ${GRAY}↻${BOLD_CYAN}$(date -d "@${five_resets_at}" +%H:%M)${RST}"
    fi
    five_display=" ${GRAY}[${LIGHT_MAGENTA}⏳${BOLD_CYAN}$(printf "%.0f" "$five_pct")%${reset_time}${GRAY}]${RST}"
else
    five_display=""
fi

# System load: CPU, RAM and root disk usage (Linux /proc only)
sys_pct() {
    local color=$BOLD_CYAN
    if (( $2 >= 90 )); then color=$BOLD_RED; elif (( $2 >= 75 )); then color=$YELLOW; fi
    printf '%s%s %s%s%%' "$GRAY" "$1" "$color" "$2"
}
cpu_sample() {
    local _ u n s idle iow irq sirq st
    read -r _ u n s idle iow irq sirq st _ < /proc/stat
    cpu_total=$((u + n + s + idle + iow + irq + sirq + st))
    cpu_busy=$((cpu_total - idle - iow))
}
if [ -r /proc/stat ] && [ -r /proc/meminfo ]; then
    # CPU is averaged since the previous render, so state is kept between runs.
    cpu_state="${XDG_RUNTIME_DIR:-$HOME/.cache}/claude-statusline-cpu"
    { read -r prev_total prev_busy < "$cpu_state"; } 2>/dev/null
    cpu_sample
    if ! [[ $prev_total =~ ^[0-9]+$ && $prev_busy =~ ^[0-9]+$ ]] || (( cpu_total <= prev_total )); then
        prev_total=$cpu_total prev_busy=$cpu_busy
        sleep 0.2
        cpu_sample
    fi
    printf '%s %s\n' "$cpu_total" "$cpu_busy" > "$cpu_state" 2>/dev/null
    cpu_pct=$(( (cpu_busy - prev_busy) * 100 / (cpu_total - prev_total) ))

    while read -r key val _; do
        case $key in
            MemTotal:) mem_total=$val ;;
            MemAvailable:) mem_avail=$val ;;
        esac
    done < /proc/meminfo
    mem_pct=$(( (mem_total - mem_avail) * 100 / mem_total ))

    disk_pct=$(df -P / | awk 'NR == 2 { sub("%", "", $5); print $5 }')

    sys_display=" ${GRAY}[$(sys_pct cpu "$cpu_pct") $(sys_pct ram "$mem_pct") $(sys_pct disk "${disk_pct:-0}")${GRAY}]${RST}"
else
    sys_display=""
fi

# Session context summary (session-specific)
session_id=$(echo "$input" | jq -r ".session_id // empty")
if [ -n "$session_id" ]; then
    context_file="$HOME/.claude/contexts/$session_id"
    if [ -f "$context_file" ] && [ -s "$context_file" ]; then
        context=$(cat "$context_file")
        context_display=" ${GRAY}│ ${ORANGE}${context}${RST}"
    else
        context_display=""
    fi
else
    context_display=""
fi

# Arrow: green if git clean or no git, red if dirty
if [ -n "$dirty_marker" ]; then
    arrow="${BOLD_RED}➜${RST}"
else
    arrow="${BOLD_GREEN}➜${RST}"
fi

# Output:  host  ➜  dir git:(branch) ✗  [model:effort]  [aws]  [ctx%]  [5h%]  [cpu ram disk]  session-context
printf "%s %s  %s%s%s%s%s%s%s%s\n" \
    "$host_badge" \
    "$arrow" \
    "${CYAN}${dir_name}${RST}" \
    "$git_part" \
    "$model_display" \
    "$aws_display" \
    "$ctx_display" \
    "$five_display" \
    "$sys_display" \
    "$context_display"
