#!/bin/bash
# Read and write ~/alias_registry.sh.

# Avoid the user's `grep` alias breaking registry parsing.
_rg() { command grep "$@"; }

registry_file_exists() {
  [[ -f "$REGISTRY" ]]
}

# Enabled entries only (active in shell).
registry_list_names() {
  local names=()

  while IFS= read -r line; do
    [[ "$line" =~ ^alias[[:space:]]+([^=[:space:]]+)= ]] || continue
    names+=("${BASH_REMATCH[1]}")
  done < "$REGISTRY"

  while IFS= read -r line; do
    [[ "$line" =~ ^([[:alnum:]_-]+)\(\)[[:space:]]*\{ ]] || continue
    names+=("${BASH_REMATCH[1]}")
  done < "$REGISTRY"

  if ((${#names[@]})); then
    printf '%s\n' "${names[@]}" | sort -u
  fi
}

# All entries including commented-out (disabled) ones.
registry_list_all_names() {
  local names=()

  while IFS= read -r line; do
    [[ "$line" =~ ^#?[[:space:]]*alias[[:space:]]+([^=[:space:]]+)= ]] || continue
    names+=("${BASH_REMATCH[1]}")
  done < "$REGISTRY"

  while IFS= read -r line; do
    [[ "$line" =~ ^#?[[:space:]]*([[:alnum:]_-]+)\(\)[[:space:]]*\{ ]] || continue
    names+=("${BASH_REMATCH[1]}")
  done < "$REGISTRY"

  if ((${#names[@]})); then
    printf '%s\n' "${names[@]}" | sort -u
  fi
}

registry_entry_enabled() {
  local name=$1

  if _rg -qE "^alias[[:space:]]+${name}=" "$REGISTRY" 2>/dev/null; then
    return 0
  fi
  if _rg -qE "^${name}\(\)[[:space:]]*\{" "$REGISTRY" 2>/dev/null; then
    return 0
  fi
  return 1
}

registry_entry_type() {
  local name=$1
  if _rg -qE "^#?[[:space:]]*alias[[:space:]]+${name}=" "$REGISTRY" 2>/dev/null; then
    echo alias
  elif _rg -qE "^#?[[:space:]]*${name}\(\)[[:space:]]*\{" "$REGISTRY" 2>/dev/null; then
    echo function
  else
    echo unknown
  fi
}

registry_get_line() {
  local name=$1
  _rg -E "^#?[[:space:]]*alias[[:space:]]+${name}=" "$REGISTRY" 2>/dev/null \
    || _rg -E "^#?[[:space:]]*${name}\(\)[[:space:]]*\{" "$REGISTRY" 2>/dev/null \
    || true
}

registry_script_path_for() {
  local name=$1
  local line path fragment esc_dir

  line=$(registry_get_line "$name")
  [[ -n "$line" ]] || return 1

  line=${line## }
  line=${line#\#}

  esc_dir=${ALIASES_DIR//\//\\/}
  path=$(sed -n "s|.*\\(${esc_dir}/[^ ;'\\\"]*\\.sh\\).*|\1|p" <<< "$line")

  if [[ -z "$path" && "$line" == *'~/aliases/'* ]]; then
    fragment=${line#*~/aliases/}
    fragment=${fragment%%[\"\'\ ;]*}
    path="${ALIASES_DIR}/${fragment}"
  fi

  if [[ -z "$path" && "$line" == *'$HOME/aliases/'* ]]; then
    fragment=${line#*\$HOME/aliases/}
    fragment=${fragment%%[\"\'\ ;]*}
    path="${ALIASES_DIR}/${fragment}"
  fi

  [[ -n "$path" ]] || return 1
  printf '%s\n' "$path"
}

registry_name_exists() {
  local name=$1 n
  while IFS= read -r n; do
    [[ "$n" == "$name" ]] && return 0
  done < <(registry_list_all_names)
  return 1
}

registry_add_alias() {
  local name=$1
  local script_path=$2

  if registry_name_exists "$name"; then
    echo "Command '$name' already exists in the registry." >&2
    return 1
  fi

  printf "alias %s='%s \"\$@\"'\n" "$name" "$script_path" >> "$REGISTRY"
}

registry_remove() {
  local name=$1
  local tmp

  if ! registry_name_exists "$name"; then
    echo "Command '$name' not found in the registry." >&2
    return 1
  fi

  tmp=$(mktemp)
  _rg -Ev "^#?[[:space:]]*alias[[:space:]]+${name}=" "$REGISTRY" \
    | _rg -Ev "^#?[[:space:]]*${name}\(\)[[:space:]]*\{" > "$tmp"
  mv "$tmp" "$REGISTRY"
}

registry_set_enabled() {
  local name=$1
  local enable=$2
  local tmp line found=0

  if ! registry_name_exists "$name"; then
    echo "Command '$name' not found in the registry." >&2
    return 1
  fi

  tmp=$(mktemp)
  if (( enable )); then
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^#[[:space:]]*(alias[[:space:]]+${name}=|${name}\(\)[[:space:]]*\{) ]] \
        || [[ "$line" =~ ^#(alias[[:space:]]+${name}=|${name}\(\)[[:space:]]*\{) ]]; then
        line="${line#\# }"
        line="${line#\#}"
        found=1
      fi
      printf '%s\n' "$line"
    done < "$REGISTRY" > "$tmp"
  else
    while IFS= read -r line || [[ -n "$line" ]]; do
      if [[ "$line" =~ ^alias[[:space:]]+${name}= ]] \
        || [[ "$line" =~ ^${name}\(\)[[:space:]]*\{ ]]; then
        printf '# %s\n' "$line"
        found=1
      else
        printf '%s\n' "$line"
      fi
    done < "$REGISTRY" > "$tmp"
  fi

  if (( ! found )); then
    rm -f "$tmp"
    echo "Could not toggle '$name' in the registry." >&2
    return 1
  fi

  mv "$tmp" "$REGISTRY"
}

registry_toggle_enabled() {
  local name=$1

  if registry_entry_enabled "$name"; then
    registry_set_enabled "$name" 0
  else
    registry_set_enabled "$name" 1
  fi
}

registry_update_name() {
  local old_name=$1
  local new_name=$2
  local tmp line

  if ! registry_name_exists "$old_name"; then
    echo "Command '$old_name' not found in the registry." >&2
    return 1
  fi

  if registry_name_exists "$new_name"; then
    echo "Command '$new_name' already exists in the registry." >&2
    return 1
  fi

  tmp=$(mktemp)
  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^#?[[:space:]]*alias[[:space:]]+${old_name}= ]]; then
      line=${line/${old_name}/$new_name}
    elif [[ "$line" =~ ^#?[[:space:]]*${old_name}\(\)[[:space:]]*\{ ]]; then
      line=${line/$old_name()/$new_name()}
    fi
    printf '%s\n' "$line"
  done < "$REGISTRY" > "$tmp"
  mv "$tmp" "$REGISTRY"
}
