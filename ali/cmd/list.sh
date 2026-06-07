#!/bin/bash

cmd_list() {
  local name type path count=0
  local fg muted accent ok warn err

  if [[ -t 1 ]]; then
    fg=$(tui_rgb_fg "${TUI_TEXT[@]}")
    muted=$(tui_rgb_fg "${TUI_MUTED[@]}")
    accent=$(tui_rgb_fg "${TUI_ACCENT[@]}")
    ok=$(tui_rgb_fg "${TUI_SUCCESS[@]}")
    warn=$(tui_rgb_fg "${TUI_WARN[@]}")
    err=$(tui_rgb_fg "${TUI_ERROR[@]}")
    printf '\n%b  ali · registered commands%b\n\n' "$accent$TUI_BOLD" "$TUI_RESET"
  else
    fg='' muted='' accent='' ok='' warn='' err='' TUI_RESET=''
    printf 'ali · registered commands\n\n'
  fi

  if ! registry_file_exists; then
    printf '%bRegistry not found:%b %s\n' "$C_ERROR" "$C_RESET" "$REGISTRY"
    return 1
  fi

  while IFS= read -r name; do
    type=$(registry_entry_type "$name")
    path=$(registry_script_path_for "$name" 2>/dev/null || echo "?")
    count=$((count + 1))

    if [[ -t 1 ]]; then
      printf '  %b%-16s%b %b%-8s%b  %s  ' \
        "$accent" "$name" "$TUI_RESET" \
        "$muted" "$type" "$TUI_RESET" \
        "$path"
      if [[ -f "$path" && -x "$path" ]]; then
        printf '%b+%b\n' "$ok" "$TUI_RESET"
      elif [[ ! -f "$path" ]]; then
        printf '%bx%b\n' "$err" "$TUI_RESET"
      else
        printf '%b!%b\n' "$warn" "$TUI_RESET"
      fi
    else
      printf '%-16s %-8s  %s\n' "$name" "$type" "$path"
    fi
  done < <(registry_list_names)

  printf '\n'
  [[ -t 1 ]] && printf '%b  %d registered%b\n\n' "$muted" "$count" "$TUI_RESET"
}
