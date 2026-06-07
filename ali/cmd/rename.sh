#!/bin/bash

cmd_rename() {
  local old_name=$1
  local new_name=$2
  local old_path new_path

  if [[ -z "$old_name" ]]; then
    ui_prompt_read old_name "Current command name"
  fi

  if [[ -z "$new_name" ]]; then
    ui_prompt_read new_name "New command name"
  fi

  if [[ -z "$old_name" || -z "$new_name" ]]; then
    ui_say warn 'Aborted.'
    return 1
  fi

  if [[ ! "$new_name" =~ ^[A-Za-z0-9_-]+$ ]]; then
    ui_say err 'Invalid new name.'
    return 1
  fi

  if ! registry_name_exists "$old_name"; then
    ui_say err "$old_name is not registered."
    return 1
  fi

  old_path=$(registry_script_path_for "$old_name" 2>/dev/null || true)
  new_path="${ALIASES_DIR}/${new_name}.sh"

  if [[ -n "$old_path" && -f "$old_path" && "$old_path" != "$new_path" ]]; then
    if [[ -e "$new_path" ]]; then
      ui_say err "Target script already exists: $new_path"
      return 1
    fi
    mv "$old_path" "$new_path"
    ui_say ok "Renamed script $old_path → $new_path"
    registry_remove "$old_name"
    registry_add_alias "$new_name" "$new_path"
  else
    registry_update_name "$old_name" "$new_name"
    ui_say ok "Renamed registry entry $old_name → $new_name"
  fi
}
