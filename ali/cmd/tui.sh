#!/bin/bash

cmd_tui_run_action_pager() {
  local action=$1
  local title=''
  local -a lines=()
  local result=0

  case "$action" in
    help) title=' ALI · help ' ;;
    doctor) title=' ALI · doctor ' ;;
    refresh) title=' ALI · refresh ' ;;
    backup) title=' ALI · backup ' ;;
  esac

  case "$action" in
    help)
      mapfile -t lines < <(
        TUI_ACTIVE=0 TUI_SCREEN=0 cmd_help 2>&1 | tui_strip_ansi
      ) || result=$?
      ;;
    doctor)
      mapfile -t lines < <(
        TUI_ACTIVE=0 TUI_SCREEN=0 cmd_doctor 2>&1 | tui_strip_ansi
      ) || result=$?
      ;;
    refresh)
      mapfile -t lines < <(
        TUI_ACTIVE=0 TUI_SCREEN=0 cmd_refresh 2>&1 | tui_strip_ansi
      ) || result=$?
      ;;
    backup)
      mapfile -t lines < <(
        TUI_ACTIVE=0 TUI_SCREEN=0 cmd_backup 2>&1 | tui_strip_ansi
      ) || result=$?
      ;;
  esac

  tui_pager "$title" lines
  return "$result"
}

cmd_tui_run_action_interactive() {
  local action=$1
  local result=0

  TUI_SCREEN=1
  TUI_SCREEN_DRAWN=0
  tui_nav_mode_set action

  case "$action" in
    new)
      TUI_SCREEN_TITLE=' ALI · new alias '
      tui_screen_open "$TUI_SCREEN_TITLE"
      cmd_new || result=$?
      ;;
  esac

  ui_press_enter
  TUI_SCREEN=0
  TUI_SCREEN_DRAWN=0
  return "$result"
}

cmd_tui_run_action() {
  local action=$1
  local result=0

  case "$action" in
    help|doctor|refresh|backup)
      cmd_tui_run_action_pager "$action" || result=$?
      ;;
    *)
      cmd_tui_run_action_interactive "$action" || result=$?
      ;;
  esac

  tui_drain_pending_newline
  tui_stats_invalidate
  TUI_PAGER_ACTIVE=0
  TUI_SCREEN=0
  TUI_SCREEN_DRAWN=0
  tui_nav_mode_sync
  TUI_NEED_FULL=1
  return "$result"
}

cmd_tui_browse_action_screen() {
  local title=$1
  shift
  local result=0

  TUI_SCREEN=1
  TUI_SCREEN_DRAWN=0
  TUI_SCREEN_TITLE=$title
  tui_nav_mode_set action
  "$@" || result=$?
  ui_press_enter
  TUI_SCREEN=0
  TUI_SCREEN_DRAWN=0
  TUI_NEED_FULL=1
  return "$result"
}

cmd_tui_browse_actions() {
  local name=$1
  local key enabled=1

  while true; do
    registry_entry_enabled "$name" && enabled=1 || enabled=0
    TUI_BROWSE_ACTIONS_ENABLED=$enabled
    tui_nav_mode_set browse_actions
    tui_begin_sync
    tui_draw_frame ' ALI · actions '
    tui_draw_panel_divider 3
    tui_at 4 4
    if (( enabled )); then
      printf '%bActions — %s' "$(tui_style_accent)$TUI_BOLD" "$name"
    else
      printf '%bActions — %s %b(disabled)' "$(tui_style_accent)$TUI_BOLD" "$name" "$(tui_style_muted)"
    fi
    tui_reset
    tui_draw_nav_footer
    tui_end_sync

    key=$(tui_read_key_once)
    case "$key" in
      d|D)
        if registry_entry_enabled "$name"; then
          registry_set_enabled "$name" 0 || true
          tui_stats_invalidate
          TUI_NEED_FULL=1
        fi
        ;;
      e|E)
        if ! registry_entry_enabled "$name"; then
          registry_set_enabled "$name" 1 || true
          tui_stats_invalidate
          TUI_NEED_FULL=1
        fi
        ;;
      n|N)
        cmd_tui_browse_action_screen ' ALI · rename alias ' cmd_rename "$name" || true
        return 1
        ;;
      r|R)
        cmd_tui_browse_action_screen ' ALI · remove alias ' cmd_remove "$name" || true
        return 1
        ;;
      b|B|back|quit|esc)
        tui_nav_mode_set browse
        TUI_NEED_FULL=1
        return 0
        ;;
    esac
  done
}

cmd_tui_browse_reload() {
  local -n _names=$1
  mapfile -t _names < <(registry_list_all_names)
  tui_browse_cache_build "$1"
  tui_stats_invalidate
}

cmd_tui_menu() {
  local -a browse_names=()
  local key total
  local prev_menu=0 prev_sel=0 prev_off=0

  set +e
  set +u

  cmd_tui_browse_reload browse_names
  total=${#browse_names[@]}

  tui_enter
  tui_stats_invalidate

  TUI_VIEW=home
  TUI_MENU_SEL=0
  TUI_BROWSE_SEL=0
  TUI_BROWSE_OFF=0
  TUI_NEED_FULL=1
  prev_menu=0
  prev_sel=0
  prev_off=0

  while (( ! TUI_QUIT )); do
    tui_size_update

    if [[ "$TUI_VIEW" == browse ]]; then
      total=${#browse_names[@]}

      if (( TUI_NEED_FULL )) || tui_resize_changed; then
        tui_begin_sync
        tui_draw_browse browse_names
        TUI_NEED_FULL=0
        tui_mark_resize_seen
        tui_end_sync
        prev_sel=$TUI_BROWSE_SEL
        prev_off=$TUI_BROWSE_OFF
      fi

      if tui_browse_wait_input "$total"; then
        tui_browse_paint_nav "$total" "$prev_sel" "$prev_off"
        prev_sel=$TUI_BROWSE_SEL
        prev_off=$TUI_BROWSE_OFF
      else
        case "$TUI_LAST_KEY" in
          enter)
            if (( total > 0 )); then
              cmd_tui_browse_actions "${browse_names[$TUI_BROWSE_SEL]}"
              cmd_tui_browse_reload browse_names
              total=${#browse_names[@]}
              TUI_NEED_FULL=1
              if (( total == 0 )); then
                TUI_VIEW=home
              else
                (( TUI_BROWSE_SEL >= total )) && TUI_BROWSE_SEL=$((total - 1))
              fi
            fi
            ;;
          back)
            TUI_VIEW=home
            TUI_NEED_FULL=1
            ;;
          quit) TUI_QUIT=1 ;;
          esc) : ;;
        esac
      fi
    else
      local home_nav=0

      if (( TUI_NEED_FULL )) || tui_resize_changed; then
        tui_render browse_names '' "$prev_menu" "$prev_sel" "$prev_off"
        TUI_NEED_FULL=0
        tui_mark_resize_seen
        prev_menu=$TUI_MENU_SEL
      fi

      if tui_home_wait_input; then
        home_nav=1
      else
        case "$TUI_LAST_KEY" in
          enter)
            case "$TUI_MENU_SEL" in
              0)
                cmd_tui_browse_reload browse_names
                TUI_VIEW=browse
                TUI_BROWSE_SEL=0
                TUI_BROWSE_OFF=0
                TUI_NEED_FULL=1
                tui_drain_pending_newline
                ;;
              1) cmd_tui_run_action new ;;
              2) cmd_tui_run_action doctor ;;
              3) cmd_tui_run_action backup ;;
              4) cmd_tui_run_action help ;;
              5) cmd_tui_config ;;
            esac
            ;;
          1|2|3|4|5|6)
            TUI_MENU_SEL=$((TUI_LAST_KEY - 1))
            if (( TUI_MENU_SEL == 0 )); then
              cmd_tui_browse_reload browse_names
              TUI_VIEW=browse
              TUI_BROWSE_SEL=0
              TUI_BROWSE_OFF=0
              TUI_NEED_FULL=1
              tui_drain_pending_newline
            else
              case "$TUI_MENU_SEL" in
                1) cmd_tui_run_action new ;;
                2) cmd_tui_run_action doctor ;;
                3) cmd_tui_run_action backup ;;
                4) cmd_tui_run_action help ;;
                5) cmd_tui_config ;;
              esac
            fi
            ;;
          quit) TUI_QUIT=1 ;;
        esac
      fi

      if [[ "$TUI_VIEW" == home ]]; then
        if (( TUI_NEED_FULL )) || tui_resize_changed; then
          tui_render browse_names '' "$prev_menu" "$prev_sel" "$prev_off"
          TUI_NEED_FULL=0
          tui_mark_resize_seen
        elif (( home_nav )); then
          tui_home_paint_nav "$prev_menu"
        fi
        prev_menu=$TUI_MENU_SEL
      fi

      prev_sel=$TUI_BROWSE_SEL
      prev_off=$TUI_BROWSE_OFF
    fi
  done

  tui_leave
  tui_trap_pop
  set -u
}

cmd_tui_stats() { :; }
cmd_tui_browse() { cmd_tui_menu; }
