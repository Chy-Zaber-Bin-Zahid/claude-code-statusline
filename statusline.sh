#!/usr/bin/env bash
# Statusline: a status line for Claude Code
# folder · git branch · model + effort · context bar · 5-hour usage bar · weekly usage bar
# https://github.com/Chy-Zaber-Bin-Zahid/statusline
#
# Claude Code pipes the session's data to this script as JSON on stdin and
# shows whatever it prints. The script makes no network calls.

if ! command -v jq >/dev/null 2>&1; then
    echo "statusline needs jq: https://jqlang.org/download/"
    exit 0
fi

input=$(cat)

# Read every field in one jq call, one per line. Percentages are rounded by
# jq so the shell never parses decimals (which fails in comma-decimal locales).
{
    read -r cwd
    read -r model
    read -r effort
    read -r ctx
    read -r fivehour
    read -r weekly
} < <(printf '%s' "$input" | jq -r '
    def pct: if type == "number" then (. + 0.5 | floor | tostring) else "" end;
    (.workspace.current_dir // .cwd // ""),
    (.model.display_name // "Claude"),
    (.effort.level // ""),
    (.context_window.used_percentage | pct),
    (.rate_limits.five_hour.used_percentage | pct),
    (.rate_limits.seven_day.used_percentage | pct)
' 2>/dev/null)
model=${model:-Claude}

R=$'\033[0m'; D=$'\033[2m'
BLUE=$'\033[38;5;110m'; PURPLE=$'\033[38;5;140m'; GREEN=$'\033[38;5;108m'
YELLOW=$'\033[38;5;179m'; RED=$'\033[38;5;167m'

# 10-cell bar + percent, coloured green / yellow (50%+) / red (80%+)
# usage: pct_bar <whole percent> [fill glyph] [empty glyph]
pct_bar() {
    local u=$1 on=${2:-█} off=${3:-░} width=10 filled i C bar=""
    if   [ "$u" -ge 80 ]; then C=$RED
    elif [ "$u" -ge 50 ]; then C=$YELLOW
    else                       C=$GREEN
    fi
    filled=$(( u * width / 100 ))
    [ "$filled" -gt "$width" ] && filled=$width
    for ((i = 0; i < filled; i++));     do bar+=$on;  done
    for ((i = filled; i < width; i++)); do bar+=$off; done
    printf '%s' "${C}${bar}${R} ${C}${u}%${R}"
}

parts=()

# ── folder ─────────────────────────────────────────────────
if [ -n "$cwd" ]; then
    parts+=("${BLUE}$(basename "$cwd")${R}")
fi

# ── git branch + count of uncommitted changes ──────────────
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null ||
             git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    dirty=$(git --no-optional-locks -C "$cwd" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    if [ "$dirty" -gt 0 ]; then
        parts+=("${YELLOW}⎇ ${branch}*${R}${D}${dirty}${R}")
    else
        parts+=("${GREEN}⎇ ${branch}${R}")
    fi
fi

# ── model + effort level ───────────────────────────────────
if [ -n "$effort" ]; then
    parts+=("${PURPLE}${model}${R} ${D}${effort}${R}")
else
    parts+=("${PURPLE}${model}${R}")
fi

# ── context window (blocks) ────────────────────────────────
if [ -n "$ctx" ]; then
    parts+=("${D}ctx${R} $(pct_bar "$ctx")")
fi

# ── 5-hour plan usage (squares) ────────────────────────────
if [ -n "$fivehour" ]; then
    parts+=("${D}5h${R} $(pct_bar "$fivehour" "■" "□")")
fi

# ── weekly plan usage (dots) ───────────────────────────────
if [ -n "$weekly" ]; then
    parts+=("${D}week${R} $(pct_bar "$weekly" "●" "○")")
fi

# ── join with dim separators ───────────────────────────────
out=""
for p in "${parts[@]}"; do
    [ -n "$out" ] && out+="${D} · ${R}"
    out+=$p
done
printf '%s\n' "$out"
