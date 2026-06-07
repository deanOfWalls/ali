#!/bin/bash

cmd_remove() {
  local name=$1
  local path line msg

  if [[ -z "$name" ]]; then
    ui_prompt_read name "Command name to remove"
  fi

  if [[ -z "$name" ]]; then
    ui_say warn 'Aborted.'
    return 1
  fi

  if ! registry_name_exists "$name"; then
    ui_say err "$name is not registered."
    return 1
  fi

  path=$(registry_script_path_for "$name" 2>/dev/null || true)
  line=$(registry_get_line "$name")
  [[ -n "$line" ]] && ui_say muted "$line"

  if [[ -n "$path" && -f "$path" ]]; then
    msg="Remove '$name' and delete $path?"
  else
    msg="Remove '$name' from the registry?"
  fi

  if ! ui_confirm "$msg"; then
    ui_say muted 'Aborted.'
    return 1
  fi

  registry_remove "$name"

  if [[ -n "$path" && -f "$path" ]]; then
    rm -f "$path"
    ui_say ok "Removed $name and deleted $path"
  else
    ui_say ok "Removed $name from the registry"
  fi
}
