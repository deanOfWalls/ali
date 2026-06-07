#!/bin/bash

doctor_count_warnings() {
  cmd_doctor --count-only 2>/dev/null || echo 0
}

cmd_doctor() {
  local count_only=0
  local arg

  for arg in "$@"; do
    case "$arg" in
      --count-only) count_only=1 ;;
    esac
  done

  local warnings=0
  local name path line

  if ! registry_file_exists; then
    if (( count_only )); then
      echo 0
      return 0
    fi
    printf '%bRegistry missing:%b %s\n' "$C_ERROR" "$C_RESET" "$REGISTRY"
    return 1
  fi

  if (( ! count_only )); then
    ui_header "ali · doctor"
    ui_rule
  fi

  while IFS= read -r line; do
    [[ "$line" =~ ^alias[[:space:]]+([^=[:space:]]+)= ]] || continue
    name="${BASH_REMATCH[1]}"
    if [[ "$line" == *'$@'* && "$line" != *'"$@"'* ]]; then
      if (( ! count_only )); then
        printf '  %b⚠%b  %-16s unquoted $@ on alias line\n' \
          "$C_WARN" "$C_RESET" "$name"
      fi
      warnings=$((warnings + 1))
    fi
  done < "$REGISTRY"

  while IFS= read -r name; do
    path=$(registry_script_path_for "$name" 2>/dev/null || true)
    if [[ -z "$path" ]]; then
      if (( ! count_only )); then
        printf '  %b✗%b  %-16s could not parse script path\n' \
          "$C_ERROR" "$C_RESET" "$name"
      fi
      warnings=$((warnings + 1))
      continue
    fi
    if [[ ! -f "$path" ]]; then
      if (( ! count_only )); then
        printf '  %b✗%b  %-16s missing script %s\n' \
          "$C_ERROR" "$C_RESET" "$name" "$path"
      fi
      warnings=$((warnings + 1))
    elif [[ ! -x "$path" ]]; then
      if (( ! count_only )); then
        printf '  %b!%b  %-16s not executable %s\n' \
          "$C_WARN" "$C_RESET" "$name" "$path"
      fi
      warnings=$((warnings + 1))
    fi
  done < <(registry_list_names)

  mapfile -t orphans < <(scripts_orphans)
  for path in "${orphans[@]}"; do
    if (( ! count_only )); then
      printf '  %b○%b  orphan script %s\n' "$C_MUTED" "$C_RESET" "$path"
    fi
    warnings=$((warnings + 1))
  done

  if (( count_only )); then
    echo "$warnings"
    return 0
  fi

  printf '\n'
  if (( warnings == 0 )); then
    printf '%bAll checks passed.%b\n' "$C_SUCCESS" "$C_RESET"
  else
    printf '%b%d issue(s) found.%b\n' "$C_WARN" "$warnings" "$C_RESET"
  fi
}
