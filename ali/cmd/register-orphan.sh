#!/bin/bash

cmd_register_orphan() {
  local script_path=$1
  local default_name name

  if [[ -z "$script_path" ]]; then
    ui_header "ali · register orphan script"
    mapfile -t orphans < <(scripts_orphans)

    if ((${#orphans[@]} == 0)); then
      ui_say ok 'No orphan scripts found.'
      return 0
    fi

    local i
    for i in "${!orphans[@]}"; do
      ui_say accent "  [$((i + 1))] ${orphans[$i]}"
    done

    local pick
    ui_prompt_read pick "Select number (or enter full path)"
    if [[ "$pick" =~ ^[0-9]+$ ]] && (( pick >= 1 && pick <= ${#orphans[@]} )); then
      script_path="${orphans[$((pick - 1))]}"
    else
      script_path=$pick
    fi
  fi

  if [[ -z "$script_path" || ! -f "$script_path" ]]; then
    ui_say err 'Script not found.'
    return 1
  fi

  default_name=$(basename "$script_path" .sh)
  ui_prompt_read name "Registry command name" "$default_name"

  if [[ -z "$name" ]]; then
    ui_say warn 'Aborted.'
    return 1
  fi

  if registry_name_exists "$name"; then
    ui_say err "$name is already registered."
    return 1
  fi

  registry_add_alias "$name" "$script_path"
  scripts_chmod_all
  ui_say ok "Registered $name → $script_path"
  ui_say muted 'Run ali refresh to load it.'
}
