#!/bin/bash
# Filesystem helpers for ~/aliases.

script_is_internal() {
  local path=$1
  local internal

  [[ "$path" == "${ALIASES_DIR}/ali.sh" ]] && return 0
  [[ "$path" == "${ALI_HOME}"/* ]] && return 0

  for internal in "${ALI_INTERNAL_PATHS[@]}"; do
    [[ "$path" == "$internal" || "$path" == "$internal/"* ]] && return 0
  done

  return 1
}

# All .sh files under ~/aliases, excluding ali internals.
scripts_find_all() {
  local path

  while IFS= read -r -d '' path; do
    script_is_internal "$path" && continue
    printf '%s\n' "$path"
  done < <(find "$ALIASES_DIR" -type f -name '*.sh' -print0 2>/dev/null | sort -z)
}

scripts_chmod_all() {
  find "$ALIASES_DIR" -type f -exec chmod +x {} \;
}

scripts_orphans() {
  local path registered=() name script_path

  while IFS= read -r name; do
    script_path=$(registry_script_path_for "$name" 2>/dev/null || true)
    [[ -n "$script_path" ]] && registered+=("$script_path")
  done < <(registry_list_all_names)

  while IFS= read -r path; do
    local found=0 item
    for item in "${registered[@]}"; do
      [[ "$path" == "$item" ]] && found=1 && break
    done
    (( found )) || printf '%s\n' "$path"
  done < <(scripts_find_all)
}

scripts_git_dirty_count() {
  if git -C "$ALIASES_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ALIASES_DIR" status --porcelain 2>/dev/null | wc -l | tr -d ' '
  else
    echo 0
  fi
}

# Commit ~/aliases working-tree changes after a backup (local repo only).
scripts_git_commit_backup() {
  local when body rc=0

  git -C "$ALIASES_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    printf 'Git: %s is not a git repository (skipped).\n' "$ALIASES_DIR"
    return 0
  }

  body=$(git -C "$ALIASES_DIR" status --porcelain 2>/dev/null)
  if [[ -z "$body" ]]; then
    printf 'Git: working tree clean (nothing to commit).\n'
    return 0
  fi

  when=$(date '+%Y-%m-%d %H:%M:%S')

  git -C "$ALIASES_DIR" add -A || {
    printf 'Git: failed to stage changes.\n' >&2
    return 1
  }

  git -C "$ALIASES_DIR" commit -m "$(cat <<EOF
Alias backup — ${when}

${body}
EOF
)" || rc=$?

  if (( rc )); then
    printf 'Git: commit failed.\n' >&2
    return "$rc"
  fi

  printf 'Git: committed changes in %s at %s\n' "$ALIASES_DIR" "$when"
  return 0
}

scripts_registry_mtime() {
  if [[ -f "$REGISTRY" ]]; then
    stat -c '%Y' "$REGISTRY" 2>/dev/null || stat -f '%m' "$REGISTRY"
  else
    echo 0
  fi
}

scripts_backup_mtime() {
  if [[ -f "${BACKUP_DIR}/alias_registry.sh" ]]; then
    stat -c '%Y' "${BACKUP_DIR}/alias_registry.sh" 2>/dev/null \
      || stat -f '%m' "${BACKUP_DIR}/alias_registry.sh"
  else
    echo 0
  fi
}

scripts_registry_needs_backup() {
  local reg_ts backup_ts
  reg_ts=$(scripts_registry_mtime)
  backup_ts=$(scripts_backup_mtime)
  (( reg_ts > backup_ts ))
}

# Snapshot registry + scripts to BACKUP_DIR (scripts only — not .git).
scripts_backup() {
  local rc=0

  mkdir -p "$BACKUP_DIR" || return 1

  if ! cp "$REGISTRY" "${BACKUP_DIR}/"; then
    printf 'Failed to copy registry to %s\n' "$BACKUP_DIR" >&2
    return 1
  fi

  mkdir -p "${BACKUP_DIR}/aliases"

  if command -v rsync >/dev/null 2>&1; then
    rsync -a --delete --exclude='.git/' "${ALIASES_DIR}/" "${BACKUP_DIR}/aliases/" || rc=$?
  else
    find "${BACKUP_DIR}/aliases" -mindepth 1 -maxdepth 1 ! -name '.git' -exec rm -rf {} + 2>/dev/null || true
    tar -C "$ALIASES_DIR" --exclude='.git' -cf - . \
      | tar -C "${BACKUP_DIR}/aliases" -xf - || rc=$?
  fi

  if (( rc )); then
    printf 'Backup completed with errors (registry saved; some scripts may be missing).\n' >&2
    return "$rc"
  fi

  printf 'Alias Registry backed up to %s\n' "$BACKUP_DIR"

  if ! scripts_git_commit_backup; then
    printf 'Warning: backup saved but git commit failed.\n' >&2
  fi

  return 0
}
