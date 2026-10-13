#!/usr/bin/env bash
# Statusline: a status line for Claude Code
# folder · git branch · model + effort · context bar · 5-hour usage bar · weekly usage bar
# https://github.com/Chy-Zaber-Bin-Zahid/claude-code-statusline
#
# Claude Code pipes the session's data to this script as JSON on stdin and
# shows whatever it prints. The script makes no network calls.
#
# Options are read from statusline-plugin.json in ${CLAUDE_CONFIG_DIR:-~/.claude}
# (or the file named by $STATUSLINE_CONFIG). Every key is optional; the README
# lists them all.

if ! command -v jq >/dev/null 2>&1; then
    echo "statusline needs jq: https://jqlang.org/download/"
    exit 0
fi

input=$(cat)
config=${STATUSLINE_CONFIG:-${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline-plugin.json}

# One jq call reads the session data and the options, one value per line.
# jq rounds the numbers so the shell never parses decimals (which fails in
# comma-decimal locales), and replaces any option it can't use with its default.
program='
def pct: if type == "number" then (. + 0.5 | floor | tostring) else "" end;
def int: if type == "number" then (floor | tostring) else "" end;
def money: if type == "number" then ((. * 100 + 0.5) | floor) as $cents
    | "\($cents / 100 | floor).\($cents % 100 | if . < 10 then "0\(.)" else tostring end)"
    else "" end;
def num($d; $lo; $hi): if type == "number" and . >= $lo and . <= $hi then floor else $d end;
def oneof($d; $xs): . as $v | if any($xs[]; . == $v) then $v else $d end;
def flag($d): if type == "boolean" then . else $d end;
def shape($d): if type == "array" and length == 2 and all(.[]; type == "string" and length > 0)
    then . else $d end;

($cfg[0] | if type == "object" then . else {} end) as $o
| ($o.shapes | if type == "object" then . else {} end) as $s
| ["folder", "git", "model", "context", "five_hour", "weekly", "duration", "lines", "cost"] as $known
| (.workspace.current_dir // .cwd // ""),
  (.model.display_name // "Claude"),
  (.effort.level // ""),
  (.context_window.used_percentage | pct),
  (.rate_limits.five_hour.used_percentage | pct),
  (.rate_limits.seven_day.used_percentage | pct),
  (.rate_limits.five_hour.resets_at | int),
  (.rate_limits.seven_day.resets_at | int),
  (.cost.total_duration_ms | int),
  (.cost.total_lines_added | int),
  (.cost.total_lines_removed | int),
  (.cost.total_cost_usd | money),
  (if ($o.parts | type) == "array"
     then [$o.parts[] | select(type == "string") | select(. as $p | any($known[]; . == $p))]
     else ["folder", "git", "model", "context", "five_hour", "weekly"] end | join(" ")),
  ($o.bar_style | oneof("both"; ["both", "percent", "bar"])),
  ($o.bar_width | num(10; 1; 40) | tostring),
  ($o.effort | flag(true) | tostring),
  ($o.labels | flag(true) | tostring),
  ($o.reset_time | oneof("off"; ["off", "on", "near-limit"])),
  ($o.colors | flag(true) | tostring),
  ($o.warn_at | num(50; 0; 101) | tostring),
  ($o.danger_at | num(80; 0; 101) | tostring),
  ($s.context | shape(["█", "░"]) | .[]),
  ($s.five_hour | shape(["■", "□"]) | .[]),
  ($s.weekly | shape(["●", "○"]) | .[])
'
read_fields() { printf '%s' "$input" | jq -r "$@" "$program" 2>/dev/null; }

fields="" config_error=""
if [ -f "$config" ]; then
    fields=$(read_fields --slurpfile cfg "$config")
fi
if [ -z "$fields" ]; then
    fields=$(read_fields --argjson cfg '[]')
    # The session data was fine, so the options file is what jq couldn't read.
    [ -f "$config" ] && [ -n "$fields" ] && config_error=1
fi

{
    IFS= read -r cwd;       IFS= read -r model;     IFS= read -r effort
    IFS= read -r ctx;       IFS= read -r fivehour;  IFS= read -r weekly
    IFS= read -r fh_reset;  IFS= read -r wk_reset;  IFS= read -r dur_ms
    IFS= read -r added;     IFS= read -r removed;   IFS= read -r cost
    IFS= read -r parts;     IFS= read -r bar_style; IFS= read -r bar_width
    IFS= read -r show_effort; IFS= read -r labels;  IFS= read -r reset_time
    IFS= read -r colors;    IFS= read -r warn_at;   IFS= read -r danger_at
    IFS= read -r ctx_on;    IFS= read -r ctx_off
    IFS= read -r fh_on;     IFS= read -r fh_off
    IFS= read -r wk_on;     IFS= read -r wk_off
} <<< "$fields"

# jq couldn't read the session data at all: show the model name alone.
if [ -z "$fields" ]; then
    parts=model bar_style=both bar_width=10 show_effort=true labels=true
    reset_time=off colors=true warn_at=50 danger_at=80
fi
model=${model:-Claude}

if [ "$colors" = false ]; then
    R="" D="" BLUE="" PURPLE="" GREEN="" YELLOW="" RED="" GREY=""
else
    R=$'\033[0m'; D=$'\033[2m'
    BLUE=$'\033[38;5;110m'; PURPLE=$'\033[38;5;140m'; GREEN=$'\033[38;5;108m'
    YELLOW=$'\033[38;5;179m'; RED=$'\033[38;5;167m'; GREY=$'\033[38;5;245m'
fi
[ "$reset_time" != off ] && now=$(date +%s)

# Time left until a reset, like 4d11h, 2h15m or 40m. Prints nothing once past.
until_reset() {
    local left=$(( $1 - now )) d h m
    [ "$left" -gt 0 ] || return 0
    d=$(( left / 86400 )); h=$(( left % 86400 / 3600 )); m=$(( left % 3600 / 60 ))
    if   [ "$d" -gt 0 ]; then printf '%sd%sh' "$d" "$h"
    elif [ "$h" -gt 0 ]; then printf '%sh%sm' "$h" "$m"
    else                      printf '%sm' "$m"
    fi
}

# A usage meter: label, bar and/or percent, then the reset time if it's wanted.
# Coloured green, yellow from warn_at, red from danger_at.
# usage: meter <label> <whole percent> <fill glyph> <empty glyph> [reset epoch]
meter() {
    local label=$1 u=$2 on=$3 off=$4 reset=$5 C bar="" out="" filled i left
    if   [ "$u" -ge "$danger_at" ]; then C=$RED
    elif [ "$u" -ge "$warn_at" ];   then C=$YELLOW
    else                                 C=$GREEN
    fi
    if [ "$bar_style" != percent ]; then
        filled=$(( u * bar_width / 100 ))
        [ "$filled" -gt "$bar_width" ] && filled=$bar_width
        for ((i = 0; i < filled; i++));         do bar+=$on;  done
        for ((i = filled; i < bar_width; i++)); do bar+=$off; done
    fi
    [ "$labels" = true ] && out="${D}${label}${R} "
    case $bar_style in
        percent) out+="${C}${u}%${R}" ;;
        bar)     out+="${C}${bar}${R}" ;;
        *)       out+="${C}${bar}${R} ${C}${u}%${R}" ;;
    esac
    if [ -n "$reset" ] && { [ "$reset_time" = on ] ||
                            { [ "$reset_time" = near-limit ] && [ "$u" -ge "$danger_at" ]; }; }; then
        left=$(until_reset "$reset")
        [ -n "$left" ] && out+=" ${D}↻${left}${R}"
    fi
    printf '%s' "$out"
}

segments=()
for part in $parts; do
    case $part in
        # ── folder ─────────────────────────────────────────────
        folder)
            [ -n "$cwd" ] && segments+=("${BLUE}$(basename "$cwd")${R}")
            ;;
        # ── git branch + count of uncommitted changes ──────────
        git)
            if [ -n "$cwd" ] && git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
                branch=$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null ||
                         git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
                dirty=$(git --no-optional-locks -C "$cwd" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
                if [ "$dirty" -gt 0 ]; then
                    segments+=("${YELLOW}⎇ ${branch}*${R}${D}${dirty}${R}")
                else
                    segments+=("${GREEN}⎇ ${branch}${R}")
                fi
            fi
            ;;
        # ── model + effort level ───────────────────────────────
        model)
            if [ "$show_effort" = true ] && [ -n "$effort" ]; then
                segments+=("${PURPLE}${model}${R} ${D}${effort}${R}")
            else
                segments+=("${PURPLE}${model}${R}")
            fi
            ;;
        # ── usage meters: context, 5-hour and weekly ───────────
        context)
            [ -n "$ctx" ] && segments+=("$(meter ctx "$ctx" "$ctx_on" "$ctx_off")")
            ;;
        five_hour)
            [ -n "$fivehour" ] && segments+=("$(meter 5h "$fivehour" "$fh_on" "$fh_off" "$fh_reset")")
            ;;
        weekly)
            [ -n "$weekly" ] && segments+=("$(meter week "$weekly" "$wk_on" "$wk_off" "$wk_reset")")
            ;;
        # ── session time ───────────────────────────────────────
        duration)
            if [ -n "$dur_ms" ]; then
                secs=$(( dur_ms / 1000 ))
                h=$(( secs / 3600 )); m=$(( secs % 3600 / 60 )); s=$(( secs % 60 ))
                if   [ "$h" -gt 0 ]; then dur="${h}h${m}m"
                elif [ "$m" -gt 0 ]; then dur="${m}m"
                else                      dur="${s}s"
                fi
                segments+=("${GREY}${dur}${R}")
            fi
            ;;
        # ── lines added / removed this session ─────────────────
        lines)
            if [ "${added:-0}" -gt 0 ] || [ "${removed:-0}" -gt 0 ]; then
                segments+=("${GREEN}+${added:-0}${R}${D}/${R}${RED}-${removed:-0}${R}")
            fi
            ;;
        # ── session cost ───────────────────────────────────────
        cost)
            [ -n "$cost" ] && segments+=("${GREY}\$${cost}${R}")
            ;;
    esac
done

if [ -n "$config_error" ]; then
    segments+=("${RED}statusline-plugin.json is not valid JSON${R}")
fi

# ── join with dim separators ───────────────────────────────
out=""
for p in "${segments[@]}"; do
    [ -n "$out" ] && out+="${D} · ${R}"
    out+=$p
done
printf '%s\n' "$out"
