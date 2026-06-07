#!/bin/bash
# Shared terminal UI helpers.

ui_clear() {
  printf '\033[2J\033[H'
}

ui_width() {
  tput cols 2>/dev/null || echo 80
}

ui_header() {
  local title=$1

  if (( TUI_ACTIVE && TUI_SCREEN )); then
    tui_screen_open " $title "
    return 0
  fi

  local width
  width=$(ui_width)

  printf '\n%b%s%b\n' "$C_HEADER_BG" "$(printf ' %.0s' $(seq 1 "$width"))" "$C_RESET"
  printf '%b  %s%b\n' "$C_HEADER_BG" "$title" "$C_RESET"
  printf '%b%s%b\n\n' "$C_HEADER_BG" "$(printf ' %.0s' $(seq 1 "$width"))" "$C_RESET"
}

ui_rule() {
  if (( TUI_ACTIVE && TUI_SCREEN )); then
    tui_screen_rule
    return 0
  fi

  local char=${1:-─}
  local width
  width=$(ui_width)
  printf '%b%s%b\n' "$C_MUTED" "$(printf '%.0s'"$char" $(seq 1 "$width"))" "$C_RESET"
}

ui_status_bar() {
  local registered=$1
  local orphans=$2
  local warnings=$3
  local git_dirty=$4
  local backup_flag=$5

  printf '%b' "$C_MUTED"
  printf ' registered:%s' "$registered"
  printf ' · orphans:%s' "$orphans"
  printf ' · lint:%s' "$warnings"
  printf ' · git dirty:%s' "$git_dirty"
  if (( backup_flag )); then
    printf ' · %bregistry Δ%b' "$C_WARN" "$C_MUTED"
  fi
  printf '%b\n\n' "$C_RESET"
}

ui_say() {
  local style=${1:-text}
  shift
  local msg=$*

  if (( TUI_ACTIVE && TUI_SCREEN )); then
    tui_screen_say "$style" "$msg"
    return 0
  fi

  case "$style" in
    ok|success)
      printf '%b%s%b\n' "$C_SUCCESS" "$msg" "$C_RESET"
      ;;
    err|error)
      printf '%b%s%b\n' "$C_ERROR" "$msg" "$C_RESET"
      ;;
    warn)
      printf '%b%s%b\n' "$C_WARN" "$msg" "$C_RESET"
      ;;
    muted)
      printf '%b%s%b\n' "$C_MUTED" "$msg" "$C_RESET"
      ;;
    accent|primary)
      printf '%b%s%b\n' "$C_PRIMARY" "$msg" "$C_RESET"
      ;;
    *)
      printf '%s\n' "$msg"
      ;;
  esac
}

ui_prompt() {
  local message=$1
  local default=${2:-}
  local reply

  if (( TUI_ACTIVE && TUI_SCREEN )); then
    printf '%bui_prompt: use ui_prompt_read in TUI mode%b\n' "$C_ERROR" "$C_RESET" >&2
    return 1
  fi

  if [[ -n "$default" ]]; then
    printf '%b%s %b[%s]%b: ' "$C_PRIMARY" "$message" "$C_MUTED" "$default" "$C_RESET" >&2
  else
    printf '%b%s%b: ' "$C_PRIMARY" "$message" "$C_RESET" >&2
  fi

  read -r reply
  if [[ -z "$reply" && -n "$default" ]]; then
    reply=$default
  fi
  printf '%s' "$reply"
}

# Set reply by variable name — required in TUI (never use name=$(ui_prompt ...) there).
ui_prompt_read() {
  local __var=$1
  local message=$2
  local default=${3:-}
  local reply=''

  if (( TUI_ACTIVE && TUI_SCREEN )); then
    tui_prompt "$message" "$default"
    reply=$TUI_PROMPT_REPLY
  else
    if [[ -n "$default" ]]; then
      printf '%b%s %b[%s]%b: ' "$C_PRIMARY" "$message" "$C_MUTED" "$default" "$C_RESET" >&2
    else
      printf '%b%s%b: ' "$C_PRIMARY" "$message" "$C_RESET" >&2
    fi
    read -r reply
    if [[ -z "$reply" && -n "$default" ]]; then
      reply=$default
    fi
  fi

  printf -v "$__var" '%s' "$reply"
}

ui_confirm() {
  local message=$1
  local reply

  if (( TUI_ACTIVE && TUI_SCREEN )); then
    tui_confirm "$message"
    return $?
  fi

  printf '%b%s %b[y/N]%b: ' "$C_WARN" "$message" "$C_MUTED" "$C_RESET" >&2
  read -r reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

ui_press_enter() {
  if (( TUI_ACTIVE && TUI_SCREEN )); then
    tui_press_enter
    return 0
  fi

  printf '\n%bPress Enter to continue...%b' "$C_MUTED" "$C_RESET" >&2
  read -r _
}

ui_menu_option() {
  local key=$1
  local label=$2
  printf '  %b[%s]%b %s\n' "$C_ACCENT" "$key" "$C_RESET" "$label"
}

ui_script_status_icon() {
  local path=$1

  if [[ ! -f "$path" ]]; then
    printf '%b✗ missing%b' "$C_ERROR" "$C_RESET"
  elif [[ ! -x "$path" ]]; then
    printf '%b! not executable%b' "$C_WARN" "$C_RESET"
  else
    printf '%b✓%b' "$C_SUCCESS" "$C_RESET"
  fi
}
