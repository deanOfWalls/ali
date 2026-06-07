#!/bin/bash
# ali — alias registry CLI (entrypoint)

set -euo pipefail

export ALI_HOME
ALI_HOME="$(cd "$(dirname "${BASH_SOURCE[0]}")/ali" && pwd)"

source "${ALI_HOME}/lib/config.sh"
source "${ALI_HOME}/lib/colors.sh"
source "${ALI_HOME}/lib/registry.sh"
source "${ALI_HOME}/lib/scripts.sh"
source "${ALI_HOME}/lib/ui.sh"
source "${ALI_HOME}/lib/tui_core.sh"

for lib in "${ALI_CMD_DIR}"/*.sh; do
  source "$lib"
done

cmd_help() {
  ui_header "ali · help"
  cat <<EOF
${C_PRIMARY}Interactive TUI${C_RESET}
  ali                 Open the full-screen menu (or run with no args)

${C_PRIMARY}Status bar${C_RESET}
  registered   enabled commands in ${REGISTRY}
  orphans      scripts under ${ALIASES_DIR} not in registry
  lint         issues from ali doctor (see below)
  git-dirty    uncommitted changes in ${ALIASES_DIR} git repo
  backup ok    registry snapshot is current
  backup stale registry changed since last backup

${C_PRIMARY}CLI commands${C_RESET}  (also available outside the TUI)
  ali list            List registered commands
  ali new <name>      Scaffold script + registry entry
  ali remove <name>   Unregister and delete script
  ali rename <o> <n>  Rename command (and script if applicable)
  ali orphan [path]   Register an unlinked script
  ali doctor          Lint registry + scripts (see below)
  ali refresh         Reload aliases in current shell
  ali backup          Snapshot registry + scripts; commit ~/aliases

${C_PRIMARY}ali doctor${C_RESET}  (built into ALI — not an external tool)
  Checks enabled registry entries for:
    · unquoted \$@ on alias lines (should be "\$@")
    · unparseable script path · missing script · not executable
    · orphan scripts (also counted in lint total)

${C_PRIMARY}Paths${C_RESET}
  registry   ${REGISTRY}  (ali → Config, or ${ALI_CONFIG_FILE})
  scripts    ${ALIASES_DIR}
  backup     ${BACKUP_DIR}

${C_PRIMARY}Setup${C_RESET}
  ali config bashrc   Show ~/.bashrc lines for a new install
EOF
}

main() {
  local cmd=${1:-}
  local needs_registry=1

  case "$cmd" in
    help|-h|--help|config|cfg)
      needs_registry=0
      ;;
  esac

  if (( needs_registry )) && ! registry_file_exists; then
    printf '%bRegistry not found:%b %s\n' "$C_ERROR" "$C_RESET" "$REGISTRY" >&2
    printf 'Run %bali config%b to set paths, or create the registry file.\n' "$C_CYAN" "$C_RESET" >&2
    exit 1
  fi

  case "$cmd" in
    ''|tui|menu)
      set +e
      cmd_tui_menu
      set -e
      ;;
    list|ls)
      cmd_list
      ;;
    new|n)
      shift || true
      cmd_new "${1:-}"
      ;;
    remove|rm|delete)
      shift || true
      cmd_remove "${1:-}"
      ;;
    rename|mv)
      shift || true
      cmd_rename "${1:-}" "${2:-}"
      ;;
    orphan|register)
      shift || true
      cmd_register_orphan "${1:-}"
      ;;
    doctor|lint|check)
      shift || true
      cmd_doctor "$@"
      ;;
    refresh|reload)
      cmd_refresh
      ;;
    backup|bak)
      cmd_backup
      ;;
    config|cfg)
      shift || true
      cmd_config "$@"
      ;;
    help|-h|--help)
      cmd_help
      ;;
    *)
      printf '%bUnknown command:%b %s\n' "$C_ERROR" "$C_RESET" "$cmd" >&2
      printf 'Run %bali help%b for usage.\n' "$C_CYAN" "$C_RESET" >&2
      exit 1
      ;;
  esac
}

main "$@"
