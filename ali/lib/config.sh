#!/bin/bash
# Shared paths for the ali tool.

: "${ALI_HOME:?ALI_HOME must be set by the entrypoint}"
: "${HOME:?HOME must be set}"

ALI_CONFIG_DIR="${XDG_CONFIG_HOME:-${HOME}/.config}/ali"
ALI_CONFIG_FILE="${ALI_CONFIG_DIR}/config"

REGISTRY="${REGISTRY:-${HOME}/alias_registry.sh}"
ALIASES_DIR="${ALIASES_DIR:-${HOME}/aliases}"
BACKUP_DIR="${BACKUP_DIR:-${HOME}/Dev/my_arch_mods/alias_registry}"
ALI_CMD_DIR="${ALI_HOME}/cmd"
ALI_LIB_DIR="${ALI_HOME}/lib"

# Scripts managed by ali itself — excluded from orphan scans.
ALI_INTERNAL_PATHS=(
  "${ALIASES_DIR}/ali.sh"
  "${ALI_HOME}"
)

ali_config_normalize_path() {
  local p=$1
  if [[ "$p" == ~ ]]; then
    p=$HOME
  elif [[ "$p" == ~/* ]]; then
    p="${HOME}/${p:2}"
  fi
  printf '%s' "$p"
}

ali_config_refresh_internal_paths() {
  ALI_INTERNAL_PATHS=(
    "${ALIASES_DIR}/ali.sh"
    "${ALI_HOME}"
  )
}

ali_config_load() {
  if [[ ! -f "$ALI_CONFIG_FILE" ]]; then
    return 0
  fi
  # shellcheck source=/dev/null
  source "$ALI_CONFIG_FILE"
  REGISTRY=$(ali_config_normalize_path "$REGISTRY")
  ALIASES_DIR=$(ali_config_normalize_path "$ALIASES_DIR")
  BACKUP_DIR=$(ali_config_normalize_path "$BACKUP_DIR")
  ali_config_refresh_internal_paths
}

ali_config_save() {
  mkdir -p "$ALI_CONFIG_DIR" || return 1
  cat >"$ALI_CONFIG_FILE" <<EOF
# ALI user config — edit via \`ali\` → Config or \`ali config\`
REGISTRY=$(printf '%q' "$REGISTRY")
ALIASES_DIR=$(printf '%q' "$ALIASES_DIR")
BACKUP_DIR=$(printf '%q' "$BACKUP_DIR")
EOF
}

ali_config_set_registry() {
  REGISTRY=$(ali_config_normalize_path "$1")
  ali_config_refresh_internal_paths
  ali_config_save
}

ali_config_set_aliases_dir() {
  ALIASES_DIR=$(ali_config_normalize_path "$1")
  ali_config_refresh_internal_paths
  ali_config_save
}

ali_config_set_backup_dir() {
  BACKUP_DIR=$(ali_config_normalize_path "$1")
  ali_config_save
}

ali_config_tilde() {
  local p=$1
  if [[ "$p" == "$HOME" ]]; then
    printf '~'
  elif [[ "$p" == "$HOME"/* ]]; then
    printf '~/%s' "${p#$HOME/}"
  else
    printf '%s' "$p"
  fi
}

ali_config_bashrc_lines() {
  local reg scripts backup ali_sh
  reg=$(ali_config_tilde "$REGISTRY")
  scripts=$(ali_config_tilde "$ALIASES_DIR")
  backup=$(ali_config_tilde "$BACKUP_DIR")
  ali_sh=$(ali_config_tilde "${ALIASES_DIR}/ali.sh")

  printf '%s\n' \
    '# === Aliases ===' \
    "export REGISTRY=\"${reg}\"" \
    "export ALIASES_DIR=\"${scripts}\"" \
    "export BACKUP_DIR=\"${backup}\"" \
    "source \"\${REGISTRY}\"" \
    '' \
    '# Register ALI itself (add this line to your registry once):' \
    "alias ali='${ali_sh} \"\$@\"'" \
    '' \
    '# PS1 is optional — it only customizes your shell prompt and is' \
    '# not required for aliases or ALI. Example:' \
    "# PS1='[\\u@\\h \\W]\\$ '"
}

ali_config_load
