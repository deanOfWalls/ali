#!/bin/bash

cmd_new() {
  local name=$1
  local script_path

  if [[ -z "$name" ]]; then
    ui_prompt_read name "Command name"
  fi

  if [[ -z "$name" ]]; then
    ui_say warn 'Aborted.'
    return 1
  fi

  if [[ ! "$name" =~ ^[A-Za-z0-9_-]+$ ]]; then
    ui_say err 'Invalid name. Use letters, numbers, hyphens, underscores.'
    return 1
  fi

  script_path="${ALIASES_DIR}/${name}.sh"

  if registry_name_exists "$name"; then
    ui_say err "$name is already registered."
    return 1
  fi

  if [[ -f "$script_path" ]]; then
    ui_say warn "Script already exists: $script_path"
    if ! ui_confirm "Register existing script as '$name'?"; then
      return 1
    fi
  else
    printf '#!/bin/bash\n' > "$script_path"
    chmod +x "$script_path"
    ui_say ok "Created $script_path"
  fi

  registry_add_alias "$name" "$script_path"
  scripts_chmod_all

  ui_say ok "Registered $name → $script_path"
  ui_say muted 'Edit the script, then run ali refresh to load it.'

  if [[ -n "${EDITOR:-}" ]] && ui_confirm "Open in \$EDITOR ($EDITOR)?"; then
    tui_suspend_for_external
    "$EDITOR" "$script_path"
    tui_resume_from_external
    if (( TUI_SCREEN )); then
      tui_screen_open "$TUI_SCREEN_TITLE"
    fi
  fi
}
