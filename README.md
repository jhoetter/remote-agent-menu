# remote-agent-menu

A fancy `fzf`-powered tmux launcher for AI coding agents (Claude Code, Codex, OpenCode).
Built to be used over SSH/tmux/Tailscale on a remote machine.

## Features

- Live-filter menu (type to filter, arrow keys, enter) — falls back to a
  plain numbered menu if `fzf` is not installed
- Start Claude / Codex / OpenCode sessions in tmux, each in your chosen working directory
- Attach to or kill sessions, with a live preview of each session's pane
- Built-in `cd` and a mini-shell (run `git pull`, `ls`, etc. before launching)
- Header showing current dir, git branch, and number of running sessions

## Requirements

- `bash`, `tmux`, `git`
- `fzf` (optional but recommended — without it you get a plain numbered menu)
- `claude`, `codex`, and/or `opencode` CLIs on your `PATH`

On Ubuntu/Debian:

```bash
sudo apt update && sudo apt install -y tmux git fzf
```

## Install (remote machine)

```bash
git clone https://github.com/jhoetter/remote-agent-menu.git
cd remote-agent-menu
chmod +x menu.sh

# Symlink so it's available everywhere
sudo ln -s "$(pwd)/menu.sh" /usr/local/bin/agent-menu

# Install the clipboard helper (required for Mac clipboard sync)
sudo cp tmux-copy-osc52 /usr/local/bin/
sudo chmod +x /usr/local/bin/tmux-copy-osc52
```

## Usage

```bash
agent-menu
```

Or from your Mac with the local launcher (see Mac setup below):

```bash
launch-agent-menu
```

## Configuration

Edit the variables at the top of `menu.sh`:

- `REPO` — default working directory the menu starts in
- `CLAUDE_CMD` / `CODEX_CMD` / `OPENCODE_CMD` — the commands launched for each agent type

---

## Mac setup (full remote dev workflow)

This setup gives you:

| Shortcut | What it does |
|----------|-------------|
| **⌃⌘S** | Capture a screen region → upload to `ubuntu-dev:/home/jhoetter/shots/` → remote path in Mac clipboard |
| **⌃⌘V** | Paste Mac clipboard into the active tmux pane on `ubuntu-dev` |

### Prerequisites

- SSH to the remote works passwordless. Host alias `ubuntu-dev` is defined in `~/.ssh/config` (Tailscale MagicDNS recommended). ControlMaster multiplexing is strongly recommended so the shortcuts feel instant:

  ```
  Host ubuntu-dev
      HostName ubuntu-dev
      User jhoetter
      ControlMaster auto
      ControlPath /tmp/ssh-%r@%h:%p
      ControlPersist 120
  ```

- [skhd](https://github.com/koekeishiya/formulae) for global hotkeys:

  ```bash
  brew install koekeishiya/formulae/skhd
  ```

- `pngpaste` (used by the screenshot script):

  ```bash
  brew install pngpaste
  ```

### Install Mac scripts

```bash
# Copy the three scripts into ~/bin (or any directory on your PATH)
cp mac/shot2remote-capture mac/paste2remote mac/launch-agent-menu ~/bin/
chmod +x ~/bin/shot2remote-capture ~/bin/paste2remote ~/bin/launch-agent-menu
```

Edit `~/bin/shot2remote-capture` and `~/bin/paste2remote` if your remote host alias or username differ from `ubuntu-dev` / `jhoetter`.

### Configure skhd

Append the contents of `mac/skhdrc.additions` to `~/.skhdrc`:

```bash
cat mac/skhdrc.additions >> ~/.skhdrc
```

Then start (or restart) skhd:

```bash
brew services start skhd
# or, if already running:
launchctl kill SIGHUP gui/$(id -u)/com.koekeishiya.skhd
```

**Important — Accessibility permission**: macOS requires skhd to have Accessibility access before global hotkeys work. The permission prompt often does not appear automatically when skhd runs as a background service. If the shortcuts do nothing:

1. Open **System Settings → Privacy & Security → Accessibility (Bedienungshilfen)**
2. Click **+** and add `/opt/homebrew/Cellar/skhd/<version>/bin/skhd` (the real binary, not the symlink — reveal it with `open -R $(readlink -f $(which skhd))`)
3. Enable the toggle
4. Reload: `launchctl kill SIGHUP gui/$(id -u)/com.koekeishiya.skhd`

Also enable **Input Monitoring** for skhd in the same Privacy & Security panel.

**Screen Recording**: The first time `⌃⌘S` fires, macOS may prompt for Screen Recording permission for `screencapture`. Grant it.

**Warp — OSC 52**: For `⌃⌘V` and clipboard copy from remote tmux to work, enable OSC 52 in Warp: Settings → Features → Terminal → "Allow applications to access clipboard via OSC 52".

### Configure tmux on the remote

Make sure your `~/.tmux.conf` on the remote includes at minimum:

```tmux
set -g mouse on
set -g allow-passthrough on
set -g set-clipboard on
set -g terminal-features "xterm*:clipboard:..."

# Clipboard: mouse-drag selection → Mac clipboard via OSC 52
bind -T copy-mode-vi MouseDragEnd1Pane send -X copy-pipe-no-clear "tmux-copy-osc52"
bind -T copy-mode    MouseDragEnd1Pane send -X copy-pipe-no-clear "tmux-copy-osc52"
```

The `tmux-copy-osc52` script (installed above) handles the OSC 52 emission. After editing `~/.tmux.conf`, reload it inside a running tmux server:

```bash
tmux source-file ~/.tmux.conf
```

### How it works

- **⌃⌘S** runs `~/bin/shot2remote-capture`: takes an interactive screenshot (`screencapture -i`), SCPs the PNG to `/home/jhoetter/shots/` on the remote, and writes the remote path to the Mac clipboard via `pbcopy`. You can then paste the path directly into an AI agent prompt.
- **⌃⌘V** runs `~/bin/paste2remote`: pipes the Mac clipboard through SSH into `tmux load-buffer`, then calls `tmux paste-buffer` to insert it into whatever pane is active. This is more reliable than ⌘V in Warp for large pastes or TUI apps.
- **Mouse-drag in remote tmux** triggers `tmux-copy-osc52`, which base64-encodes the selection and emits an OSC 52 escape sequence. The sequence travels through SSH to Warp, which sets the Mac clipboard — no Cmd+C needed.
- **`launch-agent-menu`** simply runs `ssh -tt ubuntu-dev 'agent-menu'` with a forced TTY so Warp doesn't reject the allocation.
