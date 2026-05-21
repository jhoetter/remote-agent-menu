#!/usr/bin/env bash
set -euo pipefail

# ============================================================
#  AI AGENT MENU
#  - fzf-based UI (live filter + arrow nav + preview), with a
#    plain-numbered fallback when fzf is not installed.
# ============================================================

REPO="$HOME/code/bim-ai"
CLAUDE_CMD="claude --dangerously-skip-permissions"
CODEX_CMD="codex --dangerously-bypass-approvals-and-sandbox"

# Aktuelles Arbeitsverzeichnis des Menüs. Neue Sessions starten hier.
if [ -d "$REPO" ]; then
  CWD="$REPO"
else
  CWD="$HOME"
fi

# ---------- Farben ----------
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
  C_RESET="$(tput sgr0)"
  C_DIM="$(tput dim)"
  C_BOLD="$(tput bold)"
  C_ORANGE="$(tput setaf 208 2>/dev/null || tput setaf 3)"
  C_CYAN="$(tput setaf 51 2>/dev/null || tput setaf 6)"
  C_GREEN="$(tput setaf 42 2>/dev/null || tput setaf 2)"
  C_GREY="$(tput setaf 245 2>/dev/null || tput setaf 7)"
else
  C_RESET=""; C_DIM=""; C_BOLD=""; C_ORANGE=""; C_CYAN=""; C_GREEN=""; C_GREY=""
fi

HAS_FZF=0
if command -v fzf >/dev/null 2>&1; then
  HAS_FZF=1
fi

# ============================================================
#  Helpers
# ============================================================

sanitize() {
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed -E 's/[^a-z0-9._-]+/-/g; s/^-+|-+$//g'
}

human_time() {
  local ts="$1"
  if [ -z "$ts" ] || [ "$ts" = "0" ]; then
    echo "unknown"
  else
    date -d "@$ts" "+%Y-%m-%d %H:%M:%S"
  fi
}

session_rows() {
  tmux list-sessions -F "#{session_name}|#{session_attached}|#{session_windows}|#{session_activity}" 2>/dev/null || true
}

session_count() {
  session_rows | grep -c . || true
}

# Kürzt einen Pfad für die Anzeige: $HOME -> ~
pretty_path() {
  local p="$1"
  echo "${p/#$HOME/\~}"
}

# ============================================================
#  Header / Logo / Statuszeile
# ============================================================

draw_header() {
  local cwd_disp count branch
  cwd_disp="$(pretty_path "$CWD")"
  count="$(session_count)"

  branch=""
  if git -C "$CWD" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch="$(git -C "$CWD" branch --show-current 2>/dev/null || true)"
  fi

  echo
  echo "${C_ORANGE}  ╭───────────────────────────────────────────────────────╮${C_RESET}"
  echo "${C_ORANGE}  │${C_RESET}   ${C_BOLD}${C_CYAN}▐▛███▜▌${C_RESET}    ${C_BOLD}A I   A G E N T   M E N U${C_RESET}                ${C_ORANGE}│${C_RESET}"
  echo "${C_ORANGE}  │${C_RESET}  ${C_BOLD}${C_CYAN}▝▜█████▛▘${C_RESET}   ${C_DIM}claude · codex · tmux${C_RESET}                    ${C_ORANGE}│${C_RESET}"
  echo "${C_ORANGE}  │${C_RESET}    ${C_BOLD}${C_CYAN}▘▘ ▝▝${C_RESET}                                              ${C_ORANGE}│${C_RESET}"
  echo "${C_ORANGE}  ╰───────────────────────────────────────────────────────╯${C_RESET}"
  printf "   ${C_GREY}cwd${C_RESET} ${C_GREEN}%s${C_RESET}" "$cwd_disp"
  if [ -n "$branch" ]; then
    printf "  ${C_GREY}·${C_RESET} ${C_ORANGE} %s${C_RESET}" "$branch"
  fi
  printf "  ${C_GREY}·${C_RESET} ${C_CYAN}%s session(s)${C_RESET}\n" "$count"
  echo
}

# ============================================================
#  Session-Aktionen
# ============================================================

start_agent() {
  local type="$1"
  local cmd="$2"

  echo
  read -rp "Session name suffix (empty = auto): " suffix

  if [ -z "$suffix" ]; then
    suffix="$(date +%m%d-%H%M%S)"
  else
    suffix="$(sanitize "$suffix")"
  fi

  local name="${type}-${suffix}"

  if tmux has-session -t "$name" 2>/dev/null; then
    echo "Session exists -> attaching: $name"
    tmux attach -t "$name"
    return
  fi

  tmux new-session -d -s "$name" -c "$CWD"
  tmux send-keys -t "$name" "$cmd" C-m

  echo "Started session: $name  (cwd: $(pretty_path "$CWD"))"
  tmux attach -t "$name"
}

# Wählt EINE Session per fzf (oder Fallback). Setzt SELECTED_NAME.
pick_one_session() {
  local rows
  rows="$(session_rows)"
  if [ -z "$rows" ]; then
    echo "No tmux sessions."
    return 1
  fi

  if [ "$HAS_FZF" -eq 1 ]; then
    local chosen
    chosen="$(
      echo "$rows" | awk -F'|' '{
        state = ($2=="0") ? "detached" : "attached";
        printf "%-32s  %-9s  win:%s\n", $1, state, $3
      }' | fzf \
        --ansi --height=40% --reverse --border=rounded \
        --prompt="session > " \
        --header="select a session" \
        --preview-window=right:45%:wrap \
        --preview='n=$(echo {} | awk "{print \$1}"); tmux capture-pane -ept "$n" 2>/dev/null | tail -n 40 || echo "(no preview)"'
    )" || return 1
    [ -z "$chosen" ] && return 1
    SELECTED_NAME="$(echo "$chosen" | awk '{print $1}')"
  else
    mapfile -t SESSIONS < <(echo "$rows")
    local i=1
    for row in "${SESSIONS[@]}"; do
      IFS="|" read -r name attached windows activity <<< "$row"
      local state; [ "$attached" = "0" ] && state="detached" || state="attached"
      printf "%2d) %-32s %-10s windows=%s last=%s\n" "$i" "$name" "$state" "$windows" "$(human_time "$activity")"
      i=$((i+1))
    done
    read -rp "Choose session number: " idx
    [[ "$idx" =~ ^[0-9]+$ ]] || { echo "Invalid."; return 1; }
    [ "$idx" -ge 1 ] && [ "$idx" -le "${#SESSIONS[@]}" ] || { echo "Out of range."; return 1; }
    IFS="|" read -r SELECTED_NAME _ <<< "${SESSIONS[$((idx-1))]}"
  fi
}

# Wählt MEHRERE Sessions per fzf (TAB = multi-select). Setzt SELECTED_NAMES[].
pick_multiple_sessions() {
  local rows
  rows="$(session_rows)"
  if [ -z "$rows" ]; then
    echo "No tmux sessions."
    return 1
  fi

  SELECTED_NAMES=()

  if [ "$HAS_FZF" -eq 1 ]; then
    local chosen
    chosen="$(
      echo "$rows" | awk -F'|' '{
        state = ($2=="0") ? "detached" : "attached";
        printf "%-32s  %-9s  win:%s\n", $1, state, $3
      }' | fzf \
        --ansi --multi --height=40% --reverse --border=rounded \
        --prompt="kill > " \
        --header="TAB = mark multiple . ENTER = confirm" \
        --preview-window=right:45%:wrap \
        --preview='n=$(echo {} | awk "{print \$1}"); tmux capture-pane -ept "$n" 2>/dev/null | tail -n 40 || echo "(no preview)"'
    )" || return 1
    [ -z "$chosen" ] && return 1
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      SELECTED_NAMES+=("$(echo "$line" | awk '{print $1}')")
    done <<< "$chosen"
  else
    mapfile -t SESSIONS < <(echo "$rows")
    local i=1
    for row in "${SESSIONS[@]}"; do
      IFS="|" read -r name _ <<< "$row"
      printf "%2d) %s\n" "$i" "$name"; i=$((i+1))
    done
    echo "Examples: 1,3,5  or  1-4  or  all  or  detached"
    read -rp "Selection: " selection
    if [ "$selection" = "all" ]; then
      for row in "${SESSIONS[@]}"; do IFS="|" read -r n _ <<< "$row"; SELECTED_NAMES+=("$n"); done
    elif [ "$selection" = "detached" ]; then
      for row in "${SESSIONS[@]}"; do IFS="|" read -r n a _ <<< "$row"; [ "$a" = "0" ] && SELECTED_NAMES+=("$n"); done
    else
      IFS="," read -ra parts <<< "$selection"
      for part in "${parts[@]}"; do
        part="$(echo "$part" | xargs)"
        if [[ "$part" =~ ^([0-9]+)-([0-9]+)$ ]]; then
          for ((j=${BASH_REMATCH[1]}; j<=${BASH_REMATCH[2]}; j++)); do
            [ "$j" -ge 1 ] && [ "$j" -le "${#SESSIONS[@]}" ] && { IFS="|" read -r n _ <<< "${SESSIONS[$((j-1))]}"; SELECTED_NAMES+=("$n"); }
          done
        elif [[ "$part" =~ ^[0-9]+$ ]]; then
          [ "$part" -ge 1 ] && [ "$part" -le "${#SESSIONS[@]}" ] && { IFS="|" read -r n _ <<< "${SESSIONS[$((part-1))]}"; SELECTED_NAMES+=("$n"); }
        fi
      done
    fi
  fi
}

attach_session() {
  pick_one_session || return
  tmux attach -t "$SELECTED_NAME"
}

kill_one_session() {
  pick_one_session || return
  read -rp "Kill '$SELECTED_NAME'? (y/N): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    tmux kill-session -t "$SELECTED_NAME"
    echo "Killed: $SELECTED_NAME"
  fi
}

kill_multiple_sessions() {
  pick_multiple_sessions || return
  if [ "${#SELECTED_NAMES[@]}" -eq 0 ]; then
    echo "No sessions selected."; return
  fi
  echo; echo "Will kill:"; printf " - %s\n" "${SELECTED_NAMES[@]}"; echo
  read -rp "Confirm kill? (y/N): " confirm
  if [[ "$confirm" =~ ^[Yy]$ ]]; then
    for name in "${SELECTED_NAMES[@]}"; do
      tmux kill-session -t "$name" 2>/dev/null || true
      echo "Killed: $name"
    done
  fi
}

show_sessions_overview() {
  local rows; rows="$(session_rows)"
  if [ -z "$rows" ]; then echo "No tmux sessions."; return; fi
  echo; echo "${C_BOLD}=== TMUX SESSIONS ===${C_RESET}"; echo
  local i=1
  while IFS="|" read -r name attached windows activity; do
    [ -z "$name" ] && continue
    local state; [ "$attached" = "0" ] && state="detached" || state="attached"
    printf "%2d) %-32s %-10s windows=%s last=%s\n" "$i" "$name" "$state" "$windows" "$(human_time "$activity")"
    i=$((i+1))
  done <<< "$rows"
  echo
}

# ============================================================
#  Verzeichnis / Shell
# ============================================================

resolve_dir() {
  local target="$1"
  [ -z "$target" ] && { echo ""; return; }
  [ "$target" = "-" ] && target="$REPO"
  [ "$target" = "~" ] && target="$HOME"
  target="${target/#\~/$HOME}"
  if [[ "$target" != /* ]]; then target="$CWD/$target"; fi
  if [ -d "$target" ]; then ( cd "$target" && pwd ); else echo ""; fi
}

change_dir() {
  if [ "$HAS_FZF" -eq 1 ]; then
    local choice
    choice="$(
      {
        echo ".. (up)"
        echo "~ (home)"
        echo "- (repo)"
        find "$CWD" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort | sed "s#^$CWD/#./#"
      } | fzf --ansi --height=50% --reverse --border=rounded \
            --prompt="cd > " \
            --header="pick a dir . or type a path . esc cancels" \
            --print-query | tail -n 1
    )" || return

    [ -z "$choice" ] && return
    case "$choice" in
      ".. (up)")   choice=".." ;;
      "~ (home)")  choice="~" ;;
      "- (repo)")  choice="$REPO" ;;
    esac
    local resolved; resolved="$(resolve_dir "$choice")"
    if [ -n "$resolved" ]; then CWD="$resolved"; echo "Now in: $(pretty_path "$CWD")"; else echo "Not a directory: $choice"; fi
  else
    echo; echo "Current dir: $(pretty_path "$CWD")"
    echo "Path (rel/abs) . ~ home . - repo . empty cancel"
    read -rp "cd " target
    if [ -z "$target" ]; then return; fi
    local resolved; resolved="$(resolve_dir "$target")"
    if [ -n "$resolved" ]; then CWD="$resolved"; echo "Now in: $(pretty_path "$CWD")"; else echo "Not a directory: $target"; fi
  fi
}

run_shell() {
  echo
  echo "${C_BOLD}=== SHELL${C_RESET} ${C_DIM}(cwd: $(pretty_path "$CWD"))${C_RESET}"
  echo "${C_DIM}Run git pull, ls, etc. 'cd <dir>' moves the menu. 'exit' returns.${C_RESET}"
  echo
  while true; do
    read -erp "${C_GREEN}[$(pretty_path "$CWD")]${C_RESET}$ " line || break
    [ -z "${line// }" ] && continue
    if [ "$line" = "exit" ] || [ "$line" = "quit" ]; then break; fi
    if [[ "$line" == cd ]] || [[ "$line" == cd\ * ]]; then
      local dest="${line#cd}"; dest="$(echo "$dest" | xargs)"
      [ -z "$dest" ] && dest="$HOME"
      local resolved; resolved="$(resolve_dir "$dest")"
      if [ -n "$resolved" ]; then CWD="$resolved"; else echo "Not a directory: $dest"; fi
      continue
    fi
    ( cd "$CWD" && eval "$line" ) || echo "(exit code $?)"
  done
}

# ============================================================
#  Hauptmenü
# ============================================================

MENU_ITEMS=(
  "▶  New Claude session	claude"
  "▶  New Codex session	codex"
  "⚲  Attach session	attach"
  "✕  Kill one session	kill1"
  "✕✕ Kill multiple sessions	killN"
  "≡  Session overview	overview"
  "⌘  Change directory (cd)	cd"
  "❯_ Shell (git pull, ls, …)	shell"
  "⏻  Exit	exit"
)

menu_select() {
  if [ "$HAS_FZF" -eq 1 ]; then
    local line
    line="$(
      printf '%s\n' "${MENU_ITEMS[@]}" \
        | fzf --ansi --with-nth=1 --delimiter='\t' \
              --height=60% --reverse --border=rounded \
              --prompt="> " \
              --header="AI AGENT MENU - type to filter, arrows to move, enter to run" \
              --preview-window=right:40%:wrap \
              --preview='echo {} | cut -f1; echo; echo "---"; echo "Press enter to run this action."'
    )" || { echo "exit"; return; }
    [ -z "$line" ] && { echo "exit"; return; }
    printf '%s' "$line" | cut -f2
  else
    local i=1
    for item in "${MENU_ITEMS[@]}"; do
      printf "%2d) %s\n" "$i" "$(printf '%s' "$item" | cut -f1)"
      i=$((i+1))
    done
    read -rp "Choose: " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#MENU_ITEMS[@]}" ]; then
      printf '%s' "${MENU_ITEMS[$((choice-1))]}" | cut -f2
    else
      echo "invalid"
    fi
  fi
}

while true; do
  clear
  draw_header
  if [ "$HAS_FZF" -eq 0 ]; then
    echo "${C_DIM}(install 'fzf' for the fancy live-filter UI)${C_RESET}"; echo
  fi

  action="$(menu_select)"

  case "$action" in
    claude)   start_agent "claude" "$CLAUDE_CMD" || true ;;
    codex)    start_agent "codex" "$CODEX_CMD" || true ;;
    attach)   attach_session || true ;;
    kill1)    kill_one_session || true; read -rp "Press enter..." ;;
    killN)    kill_multiple_sessions || true; read -rp "Press enter..." ;;
    overview) show_sessions_overview || true; read -rp "Press enter..." ;;
    cd)       change_dir || true; read -rp "Press enter..." ;;
    shell)    run_shell || true ;;
    exit)     clear; echo "bye"; exit 0 ;;
    invalid)  echo "Invalid option"; sleep 1 ;;
    *)        sleep 1 ;;
  esac
done
