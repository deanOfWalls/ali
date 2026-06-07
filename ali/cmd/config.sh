#!/bin/bash

cmd_config() {
  local sub=${1:-}

  case "$sub" in
    bashrc)
      ali_config_bashrc_lines
      ;;
    set)
      shift || true
      cmd_config_set "$@"
      ;;
    ''|show)
      ui_header 'ali · config'
      printf '  Config file: %s\n\n' "$ALI_CONFIG_FILE"
      printf '  registry  %s\n' "$REGISTRY"
      printf '  scripts   %s\n' "$ALIASES_DIR"
      printf '  backup    %s\n\n' "$BACKUP_DIR"
      printf '%bRun %bali config bashrc%b for ~/.bashrc setup lines.\n' \
        "$C_MUTED" "$C_CYAN" "$C_RESET"
      ;;
    *)
      printf 'Usage: ali config [show|bashrc|set <registry|scripts|backup> <path>]\n' >&2
      return 1
      ;;
  esac
}

cmd_config_set() {
  local key=${1:-} path=${2:-}

  if [[ -z "$key" || -z "$path" ]]; then
    printf 'Usage: ali config set <registry|scripts|backup> <path>\n' >&2
    return 1
  fi

  case "$key" in
    registry) ali_config_set_registry "$path" ;;
    scripts|aliases) ali_config_set_aliases_dir "$path" ;;
    backup) ali_config_set_backup_dir "$path" ;;
    *)
      printf 'Unknown key: %s (use registry, scripts, or backup)\n' "$key" >&2
      return 1
      ;;
  esac

  printf 'Saved to %s\n' "$ALI_CONFIG_FILE"
}

cmd_config_edit_path() {
  local which=$1
  local label current new_path

  case "$which" in
    registry)
      label='Registry path'
      current=$REGISTRY
      ;;
    scripts)
      label='Scripts path'
      current=$ALIASES_DIR
      ;;
    backup)
      label='Backup path'
      current=$BACKUP_DIR
      ;;
    *)
      return 1
      ;;
  esac

  TUI_SCREEN=1
  TUI_SCREEN_DRAWN=0
  tui_screen_open ' ALI · config '
  ui_prompt_read new_path "$label" "$current"

  if [[ -z "$new_path" ]]; then
    ui_say warn 'Aborted.'
    ui_press_enter
    TUI_SCREEN=0
    TUI_SCREEN_DRAWN=0
    return 1
  fi

  case "$which" in
    registry) ali_config_set_registry "$new_path" ;;
    scripts) ali_config_set_aliases_dir "$new_path" ;;
    backup) ali_config_set_backup_dir "$new_path" ;;
  esac

  ui_say ok "Saved $label"
  if [[ "$which" == registry && ! -f "$REGISTRY" ]]; then
    ui_say warn "Registry file does not exist yet: $REGISTRY"
  fi
  tui_stats_invalidate
  ui_press_enter
  TUI_SCREEN=0
  TUI_SCREEN_DRAWN=0
}

cmd_config_show_bashrc_pager() {
  local -a lines=()
  mapfile -t lines < <(ali_config_bashrc_lines)
  tui_pager ' ALI · ~/.bashrc setup ' lines
}

cmd_tui_config_draw_row() {
  local idx=$1 selected=$2
  local row=$((11 + idx))
  local -a labels=(
    'Registry path'
    'Scripts path'
    'Backup path'
    '~/.bashrc setup'
  )

  tui_draw_body_row "$row"
  tui_fill_inner_row "$row"
  tui_at "$row" 6
  if (( selected )); then
    printf '%b  %s %b%b%d%b  %s' \
      "$(tui_style_sel)" "$TUI_CH_SEL" \
      "$(tui_rgb_bg "${TUI_SEL_BG[@]}")" "$(tui_rgb_fg "${TUI_ACCENT[@]}")" "$((idx + 1))" \
      "$(tui_style_sel)" "${labels[$idx]}"
    tui_reset
  else
    printf '%b    %b%d%b  %s' \
      "$(tui_style_text)" \
      "$(tui_style_accent)" "$((idx + 1))" "$(tui_style_text)" \
      "${labels[$idx]}"
    tui_reset
  fi
}

cmd_tui_config_apply_nav() {
  local dir=$1
  case "$dir" in
    up)
      TUI_CONFIG_SEL=$((TUI_CONFIG_SEL - 1))
      (( TUI_CONFIG_SEL < 0 )) && TUI_CONFIG_SEL=3
      ;;
    down)
      TUI_CONFIG_SEL=$((TUI_CONFIG_SEL + 1))
      (( TUI_CONFIG_SEL > 3 )) && TUI_CONFIG_SEL=0
      ;;
  esac
}

cmd_tui_config_draw() {
  local prev_sel=${1:-$TUI_CONFIG_SEL}
  local i max=$((TUI_INNER_W - 8))

  tui_begin_sync
  tui_draw_frame ' ALI · config '
  tui_draw_panel_divider 3
  tui_at 4 4
  printf '%bPaths%b  %b(saved to %s)' \
    "$(tui_style_accent)$TUI_BOLD" "$(tui_reset)" \
    "$(tui_style_muted)" "$(tui_truncate "$ALI_CONFIG_FILE" "$max")"
  tui_reset
  tui_at 5 6
  printf '%bregistry%b  %s' "$(tui_style_muted)" "$(tui_reset)" \
    "$(tui_truncate "$(ali_config_tilde "$REGISTRY")" "$max")"
  tui_at 6 6
  printf '%bscripts%b   %s' "$(tui_style_muted)" "$(tui_reset)" \
    "$(tui_truncate "$(ali_config_tilde "$ALIASES_DIR")" "$max")"
  tui_at 7 6
  printf '%bbackup%b    %s' "$(tui_style_muted)" "$(tui_reset)" \
    "$(tui_truncate "$(ali_config_tilde "$BACKUP_DIR")" "$max")"
  tui_fill_inner_row 9
  tui_at 9 4
  printf '%bCONFIG MENU' "$(tui_style_muted)$TUI_BOLD"
  tui_reset
  for i in 0 1 2 3; do
    cmd_tui_config_draw_row "$i" "$(( i == TUI_CONFIG_SEL ))"
  done
  tui_draw_nav_footer
  tui_end_sync
}

cmd_tui_config_wait_input() {
  local key dir

  key=$(tui_read_key_once)
  dir=$(tui_nav_key "$key")
  case "$dir" in
    up|down)
      cmd_tui_config_apply_nav "$dir"
      tui_drain_arrow_burst cmd_tui_config_apply_nav
      TUI_LAST_KEY=$dir
      return 0
      ;;
  esac
  TUI_LAST_KEY=$key
  tui_input_purge
  return 1
}

cmd_tui_config() {
  local prev_sel=0 home_nav=0

  TUI_CONFIG_SEL=0
  TUI_SCREEN=0
  TUI_SCREEN_DRAWN=0
  tui_nav_mode_set action
  TUI_NEED_FULL=1

  while true; do
    if (( TUI_NEED_FULL )) || tui_resize_changed; then
      cmd_tui_config_draw "$prev_sel"
      TUI_NEED_FULL=0
      tui_mark_resize_seen
      prev_sel=$TUI_CONFIG_SEL
    fi

    if cmd_tui_config_wait_input; then
      cmd_tui_config_draw "$prev_sel"
      prev_sel=$TUI_CONFIG_SEL
    else
      case "$TUI_LAST_KEY" in
        enter)
          case "$TUI_CONFIG_SEL" in
            0) cmd_config_edit_path registry; TUI_NEED_FULL=1 ;;
            1) cmd_config_edit_path scripts; TUI_NEED_FULL=1 ;;
            2) cmd_config_edit_path backup; TUI_NEED_FULL=1 ;;
            3) cmd_config_show_bashrc_pager; TUI_NEED_FULL=1 ;;
          esac
          ;;
        1|2|3|4)
          TUI_CONFIG_SEL=$((TUI_LAST_KEY - 1))
          case "$TUI_CONFIG_SEL" in
            0) cmd_config_edit_path registry; TUI_NEED_FULL=1 ;;
            1) cmd_config_edit_path scripts; TUI_NEED_FULL=1 ;;
            2) cmd_config_edit_path backup; TUI_NEED_FULL=1 ;;
            3) cmd_config_show_bashrc_pager; TUI_NEED_FULL=1 ;;
          esac
          ;;
        back|quit|esc)
          tui_nav_mode_sync
          TUI_NEED_FULL=1
          return 0
          ;;
      esac
    fi
  done
}
