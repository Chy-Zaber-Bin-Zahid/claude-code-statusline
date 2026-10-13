# Statusline

A compact status line for [Claude Code](https://github.com/anthropics/claude-code) that shows how full your context window is and how much of your 5-hour and weekly limits you've used, so you don't have to keep opening the usage page.

![Statusline at light, busy and heavy usage](assets/preview.svg)

Three bars side by side are easy to mix up, so each one has its own shape: **blocks** for context, **squares** for the 5-hour limit and **dots** for the weekly limit.

## What it shows

| Part | Example | What it means |
| --- | --- | --- |
| Folder | `my-app` | The folder Claude Code is working in |
| Branch | `⎇ main` | Your git branch. It turns yellow with a count, like `⎇ main*3`, when you have uncommitted changes |
| Model | `Opus 5.5 high` | The model and its effort level |
| Context | `ctx ██░░░░░░░░ 24%` | How full the context window is |
| 5-hour limit | `5h ■■■■■■□□□□ 64%` | How much of your 5-hour usage limit you've used |
| Weekly limit | `week ●●●●○○○○○○ 41%` | How much of your weekly usage limit you've used |

Bars are green below 50%, yellow from 50% and red from 80%.

## Install

In Claude Code, run:

```
/plugin install statusline --marketplace Chy-Zaber-Bin-Zahid/statusline
```

Answer `y` to add the marketplace, then choose where to install it (User is the default). Then turn it on:

```
/statusline:setup
```

The new status line appears after your next message. If Claude Code says the setup command doesn't exist yet, run `/reload-plugins` and try again.

Type the whole command, `/statusline:setup`. Plain `/statusline` is Claude Code's own built-in command, which asks Claude to write a status line for you.

<details>
<summary>On an older version of Claude Code</summary>

```
/plugin marketplace add Chy-Zaber-Bin-Zahid/statusline
/plugin install statusline@statusline
/statusline:setup
```

</details>

<details>
<summary>Without the plugin system</summary>

Download the script:

```bash
curl -fsSL https://raw.githubusercontent.com/Chy-Zaber-Bin-Zahid/statusline/main/statusline.sh -o ~/.claude/statusline-plugin.sh
```

Then add this to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "bash ~/.claude/statusline-plugin.sh"
  }
}
```

</details>

## Requirements

- Claude Code
- `bash`, `jq` and `git` (git is only used for the branch)
- A Claude subscription (Pro, Max, Team or Enterprise) for the 5-hour and weekly bars. They appear once a session has had its first reply, and stay hidden when you use an API key.

Tested on macOS, including its built-in bash 3.2. It uses only standard tools, so it should work on Linux too. On Windows, use WSL.

## Update

```bash
claude plugin update statusline@statusline
```

Then run `/statusline:setup` again so it copies the new version.

## Uninstall

1. Remove the `statusLine` entry from `~/.claude/settings.json`, or put your old one back.
2. Run `claude plugin uninstall statusline@statusline`.
3. Delete `~/.claude/statusline-plugin.sh`.

## Privacy

The script runs on your computer. It reads only the session data Claude Code passes to it and the git status of your current folder, and it makes no network requests.

## License

[MIT](LICENSE). This is a community project. It isn't made by or affiliated with Anthropic.
