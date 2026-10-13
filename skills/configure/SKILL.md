---
name: configure
description: Change what the Statuslines plugin shows, such as hiding or reordering parts, showing percentages without bars, or changing bar width, shapes, colors and reset times. Use when the user runs /statuslines:configure, or asks to change a status line drawn by this plugin's statusline-plugin.sh.
argument-hint: "[what to change, like: percent only, hide git]"
---

# Configure Statuslines

The options live in `statusline-plugin.json` in `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`. Every key is optional, and a missing key uses its default. The status line reads the file each time it refreshes, so changes show up after the user's next message, with no restart.

The user asked for: $ARGUMENTS

## 1. Check this plugin draws their status line

Read `statusLine.command` in `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`. If it doesn't mention `statusline-plugin.sh`, these options change nothing: tell the user, suggest `/statuslines:setup`, and stop unless they still want to go on.

## 2. Work out the change

If the request above is empty, read the current file (no file means all defaults), describe the current setup in plain words, list what can change, and ask what they want.

| Key | Values | Default | What it does |
| --- | --- | --- | --- |
| `parts` | list of part names | `["folder", "git", "model", "context", "five_hour", "weekly"]` | Which parts show, left to right. Leave a part out to hide it |
| `bar_style` | `"both"`, `"percent"`, `"bar"` | `"both"` | Bar and percent, percent only, or bar only |
| `bar_width` | 1 to 40 | `10` | Number of cells in each bar |
| `effort` | `true`, `false` | `true` | Effort level after the model name |
| `labels` | `true`, `false` | `true` | The `ctx`, `5h` and `week` labels |
| `reset_time` | `"off"`, `"on"`, `"near-limit"` | `"off"` | Time until the 5-hour and weekly limits reset. `near-limit` shows it only once that bar reaches `danger_at` |
| `colors` | `true`, `false` | `true` | `false` prints plain text |
| `warn_at` | 0 to 101 | `50` | Percent where a bar turns yellow |
| `danger_at` | 0 to 101 | `80` | Percent where a bar turns red |
| `context_size` | `true`, `false` | `false` | The context window size after the context meter, like `42% of 1M` |
| `ascii` | `true`, `false` | `false` | Plain ASCII only: ASCII bar shapes, `git:` before the branch, `\|` between parts, `reset` before reset times. Shapes set in `shapes` still win |
| `stale_after` | minutes, `0` turns it off | `15` | Turn the 5-hour and weekly bars grey, with `updated 25m ago`, once the session has had no reply from Claude for this long, since their numbers may be out of date |
| `shapes` | object, see below | blocks, squares, dots | The characters each bar is drawn with |

Parts: `folder`, `git` (branch and uncommitted changes), `model`, `context`, `five_hour`, `weekly`, plus five that are off by default: `duration` (session time), `lines` (lines added and removed), `cost` (session cost in dollars, hidden while it is $0.00), `agent` (the agent's name, only while running as an agent) and `worktree` (the worktree's name, only while in one).

`shapes` sets a `[filled, empty]` pair per bar, for example `{"context": ["█", "░"], "five_hour": ["■", "□"], "weekly": ["●", "○"]}`. Leave out a bar to keep its default.

How requests usually map:

- "hide X" or "turn off X": remove X from `parts`.
- "show X" or "turn on X": add X to `parts`. Put the extras (`duration`, `lines`, `cost`) at the end unless the user says where.
- "only percentages" or "no bars": `"bar_style": "percent"`.
- "reset to defaults": delete the file.

## 3. Write the file

Keep the keys the user already set unless they asked to change them. Write plain JSON with no comments, then check it with `jq . <file>`. Anything outside the table is ignored, so stick to it.

## 4. Show the result

Preview the new line with sample data, run from the user's project so the folder and branch are real:

```bash
now=$(date +%s)
jq -n --argjson f $((now + 8100)) --argjson w $((now + 385200)) '{
  workspace: {current_dir: env.PWD}, model: {display_name: "Opus"}, effort: {level: "high"},
  context_window: {used_percentage: 42},
  rate_limits: {five_hour: {used_percentage: 63, resets_at: $f}, seven_day: {used_percentage: 85, resets_at: $w}},
  cost: {total_cost_usd: 1.5, total_duration_ms: 4380000, total_lines_added: 120, total_lines_removed: 30}
}' | bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline-plugin.sh" | sed $'s/\x1b\\[[0-9;]*m//g'
```

Show the user that line, say it uses sample numbers, and tell them their real status line changes after their next message.
