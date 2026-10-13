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
def money: if type == "number" and . >= 0.005 then ((. * 100 + 0.5) | floor) as $cents
    | "\($cents / 100 | floor).\($cents % 100 | if . < 10 then "0\(.)" else tostring end)"
    else "" end;
def size: if type == "number" and . > 0 then
    if . >= 1000000 then "\(. / 100000 | floor / 10)M" else "\(. / 1000 | floor)k" end
    else "" end;
def text: if type == "string" then gsub("[\n\r]"; " ") else "" end;
def num($d; $lo; $hi): if type == "number" and . >= $lo and . <= $hi then floor else $d end;
def oneof($d; $xs): . as $v | if any($xs[]; . == $v) then $v else $d end;
def flag($d): if type == "boolean" then . else $d end;
def shape($d): if type == "array" and length == 2 and all(.[]; type == "string" and length > 0)
    then . else $d end;

($cfg[0] | if type == "object" then . else {} end) as $o
| ($o.shapes | if type == "object" then . else {} end) as $s
| ($o.ascii | flag(false)) as $ascii
| ["folder", "git", "model", "context", "five_hour", "weekly",
   "duration", "lines", "cost", "agent", "worktree"] as $known
| (.workspace.current_dir // .cwd // "" | text),
  (.model.display_name // "Claude" | text),
  (.effort.level | text),
  (.context_window.used_percentage | pct),
  (.rate_limits.five_hour.used_percentage | pct),
  (.rate_limits.seven_day.used_percentage | pct),
  (.rate_limits.five_hour.resets_at | int),
  (.rate_limits.seven_day.resets_at | int),
  (.cost.total_duration_ms | int),
  (.cost.total_lines_added | int),
  (.cost.total_lines_removed | int),
  (.cost.total_cost_usd | money),
  (.session_id | text),
  (.context_window.context_window_size | size),
  (.agent.name | text),
  (.worktree.name | text),
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
  ($o.context_size | flag(false) | tostring),
  ($ascii | tostring),
  ($s.context | shape(if $ascii then ["#", "-"] else ["█", "░"] end) | .[]),
  ($s.five_hour | shape(if $ascii then ["=", "-"] else ["■", "□"] end) | .[]),
  ($s.weekly | shape(if $ascii then ["*", "."] else ["●", "○"] end) | .[])
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
    IFS= read -r cwd;        IFS= read -r model;      IFS= read -r effort
    IFS= read -r ctx;        IFS= read -r fivehour;   IFS= read -r weekly
    IFS= read -r fh_reset;   IFS= read -r wk_reset;   IFS= read -r dur_ms
    IFS= read -r added;      IFS= read -r removed;    IFS= read -r cost
    IFS= read -r session_id; IFS= read -r ctx_size;   IFS= read -r agent
    IFS= read -r worktree
    IFS= read -r parts;      IFS= read -r bar_style;  IFS= read -r bar_width
    IFS= read -r show_effort; IFS= read -r labels;    IFS= read -r reset_time
    IFS= read -r colors;     IFS= read -r warn_at;    IFS= read -r danger_at
    IFS= read -r context_size; IFS= read -r ascii
    IFS= read -r ctx_on;     IFS= read -r ctx_off
    IFS= read -r fh_on;      IFS= read -r fh_off
    IFS= read -r wk_on;      IFS= read -r wk_off
} <<< "$fields"

# jq couldn't read the session data at all: show the model name alone.
if [ -z "$fields" ]; then
    parts=model bar_style=both bar_width=10 show_effort=true labels=true
    reset_time=off colors=true warn_at=50 danger_at=80 context_size=false ascii=false
fi
model=${model:-Claude}
# The session id names the git cache file, so keep it to safe characters.
case $session_id in *[!A-Za-z0-9_-]*) session_id="" ;; esac

if [ "$colors" = false ]; then
    R="" D="" BLUE="" PURPLE="" GREEN="" YELLOW="" RED="" GREY=""
else
    R=$'\033[0m'; D=$'\033[2m'
    BLUE=$'\033[38;5;110m'; PURPLE=$'\033[38;5;140m'; GREEN=$'\033[38;5;108m'
    YELLOW=$'\033[38;5;179m'; RED=$'\033[38;5;167m'; GREY=$'\033[38;5;245m'
fi
if [ "$ascii" = true ]; then
    SEP=" | " BRANCH="git:" RESET="reset "
else
    SEP=" · " BRANCH="⎇ " RESET="↻"
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

# Branch and count of uncommitted changes, as two lines; nothing outside a repo.
# git status can be slow in big repos and the status line runs often, so the
# answer is kept for 5 seconds per session and folder.
git_info() {
    local cache="" stamp c b d tmp
    if [ -n "$session_id" ]; then
        cache="${TMPDIR:-/tmp}/statusline-plugin-git-$session_id"
        [ -n "$now" ] || now=$(date +%s)
        if [ -f "$cache" ] &&
           { IFS= read -r stamp && IFS= read -r c && IFS= read -r b && IFS= read -r d; } < "$cache"; then
            case $stamp in ''|*[!0-9]*) stamp=0 ;; esac
            if [ "$c" = "$cwd" ] && [ $(( now - stamp )) -ge 0 ] && [ $(( now - stamp )) -lt 5 ]; then
                [ "$d" = "-" ] || printf '%s\n%s\n' "$b" "$d"
                return 0
            fi
        fi
    fi
    if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
        b=$(git -C "$cwd" symbolic-ref --short -q HEAD 2>/dev/null ||
            git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
        d=$(git --no-optional-locks -C "$cwd" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    else
        b="" d="-"
    fi
    if [ -n "$cache" ] && tmp=$(mktemp "$cache.XXXXXX" 2>/dev/null); then
        printf '%s\n%s\n%s\n%s\n' "$now" "$cwd" "$b" "$d" > "$tmp" && mv -f "$tmp" "$cache"
    fi
    [ "$d" = "-" ] || printf '%s\n%s\n' "$b" "$d"
}

# A usage meter: label, bar and/or percent, an optional note, then the reset
# time if it's wanted. Coloured green, yellow from warn_at, red from danger_at.
# usage: meter <label> <whole percent> <fill glyph> <empty glyph> [reset epoch] [note]
meter() {
    local u=$2 on=$3 off=$4 reset=$5 note=$6 C bar="" out="" filled i left
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
    [ "$labels" = true ] && out="${D}$1${R} "
    case $bar_style in
        percent) out+="${C}${u}%${R}" ;;
        bar)     out+="${C}${bar}${R}" ;;
        *)       out+="${C}${bar}${R} ${C}${u}%${R}" ;;
    esac
    [ -n "$note" ] && out+=" ${D}${note}${R}"
    if [ -n "$reset" ] && { [ "$reset_time" = on ] ||
                            { [ "$reset_time" = near-limit ] && [ "$u" -ge "$danger_at" ]; }; }; then
        left=$(until_reset "$reset")
        [ -n "$left" ] && out+=" ${D}${RESET}${left}${R}"
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
            if [ -n "$cwd" ]; then
                { IFS= read -r branch; IFS= read -r dirty; } <<< "$(git_info)"
                if [ -n "$dirty" ] && [ "$dirty" -gt 0 ]; then
                    segments+=("${YELLOW}${BRANCH}${branch}*${R}${D}${dirty}${R}")
                elif [ -n "$dirty" ]; then
                    segments+=("${GREEN}${BRANCH}${branch}${R}")
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
            note=""
            [ "$context_size" = true ] && [ -n "$ctx_size" ] && note="of $ctx_size"
            [ -n "$ctx" ] && segments+=("$(meter ctx "$ctx" "$ctx_on" "$ctx_off" "" "$note")")
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
        # ── session cost, once there is some ───────────────────
        cost)
            [ -n "$cost" ] && segments+=("${GREY}\$${cost}${R}")
            ;;
        # ── agent and worktree, only while one is active ───────
        agent)
            if [ -n "$agent" ]; then
                lbl=""; [ "$labels" = true ] && lbl="${D}agent${R} "
                segments+=("${lbl}${PURPLE}${agent}${R}")
            fi
            ;;
        worktree)
            if [ -n "$worktree" ]; then
                lbl=""; [ "$labels" = true ] && lbl="${D}worktree${R} "
                segments+=("${lbl}${BLUE}${worktree}${R}")
            fi
            ;;
    esac
done

if [ -n "$config_error" ]; then
    segments+=("${RED}statusline-plugin.json is not valid JSON${R}")
fi

# ── join with dim separators ───────────────────────────────
out=""
for p in "${segments[@]}"; do
    [ -n "$out" ] && out+="${D}${SEP}${R}"
    out+=$p
done
printf '%s\n' "$out"
