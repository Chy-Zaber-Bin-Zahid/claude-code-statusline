---
name: setup
description: Turn on Statuslines as the user's status line, or refresh it after a plugin update. Run when the user types /statuslines:setup.
disable-model-invocation: true
---

# Set up Statuslines

Point the user's Claude Code status line at this plugin's script. Work through the steps in order, run the commands yourself, and tell the user in plain words what you changed.

Below, `CONFIG_DIR` means `${CLAUDE_CONFIG_DIR:-$HOME/.claude}`.

## 1. Check for jq

Run `command -v jq`. If it prints nothing, stop and tell the user to install jq, then run `/statuslines:setup` again:

- macOS: `brew install jq`
- Debian or Ubuntu: `sudo apt install jq`
- Windows: `winget install jqlang.jq`

## 2. Copy the script to a fixed place

The script ships with this plugin as `statusline.sh`, two folders above this skill's base directory (`<base directory>/../../statusline.sh`). If it is not there, use the newest `CONFIG_DIR/plugins/cache/statuslines/statuslines/<version>/statusline.sh`.

The plugin's folder changes with every version, so copy the script out instead of pointing at it. If `statusline-plugin.sh` already exists there and does not contain `github.com/Chy-Zaber-Bin-Zahid/`, it is someone else's file: ask the user before overwriting it.

```bash
cp "<path to statusline.sh>" "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline-plugin.sh"
chmod +x "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline-plugin.sh"
```

## 3. Update settings.json

Open `CONFIG_DIR/settings.json` (if it does not exist, create it containing `{}`).

If it already has a `statusLine` whose command is not the one below, show the user the current value and ask before replacing it, so they can switch back later. If it already matches, leave the file alone.

Otherwise set the top-level `statusLine` key to exactly this, keeping every other setting as it is:

```json
"statusLine": {
  "type": "command",
  "command": "bash \"${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline-plugin.sh\""
}
```

Check the file is still valid JSON afterwards (`jq . <file>`).

## 4. Test it

```bash
echo '{"model":{"display_name":"Opus"},"effort":{"level":"high"},"context_window":{"used_percentage":42},"rate_limits":{"five_hour":{"used_percentage":63},"seven_day":{"used_percentage":81}}}' \
  | bash "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/statusline-plugin.sh"
```

It should print one line with the model name and the usage meters (three bars, unless the user's `statusline-plugin.json` changes that). If it prints an error instead, show the error to the user.

## 5. Tell the user

- It is set up, and the new status line appears after their next message.
- The 5-hour and weekly bars appear only on a Claude Pro or Max plan, once the session has had its first reply. With an API key or another provider (Bedrock, Vertex, GLM and so on) they stay hidden.
- If a project's own `.claude/settings.json` sets a `statusLine`, that one wins inside that project.
- After updating the plugin, run `/statuslines:setup` again to copy the new version.
- To change what it shows (hide parts, percentages only, reset times and more), run `/statuslines:configure`, for example `/statuslines:configure percent only, hide git`.
