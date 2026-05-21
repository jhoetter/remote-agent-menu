# remote-agent-menu

A fancy `fzf`-powered tmux launcher for AI coding agents (Claude Code, Codex).
Built to be used over SSH/tmux/Tailscale on a remote machine.

## Features

- Live-filter menu (type to filter, arrow keys, enter) — falls back to a
  plain numbered menu if `fzf` is not installed
- Start Claude / Codex sessions in tmux, each in your chosen working directory
- Attach to or kill sessions, with a live preview of each session's pane
- Built-in `cd` and a mini-shell (run `git pull`, `ls`, etc. before launching)
- Header showing current dir, git branch, and number of running sessions

## Requirements

- `bash`, `tmux`, `git`
- `fzf` (optional but recommended — without it you get a plain numbered menu)
- `claude` and/or `codex` CLIs on your `PATH`

On Ubuntu/Debian:

```bash
sudo apt update && sudo apt install -y tmux git fzf
```

## Install

```bash
git clone https://github.com/jhoetter/remote-agent-menu.git
cd remote-agent-menu
chmod +x menu.sh
```

Optionally put it on your `PATH` so you can run it from anywhere:

```bash
sudo ln -s "$(pwd)/menu.sh" /usr/local/bin/agent-menu
```

## Usage

```bash
./menu.sh
# or, if symlinked:
agent-menu
```

## Configuration

Edit the variables at the top of `menu.sh`:

- `REPO` — default working directory the menu starts in
- `CLAUDE_CMD` / `CODEX_CMD` — the commands launched for each agent type

## Notes

The built-in shell option uses `eval` and runs with your full permissions.
It's meant for personal tooling — don't paste commands into it you don't trust.
