#!/usr/bin/env bash
# Runs when a new Claude Code session starts. If Statuslines is installed but
# isn't drawing the status line, it tells the person how to turn it on. Once
# it's set up it prints nothing.
#
# It prints only {"systemMessage": ...}, which Claude Code shows to the person.
# Plain text from a SessionStart hook would land in Claude's context instead.

dir=${CLAUDE_CONFIG_DIR:-$HOME/.claude}
project=${CLAUDE_PROJECT_DIR:-$PWD}
settings=("$dir/settings.json" "$project/.claude/settings.json" "$project/.claude/settings.local.json")

ours="" other="" refresh=""
for f in "${settings[@]}"; do
    [ -f "$f" ] || continue
    if grep -q 'statusline-plugin\.sh' "$f"; then
        ours=1
        grep -q '"refreshInterval"' "$f" && refresh=1
    elif grep -q '"statusLine"' "$f"; then
        other=1
    fi
done

if [ -n "$ours" ] && [ -f "$dir/statusline-plugin.sh" ] && [ -n "$refresh" ]; then
    exit 0
elif [ -n "$ours" ] && [ -f "$dir/statusline-plugin.sh" ]; then
    # Set up before 2.2.0: the line only redraws on new replies, so it can't
    # notice when the usage numbers get old.
    msg="Run /statuslines:setup once more so Statuslines refreshes every minute and can flag out-of-date usage numbers."
elif [ -n "$ours" ]; then
    msg="Statuslines can't find its script. Run /statuslines:setup to put it back."
elif [ -n "$other" ]; then
    msg="Statuslines is installed, but your status line runs a different command. Run /statuslines:setup to switch, or uninstall the plugin to keep yours."
else
    msg="Statuslines is installed but not turned on yet. Run /statuslines:setup to turn it on."
fi
printf '{"systemMessage": "%s"}\n' "$msg"
