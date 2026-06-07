#!/bin/bash
# Premium full-screen TUI core — truecolor, alternate buffer, keyboard nav.

TUI_W=80
TUI_H=24
TUI_INNER_W=78
TUI_VIEW=home
TUI_MENU_SEL=0
TUI_BROWSE_SEL=0
TUI_BROWSE_OFF=0
TUI_BROWSE_DETAIL_SEL=-1
TUI_QUIT=0
TUI_NEED_FULL=1
TUI_LAST_W=0
TUI_LAST_H=0
TUI_LIST_DASHES=30
TUI_DETAIL_DASHES=45
TUI_DETAIL_COL=36
TUI_DETAIL_W=45
TUI_LIST_W=30
TUI_BROWSE_MARK_W=2
TUI_BROWSE_NAME_W=14
TUI_BROWSE_TYPE_W=8
TUI_BROWSE_STATUS_COL=$((3 + TUI_BROWSE_MARK_W + TUI_BROWSE_NAME_W + TUI_BROWSE_TYPE_W))

TUI_BC_NAMES=()
TUI_BC_TYPES=()
TUI_BC_TYPE_FULL=()
TUI_BC_PATHS=()
TUI_BC_READY=()
TUI_BC_ENABLED=()
TUI_BC_REG_LINES=()
TUI_BC_LIST_NORM=()
TUI_BC_LIST_SEL=()
TUI_BC_DETAIL_META=()
TUI_BC_DETAIL_PREVIEW=()
TUI_BC_DISPLAY_W=0
TUI_BC_DISPLAY_H=0
declare -A TUI_PREVIEW_CACHE=()
declare -A TUI_PREVIEW_MTIME=()
TUI_STATS_DIRTY=1
TUI_LAST_KEY=''
TUI_ACTIVE=0
TUI_CLEANED=0
TUI_TTY=''
TUI_STTY_SAVED=''
TUI_NAV_MODE=home
TUI_PAGER_ACTIVE=0
TUI_SCREEN_HINT=''

TUI_PROMPT_REPLY=''
TUI_C_APPBG=''
TUI_C_TEXT=''
TUI_C_MUTED=''
TUI_C_ACCENT=''
TUI_C_OK=''
TUI_C_WARN=''
TUI_C_ERR=''
TUI_C_SEL=''
TUI_C_PANEL=''
TUI_C_FRAME_MUTED=''
TUI_OUT=''

TUI_HOME_LIST_NORM=()
TUI_HOME_LIST_SEL=()

TUI_ESC=$'\033'
TUI_RESET="${TUI_ESC}[0m"
TUI_BOLD="${TUI_ESC}[1m"
TUI_DIM="${TUI_ESC}[2m"

# ASCII-only markers (safe on any terminal / font).
TUI_CH_SEL='>'

TUI_BG=(12 14 22)
TUI_PANEL=(18 22 34)
TUI_PANEL_ALT=(24 18 38)
TUI_BORDER=(130 80 180)
TUI_FRAME_BG=(42 28 72)
TUI_FRAME_FG=(220 210 240)
TUI_ACCENT=(255 95 210)
TUI_ACCENT_DIM=(180 70 150)
TUI_TEXT=(230 232 240)
TUI_MUTED=(110 118 140)
TUI_SUCCESS=(90 220 140)
TUI_WARN=(255 180 80)
TUI_ERROR=(255 90 110)
TUI_SEL_BG=(70 35 95)
TUI_SEL_FG=(255 240 255)
TUI_HEADER=(16 20 32)

tui_rgb_fg() { printf '%s[38;2;%sm' "$TUI_ESC" "$1;$2;$3"; }
tui_rgb_bg() { printf '%s[48;2;%sm' "$TUI_ESC" "$1;$2;$3"; }

# Always pair foreground with the app background so RESET never exposes the terminal default.
tui_app_bg() { tui_rgb_bg "${TUI_BG[@]}"; }

tui_style_text() { printf '%b%b' "$(tui_app_bg)" "$(tui_rgb_fg "${TUI_TEXT[@]}")"; }
tui_style_muted() { printf '%b%b' "$(tui_app_bg)" "$(tui_rgb_fg "${TUI_MUTED[@]}")"; }
tui_style_accent() { printf '%b%b' "$(tui_app_bg)" "$(tui_rgb_fg "${TUI_ACCENT[@]}")"; }
tui_style_border() { printf '%b%b' "$(tui_app_bg)" "$(tui_rgb_fg "${TUI_BORDER[@]}")"; }
tui_style_ok() { printf '%b%b' "$(tui_app_bg)" "$(tui_rgb_fg "${TUI_SUCCESS[@]}")"; }
tui_style_warn() { printf '%b%b' "$(tui_app_bg)" "$(tui_rgb_fg "${TUI_WARN[@]}")"; }
tui_style_err() { printf '%b%b' "$(tui_app_bg)" "$(tui_rgb_fg "${TUI_ERROR[@]}")"; }
tui_style_sel() {
  printf '%b%b%b' "$(tui_rgb_bg "${TUI_SEL_BG[@]}")" "$(tui_rgb_fg "${TUI_SEL_FG[@]}")" "$TUI_BOLD"
}

tui_frame_bg() { tui_rgb_bg "${TUI_FRAME_BG[@]}"; }
tui_style_frame_text() { printf '%b%b' "$(tui_frame_bg)" "$(tui_rgb_fg "${TUI_FRAME_FG[@]}")"; }
tui_style_frame_accent() { printf '%b%b' "$(tui_frame_bg)" "$(tui_rgb_fg "${TUI_ACCENT[@]}")"; }
tui_style_frame_muted() { printf '%b%b' "$(tui_frame_bg)" "$(tui_rgb_fg "${TUI_MUTED[@]}")"; }
tui_style_panel_bar() { printf '%b' "$(tui_rgb_bg "${TUI_PANEL[@]}")"; }

tui_reset() { printf '%b' "$(tui_app_bg)"; }

tui_repeat() {
  local char=$1 count=$2
  printf '%*s' "$count" '' | tr ' ' "$char"
}

tui_truncate() {
  local text=$1 max=$2
  if ((${#text} > max)); then
    printf '%s...' "${text:0:$((max - 3))}"
  else
    printf '%s' "$text"
  fi
}

# Fixed-width field for list columns (truncate then pad).
tui_fit_field() {
  local text=$1 max=$2
  printf '%-*s' "$max" "$(tui_truncate "$text" "$max")"
}

tui_browse_type_label() {
  case "$(registry_entry_type "$1")" in
    function) printf 'func' ;;
    alias)    printf 'alias' ;;
    *)        printf '?' ;;
  esac
}

tui_browse_type_short() {
  case "$1" in
    function) printf 'func' ;;
    alias)    printf 'alias' ;;
    *)        printf '?' ;;
  esac
}

# Precompute per-row metadata once (avoid grep/stat on every keypress).
tui_browse_cache_build() {
  local array_name=$1
  local -n _names=$array_name
  local name path type_full

  TUI_BC_NAMES=()
  TUI_BC_TYPES=()
  TUI_BC_TYPE_FULL=()
  TUI_BC_PATHS=()
  TUI_BC_READY=()
  TUI_BC_ENABLED=()
  TUI_BC_REG_LINES=()
  TUI_PREVIEW_CACHE=()
  TUI_PREVIEW_MTIME=()
  TUI_BROWSE_DETAIL_SEL=-1

  for name in "${_names[@]}"; do
    TUI_BC_NAMES+=("$name")
    type_full=$(registry_entry_type "$name")
    path=$(registry_script_path_for "$name" 2>/dev/null || echo "")
    TUI_BC_TYPE_FULL+=("$type_full")
    TUI_BC_TYPES+=("$(tui_browse_type_short "$type_full")")
    TUI_BC_PATHS+=("$path")
    if [[ -f "$path" && -x "$path" ]]; then
      TUI_BC_READY+=(1)
    else
      TUI_BC_READY+=(0)
    fi
    if registry_entry_enabled "$name"; then
      TUI_BC_ENABLED+=(1)
    else
      TUI_BC_ENABLED+=(0)
    fi
    TUI_BC_REG_LINES+=("$(registry_get_line "$name")")
  done
  tui_browse_invalidate_display_cache
}

tui_browse_invalidate_display_cache() {
  TUI_BC_LIST_NORM=()
  TUI_BC_LIST_SEL=()
  TUI_BC_DETAIL_META=()
  TUI_BC_DETAIL_PREVIEW=()
  TUI_BC_DISPLAY_W=0
  TUI_BC_DISPLAY_H=0
  TUI_BROWSE_DETAIL_SEL=-1
}

tui_styles_cache_refresh() {
  TUI_C_APPBG=$(tui_app_bg)
  TUI_C_TEXT=$(tui_style_text)
  TUI_C_MUTED=$(tui_style_muted)
  TUI_C_ACCENT=$(tui_style_accent)
  TUI_C_OK=$(tui_style_ok)
  TUI_C_WARN=$(tui_style_warn)
  TUI_C_ERR=$(tui_style_err)
  TUI_C_SEL=$(tui_style_sel)
  TUI_C_PANEL=$(tui_style_panel_bar)
  TUI_C_FRAME_MUTED=$(tui_style_frame_muted)
}

tui_out_reset() { TUI_OUT=''; }

tui_out_append() { TUI_OUT+=$1; }

tui_out_flush() {
  if [[ -n "$TUI_OUT" ]]; then
    printf '%s' "$TUI_OUT"
    TUI_OUT=''
  fi
}

tui_pad_line() {
  local text=$1 width=$2
  local vis=${#text} pad

  (( vis >= width )) && { printf '%s' "${text:0:width}"; return; }
  pad=$((width - vis))
  printf '%s%*s' "$text" "$pad" ''
}

tui_browse_list_status_str() {
  local idx=$1 selected=$2
  local path="${TUI_BC_PATHS[$idx]}"
  local ready="${TUI_BC_READY[$idx]}"

  if (( ! TUI_BC_ENABLED[$idx] )); then
    printf '%b-' "$TUI_C_MUTED"
  elif (( ready )); then
    printf '%b+' "$TUI_C_OK"
  elif (( selected )) && [[ ! -f "$path" ]]; then
    printf '%bx' "$TUI_C_ERR"
  elif (( selected )); then
    printf '%b!' "$TUI_C_WARN"
  else
    printf '%b.' "$TUI_C_WARN"
  fi
}

tui_browse_format_list_row() {
  local idx=$1 selected=$2
  local mark name_f type_f status row_w
  local style=$TUI_C_TEXT

  (( selected )) && style=$TUI_C_SEL
  if (( selected )); then
    mark=$(tui_fit_field "$TUI_CH_SEL" "$TUI_BROWSE_MARK_W")
  else
    mark=$(tui_fit_field '' "$TUI_BROWSE_MARK_W")
  fi
  name_f=$(tui_fit_field "${TUI_BC_NAMES[$idx]}" "$TUI_BROWSE_NAME_W")
  type_f=$(tui_fit_field "${TUI_BC_TYPES[$idx]}" "$TUI_BROWSE_TYPE_W")
  status=$(tui_browse_list_status_str "$idx" "$selected")
  row_w=$(tui_browse_list_fill_w)
  tui_pad_line "${style}${mark}${name_f}${type_f}${TUI_C_APPBG}${status}${TUI_C_APPBG}" "$row_w"
}

tui_browse_format_detail_meta_block() {
  local idx=$1
  local col=$TUI_DETAIL_COL dw=$TUI_DETAIL_W
  local name="${TUI_BC_NAMES[$idx]}"
  local type="${TUI_BC_TYPE_FULL[$idx]}"
  local path="${TUI_BC_PATHS[$idx]}"
  local reg_line="${TUI_BC_REG_LINES[$idx]}"
  local out='' line

  line="${TUI_C_MUTED}Name${TUI_C_APPBG}     ${TUI_C_ACCENT}${name}${TUI_C_APPBG}"
  out+="${TUI_ESC}[5;${col}H$(tui_pad_line "$line" "$dw")"
  line="${TUI_C_MUTED}Type${TUI_C_APPBG}     ${type}${TUI_C_APPBG}"
  out+="${TUI_ESC}[6;${col}H$(tui_pad_line "$line" "$dw")"
  line="${TUI_C_MUTED}Script${TUI_C_APPBG}   $(tui_truncate "${path:-?}" "$((dw - 10))")${TUI_C_APPBG}"
  out+="${TUI_ESC}[7;${col}H$(tui_pad_line "$line" "$dw")"

  line="${TUI_C_MUTED}Status${TUI_C_APPBG}   "
  if (( ! TUI_BC_ENABLED[$idx] )); then
    line+="${TUI_C_MUTED}disabled"
  elif (( TUI_BC_READY[$idx] )); then
    line+="${TUI_C_OK}ready"
  elif [[ -n "$path" && ! -f "$path" ]]; then
    line+="${TUI_C_ERR}missing"
  elif [[ -n "$path" ]]; then
    line+="${TUI_C_WARN}not executable"
  fi
  line+="${TUI_C_APPBG}"
  out+="${TUI_ESC}[8;${col}H$(tui_pad_line "$line" "$dw")"

  line="${TUI_C_ACCENT}${TUI_BOLD}Registry${TUI_C_APPBG}"
  out+="${TUI_ESC}[10;${col}H$(tui_pad_line "$line" "$dw")"
  line="${TUI_C_TEXT}$(tui_truncate "$reg_line" "$dw")${TUI_C_APPBG}"
  out+="${TUI_ESC}[11;${col}H$(tui_pad_line "$line" "$dw")"

  printf '%s' "$out"
}

tui_browse_format_detail_preview_block() {
  local idx=$1
  local col=$TUI_DETAIL_COL dw=$TUI_DETAIL_W
  local path="${TUI_BC_PATHS[$idx]}"
  local max_preview=$((TUI_H - 16)) ln pline out='' line

  (( max_preview < 3 )) && max_preview=3

  for ((ln = 0; ln < max_preview; ln++)); do
    out+="${TUI_ESC}[$((13 + ln));${col}H$(tui_pad_line "$TUI_C_APPBG" "$dw")"
  done

  [[ -z "$path" || ! -f "$path" ]] && { printf '%s' "$out"; return; }

  out+="${TUI_ESC}[13;${col}H$(tui_pad_line "${TUI_C_ACCENT}${TUI_BOLD}Preview${TUI_C_APPBG}" "$dw")"
  ln=0
  while IFS= read -r pline && (( ln < max_preview )); do
    line="${TUI_C_MUTED} $(tui_truncate "$pline" "$((dw - 1))")${TUI_C_APPBG}"
    out+="${TUI_ESC}[$((14 + ln));${col}H$(tui_pad_line "$line" "$dw")"
    ln=$((ln + 1))
  done < <(tui_preview_lines "$path" "$max_preview")

  printf '%s' "$out"
}

tui_browse_format_detail_block() {
  local idx=$1
  printf '%s%s' "$(tui_browse_format_detail_meta_block "$idx")" "$(tui_browse_format_detail_preview_block "$idx")"
}

tui_browse_display_cache_build() {
  local i total=${#TUI_BC_NAMES[@]}

  if [[ "$TUI_W" == "$TUI_BC_DISPLAY_W" && "$TUI_H" == "$TUI_BC_DISPLAY_H" ]]; then
    return 0
  fi

  tui_styles_cache_refresh
  TUI_BC_LIST_NORM=()
  TUI_BC_LIST_SEL=()
  TUI_BC_DETAIL_META=()
  TUI_BC_DETAIL_PREVIEW=()

  for ((i = 0; i < total; i++)); do
    TUI_BC_LIST_NORM+=("$(tui_browse_format_list_row "$i" 0)")
    TUI_BC_LIST_SEL+=("$(tui_browse_format_list_row "$i" 1)")
    TUI_BC_DETAIL_META+=("$(tui_browse_format_detail_meta_block "$i")")
    TUI_BC_DETAIL_PREVIEW[$i]=$(tui_browse_format_detail_preview_block "$i")
  done

  TUI_BC_DISPLAY_W=$TUI_W
  TUI_BC_DISPLAY_H=$TUI_H
  TUI_BROWSE_DETAIL_SEL=-1
}

tui_browse_preview_get() {
  local idx=$1

  if [[ -z "${TUI_BC_DETAIL_PREVIEW[$idx]+x}" ]]; then
    TUI_BC_DETAIL_PREVIEW[$idx]=$(tui_browse_format_detail_preview_block "$idx")
  fi
  printf '%s' "${TUI_BC_DETAIL_PREVIEW[$idx]}"
}

tui_browse_paint_list_to_out() {
  local total=$1 prev_sel=$2 prev_off=$3
  local vis prev_slot new_slot i idx

  tui_browse_ensure_visible "$total"
  vis=$(tui_browse_visible_rows)

  if (( prev_off == TUI_BROWSE_OFF )); then
    prev_slot=$((prev_sel - TUI_BROWSE_OFF))
    new_slot=$((TUI_BROWSE_SEL - TUI_BROWSE_OFF))
    if (( prev_sel >= 0 && prev_sel < total && prev_slot >= 0 && prev_slot < vis )); then
      tui_out_append "${TUI_ESC}[$((5 + prev_slot));3H${TUI_BC_LIST_NORM[$prev_sel]}"
    fi
    if (( TUI_BROWSE_SEL >= 0 && TUI_BROWSE_SEL < total && new_slot >= 0 && new_slot < vis )); then
      tui_out_append "${TUI_ESC}[$((5 + new_slot));3H${TUI_BC_LIST_SEL[$TUI_BROWSE_SEL]}"
    fi
  else
    for ((i = 0; i < vis; i++)); do
      idx=$((TUI_BROWSE_OFF + i))
      (( idx >= total )) && continue
      if (( idx == TUI_BROWSE_SEL )); then
        tui_out_append "${TUI_ESC}[$((5 + i));3H${TUI_BC_LIST_SEL[$idx]}"
      else
        tui_out_append "${TUI_ESC}[$((5 + i));3H${TUI_BC_LIST_NORM[$idx]}"
      fi
    done
  fi

  if (( total > vis )); then
    tui_out_append "${TUI_ESC}[$((TUI_H - 4));3H${TUI_C_MUTED} $((TUI_BROWSE_SEL + 1)) / ${total}${TUI_C_APPBG}"
  fi
}

tui_browse_paint_detail_to_out() {
  local total=$1

  tui_browse_idx_ok "$TUI_BROWSE_SEL" "$total" || return 0
  if [[ -z "${TUI_BC_DETAIL_PREVIEW[$TUI_BROWSE_SEL]+x}" ]]; then
    TUI_BC_DETAIL_PREVIEW[$TUI_BROWSE_SEL]=$(tui_browse_format_detail_preview_block "$TUI_BROWSE_SEL")
  fi
  tui_out_append "${TUI_BC_DETAIL_META[$TUI_BROWSE_SEL]}"
  tui_out_append "${TUI_BC_DETAIL_PREVIEW[$TUI_BROWSE_SEL]}"
  TUI_BROWSE_DETAIL_SEL=$TUI_BROWSE_SEL
}

tui_browse_paint_nav() {
  local total=$1 prev_sel=$2 prev_off=$3

  (( prev_sel == TUI_BROWSE_SEL && prev_off == TUI_BROWSE_OFF )) && return 0
  (( total < 1 )) && return 0

  tui_browse_display_cache_build
  (( ${#TUI_BC_LIST_NORM[@]} < total )) && return 0

  tui_out_reset
  tui_browse_paint_list_to_out "$total" "$prev_sel" "$prev_off"
  tui_browse_paint_detail_to_out "$total"
  tui_begin_sync
  tui_out_flush
  tui_end_sync
}

tui_browse_detail_get() {
  local idx=$1 include_preview=${2:-1}

  printf '%s' "${TUI_BC_DETAIL_META[$idx]}"
  (( include_preview )) && printf '%s' "$(tui_browse_preview_get "$idx")"
}

tui_browse_paint_list() {
  local total=$1 prev_sel=$2 prev_off=$3

  tui_browse_display_cache_build
  tui_out_reset
  tui_browse_paint_list_to_out "$total" "$prev_sel" "$prev_off"
  tui_out_flush
}

tui_browse_paint_detail() {
  local total=$1

  tui_browse_display_cache_build
  tui_out_reset
  tui_browse_paint_detail_to_out "$total"
  tui_out_flush
}

tui_browse_paint() {
  tui_browse_paint_nav "$1" "$2" "$3"
}

tui_browse_wait_input() {
  local total=$1
  local key dir

  key=$(tui_read_key_once)
  dir=$(tui_nav_key "$key")
  case "$dir" in
    up|down|pageup|pagedown)
      tui_browse_apply_nav "$dir" "$total"
      tui_drain_arrow_burst tui_browse_apply_nav "$total"
      TUI_LAST_KEY=$dir
      return 0
      ;;
  esac
  TUI_LAST_KEY=$key
  tui_input_purge
  return 1
}

tui_home_apply_nav() {
  case "$1" in
    up)
      TUI_MENU_SEL=$((TUI_MENU_SEL - 1))
      (( TUI_MENU_SEL < 0 )) && TUI_MENU_SEL=$((${#tui_menu_items[@]} - 1))
      ;;
    down)
      TUI_MENU_SEL=$((TUI_MENU_SEL + 1))
      (( TUI_MENU_SEL >= ${#tui_menu_items[@]} )) && TUI_MENU_SEL=0
      ;;
  esac
}

tui_home_format_menu_row() {
  local idx=$1 selected=$2
  local row=$((9 + idx))
  local label="${tui_menu_items[$idx]}"
  local line w=$((TUI_INNER_W - 4))

  if (( selected )); then
    line=$(printf '%b  %s %b%b%d%b  %s' \
      "$TUI_C_SEL" "$TUI_CH_SEL" \
      "$(tui_rgb_bg "${TUI_SEL_BG[@]}")" "$TUI_C_ACCENT" "$((idx + 1))" \
      "$TUI_C_SEL" "$label")
  else
    line=$(printf '%b    %b%d%b  %s' \
      "$TUI_C_TEXT" "$TUI_C_ACCENT" "$((idx + 1))" "$TUI_C_TEXT" "$label")
  fi
  printf '%s[%d;6H%s' "$TUI_ESC" "$row" "$(tui_pad_line "${TUI_C_APPBG}${line}${TUI_C_APPBG}" "$w")"
}

tui_home_menu_cache_build() {
  local i

  TUI_HOME_LIST_NORM=()
  TUI_HOME_LIST_SEL=()
  for i in "${!tui_menu_items[@]}"; do
    TUI_HOME_LIST_NORM+=("$(tui_home_format_menu_row "$i" 0)")
    TUI_HOME_LIST_SEL+=("$(tui_home_format_menu_row "$i" 1)")
  done
}

tui_home_paint_nav() {
  local prev=$1

  (( prev == TUI_MENU_SEL )) && return 0
  (( ${#TUI_HOME_LIST_NORM[@]} == 0 )) && tui_home_menu_cache_build

  tui_out_reset
  if (( prev >= 0 && prev < ${#TUI_HOME_LIST_NORM[@]} )); then
    tui_out_append "${TUI_HOME_LIST_NORM[$prev]}"
  fi
  if (( TUI_MENU_SEL >= 0 && TUI_MENU_SEL < ${#TUI_HOME_LIST_SEL[@]} )); then
    tui_out_append "${TUI_HOME_LIST_SEL[$TUI_MENU_SEL]}"
  fi
  tui_begin_sync
  tui_out_flush
  tui_end_sync
}

tui_home_wait_input() {
  local key dir

  key=$(tui_read_key_once)
  dir=$(tui_nav_key "$key")
  case "$dir" in
    up|down)
      tui_home_apply_nav "$dir"
      tui_drain_arrow_burst tui_home_apply_nav
      TUI_LAST_KEY=$dir
      return 0
      ;;
  esac
  TUI_LAST_KEY=$key
  tui_input_purge
  return 1
}

tui_stats_invalidate() { TUI_STATS_DIRTY=1; }

tui_preview_lines() {
  local path=$1 max=$2
  local key="${path}|${max}" mtime

  if [[ -z "$path" || ! -f "$path" ]]; then
    return 0
  fi

  mtime=$(stat -c '%Y' "$path" 2>/dev/null || stat -f '%m' "$path" 2>/dev/null || echo 0)
  if [[ -n "${TUI_PREVIEW_MTIME[$path]+x}" && "${TUI_PREVIEW_MTIME[$path]}" != "$mtime" ]]; then
    local k
    local -a _preview_keys=("${!TUI_PREVIEW_CACHE[@]}")
    for k in "${_preview_keys[@]}"; do
      [[ "$k" == "${path}|"* ]] && unset "TUI_PREVIEW_CACHE[$k]"
    done
  fi
  TUI_PREVIEW_MTIME[$path]=$mtime

  if [[ -z "${TUI_PREVIEW_CACHE[$key]+x}" ]]; then
    TUI_PREVIEW_CACHE[$key]=$(head -n "$max" "$path" 2>/dev/null)
  fi
  printf '%s' "${TUI_PREVIEW_CACHE[$key]}"
}

tui_browse_layout_compute() {
  local split_content=$((TUI_W - 5))
  TUI_LIST_DASHES=$(( split_content * 42 / 100 ))
  (( TUI_LIST_DASHES < 20 )) && TUI_LIST_DASHES=20
  (( TUI_LIST_DASHES > split_content - 12 )) && TUI_LIST_DASHES=$((split_content - 12))
  TUI_DETAIL_DASHES=$((split_content - TUI_LIST_DASHES))
  TUI_LIST_W=$TUI_LIST_DASHES
  TUI_DETAIL_COL=$((TUI_LIST_DASHES + 4))
  TUI_DETAIL_W=$TUI_DETAIL_DASHES
}

tui_size_update() {
  local w h

  w=$(tput cols 2>/dev/null || echo 80)
  h=$(tput lines 2>/dev/null || echo 24)
  (( w < 72 )) && w=72
  (( h < 20 )) && h=20
  if [[ "$w" == "$TUI_W" && "$h" == "$TUI_H" ]]; then
    return 0
  fi
  TUI_W=$w
  TUI_H=$h
  TUI_INNER_W=$((TUI_W - 2))
  tui_browse_layout_compute
}

tui_begin_sync() { printf '%s[?2026h' "$TUI_ESC"; }
tui_end_sync() { printf '%s[?2026l' "$TUI_ESC"; }

tui_tty_init() {
  TUI_TTY=$(tty 2>/dev/null || echo /dev/tty)
  [[ -r "$TUI_TTY" ]] || TUI_TTY=/dev/tty
  TUI_STTY_SAVED=$(stty -g -F "$TUI_TTY" 2>/dev/null || stty -g 2>/dev/null || true)
}

tui_tty_apply() {
  local mode=$1

  [[ -z "$TUI_TTY" ]] && tui_tty_init
  case "$mode" in
    raw)
      stty -F "$TUI_TTY" -echo -icanon min 0 time 0 2>/dev/null || \
        stty -echo -icanon min 0 time 0 2>/dev/null || true
      ;;
    cooked)
      stty -F "$TUI_TTY" echo icanon 2>/dev/null || stty echo icanon 2>/dev/null || true
      ;;
    restore)
      [[ -n "$TUI_STTY_SAVED" ]] && \
        stty -F "$TUI_TTY" "$TUI_STTY_SAVED" 2>/dev/null || \
        stty "$TUI_STTY_SAVED" 2>/dev/null || true
      ;;
  esac
}

tui_read_byte() {
  local _var=$1
  local _timeout=${2:-}
  local _rc=0

  [[ -z "$TUI_TTY" ]] && tui_tty_init
  if [[ -n "$_timeout" ]]; then
    IFS= read -rsn1 -t "$_timeout" "$_var" <"$TUI_TTY" 2>/dev/null || _rc=$?
  else
    IFS= read -rsn1 "$_var" <"$TUI_TTY" 2>/dev/null || _rc=$?
  fi
  return "$_rc"
}

tui_collect_pending_bytes() {
  local buf='' k=''

  while tui_read_byte k 0; do
    buf+=$k
  done
  printf '%s' "$buf"
}

tui_collect_pending_bytes_capped() {
  local max=${1:-48}
  local buf='' k=''
  local n=0

  while (( n < max )) && tui_read_byte k 0; do
    buf+=$k
    n=$((n + 1))
  done
  printf '%s' "$buf"
}

tui_parse_arrows_in_buf() {
  local buf=$1
  local apply_fn=$2
  local max_steps=$3
  shift 3
  local i=0 len=${#buf} c c2 c3 c4 steps=0

  while (( i < len && steps < max_steps )); do
    c=${buf:i:1}
    if [[ "$c" == $'\e' ]] && (( i + 2 < len )); then
      c2=${buf:i+1:1}
      c3=${buf:i+2:1}
      if [[ "$c2" == '[' ]]; then
        case "$c3" in
          A) "$apply_fn" up "$@"; i=$((i + 3)); steps=$((steps + 1)); continue ;;
          B) "$apply_fn" down "$@"; i=$((i + 3)); steps=$((steps + 1)); continue ;;
          C) "$apply_fn" right "$@"; i=$((i + 3)); steps=$((steps + 1)); continue ;;
          D) "$apply_fn" left "$@"; i=$((i + 3)); steps=$((steps + 1)); continue ;;
          5|6)
            if (( i + 3 < len )); then
              c4=${buf:i+3:1}
              if [[ "$c4" == '~' ]]; then
                [[ "$c3" == 5 ]] && "$apply_fn" pageup "$@" || "$apply_fn" pagedown "$@"
                i=$((i + 4))
                steps=$((steps + 1))
                continue
              fi
            fi
            ;;
        esac
      fi
    fi
    i=$((i + 1))
  done
}

tui_enter() {
  tui_size_update
  TUI_LAST_W=$TUI_W
  TUI_LAST_H=$TUI_H
  TUI_ACTIVE=1
  TUI_CLEANED=0
  tui_tty_init
  tui_tty_apply raw
  tui_styles_cache_refresh
  tui_trap_push
  tput smcup 2>/dev/null || true
  tput civis 2>/dev/null || true
  # Set terminal background to match the app (works on many emulators).
  printf '%s]11;rgb:%s/%s/%s%s\\' "$TUI_ESC" \
    "$(printf '%02x' "${TUI_BG[0]}")" \
    "$(printf '%02x' "${TUI_BG[1]}")" \
    "$(printf '%02x' "${TUI_BG[2]}")" "$TUI_ESC"
  printf '%s[2J%s[H' "$TUI_ESC" "$TUI_ESC"
}

tui_leave() {
  (( TUI_CLEANED )) && return 0
  TUI_CLEANED=1
  TUI_ACTIVE=0
  tui_end_sync
  tui_tty_apply restore
  tput cnorm 2>/dev/null || true
  tput rmcup 2>/dev/null || true
  printf '%s\n' "$TUI_RESET"
}

tui_trap_push() {
  trap 'tui_handle_int' INT
  trap 'tui_handle_term' TERM
  trap 'tui_handle_exit' EXIT
}

tui_trap_pop() {
  trap - INT TERM EXIT
}

tui_handle_int() {
  tui_leave
  tui_trap_pop
  exit 130
}

tui_handle_term() {
  tui_leave
  tui_trap_pop
  exit 143
}

tui_handle_exit() {
  tui_leave
}

tui_goto() { printf '%s[%d;%dH' "$TUI_ESC" "$1" "$2"; }
tui_at() { tui_goto "$1" "$2"; }

tui_input_purge() {
  tui_collect_pending_bytes >/dev/null
}

tui_drain_arrow_burst() {
  local apply_fn=$1
  shift
  local buf='' k=''
  local i=0

  buf=$(tui_collect_pending_bytes_capped 48)
  while (( i < 6 )); do
    tui_read_byte k 0.004 || break
    buf+=$k
    i=$((i + 1))
  done
  tui_parse_arrows_in_buf "$buf" "$apply_fn" 24 "$@"
  tui_input_purge
}

tui_read_key_once() {
  local k='' k2='' k3='' k4=''

  if ! tui_read_byte k; then
    printf quit
    return 0
  fi
  case "$k" in
    $'\e')
      if ! tui_read_byte k2 0.04; then
        printf esc
        return 0
      fi
      if [[ "$k2" != '[' ]]; then
        printf esc
        return 0
      fi
      if ! tui_read_byte k3 0.04; then
        printf esc
        return 0
      fi
      case "$k3" in
        A) printf up ;;
        B) printf down ;;
        C) printf right ;;
        D) printf left ;;
        5|6)
          tui_read_byte k4 0.02 2>/dev/null || true
          if [[ "$k4" == '~' ]]; then
            [[ "$k3" == 5 ]] && printf pageup || printf pagedown
          else
            printf esc
          fi
          ;;
        *) printf esc ;;
      esac
      ;;
    ''|$'\n'|$'\r') printf enter ;;
    q|Q) printf quit ;;
    h|b|B) printf back ;;
    [1-9]) printf '%s' "$k" ;;
    *) printf esc ;;
  esac
}

# Legacy wrapper — prefer tui_home_wait_input / tui_browse_wait_input.
tui_read_key() {
  local key=''

  key=$(tui_read_key_once) || return
  printf '%s' "$key"
}

tui_drain_pending_newline() {
  local k=''
  tui_read_byte k 0 2>/dev/null || return 0
  [[ "$k" == $'\n' || "$k" == $'\r' ]]
}

tui_nav_key() {
  printf '%s' "$1"
}

tui_browse_idx_ok() {
  local idx=$1 total=$2
  (( total > 0 && idx >= 0 && idx < total && idx < ${#TUI_BC_NAMES[@]} ))
}

tui_browse_apply_nav() {
  local key=$1 total=$2
  local vis

  (( total > 0 )) || return 0
  vis=$(tui_browse_visible_rows)
  (( vis < 1 )) && vis=1

  case "$key" in
    up)
      TUI_BROWSE_SEL=$((TUI_BROWSE_SEL - 1))
      (( TUI_BROWSE_SEL < 0 )) && TUI_BROWSE_SEL=$((total - 1))
      ;;
    down)
      TUI_BROWSE_SEL=$((TUI_BROWSE_SEL + 1))
      (( TUI_BROWSE_SEL >= total )) && TUI_BROWSE_SEL=0
      ;;
    pageup)
      TUI_BROWSE_SEL=$((TUI_BROWSE_SEL - vis))
      if (( TUI_BROWSE_SEL < 0 )); then
        TUI_BROWSE_SEL=0
      fi
      ;;
    pagedown)
      TUI_BROWSE_SEL=$((TUI_BROWSE_SEL + vis))
      if (( TUI_BROWSE_SEL >= total )); then
        TUI_BROWSE_SEL=$((total - 1))
      fi
      ;;
    *)
      return 0
      ;;
  esac

  tui_browse_ensure_visible "$total"
  return 0
}

tui_bg_str() { tui_app_bg; }

tui_fill_row() {
  local row=$1 col=$2 width=$3
  tui_at "$row" "$col"
  printf '%b%*s' "$(tui_app_bg)" "$width" ''
}

tui_fill_inner_row() {
  tui_fill_row "$1" 2 "$TUI_INNER_W"
}

tui_fill_screen_bg() {
  local row
  for ((row = 1; row <= TUI_H; row++)); do
    tui_draw_body_row "$row"
  done
}

tui_draw_frame_bar() {
  local row=$1
  tui_at "$row" 1
  printf '%b%*s' "$(tui_frame_bg)" "$TUI_W" ''
  tui_reset
}

tui_draw_body_row() {
  local row=$1
  tui_at "$row" 1
  printf '%b %b' "$(tui_frame_bg)" "$(tui_reset)"
  tui_fill_row "$row" 2 "$TUI_INNER_W"
  tui_at "$row" "$TUI_W"
  printf '%b %b' "$(tui_frame_bg)" "$(tui_reset)"
}

tui_draw_panel_divider() {
  local row=$1
  tui_at "$row" 2
  printf '%b%*s' "$(tui_style_panel_bar)" "$TUI_INNER_W" ''
  tui_reset
}

tui_draw_frame() {
  local title=$1

  tui_draw_frame_bar 1
  for ((row = 2; row < TUI_H; row++)); do
    tui_draw_body_row "$row"
  done
  tui_draw_frame_bar "$TUI_H"

  if [[ -n "$title" ]]; then
    tui_at 1 3
    printf '%b%s' "$(tui_style_frame_accent)$TUI_BOLD" "$title"
    tui_reset
  fi
}

tui_draw_logo() {
  local row=$1 col=$2
  tui_at "$row" "$col"
  printf '%bALI' "$(tui_style_accent)$TUI_BOLD"
  tui_reset
  tui_at "$((row + 1))" "$col"
  printf '%bregistry' "$(tui_style_muted)"
  tui_reset
}

tui_stats_collect() {
  (( ! TUI_STATS_DIRTY )) && return 0
  TUI_STAT_REG=$(registry_list_names | wc -l | tr -d ' ')
  TUI_STAT_ORPH=$(scripts_orphans | wc -l | tr -d ' ')
  TUI_STAT_LINT=$(cmd_doctor --count-only 2>/dev/null || echo 0)
  TUI_STAT_GIT=$(scripts_git_dirty_count)
  TUI_STAT_BACKUP=0
  scripts_registry_needs_backup && TUI_STAT_BACKUP=1
  TUI_STATS_DIRTY=0
}

tui_stat_severity_zero_ok() {
  local n=$1
  (( n == 0 )) && echo good || echo warn
}

tui_draw_status_field() {
  local label=$1 value=$2 severity=$3

  printf '%b%s:%b' "$(tui_style_accent)" "$label" "$(tui_reset)"
  case "$severity" in
    good)  printf '%b%s' "$(tui_style_ok)" "$value" ;;
    warn)  printf '%b%s' "$(tui_style_warn)" "$value" ;;
    err)   printf '%b%s' "$(tui_style_err)" "$value" ;;
    *)     printf '%b%s' "$(tui_style_text)" "$value" ;;
  esac
  tui_reset
}

tui_draw_status_pills() {
  local row=$1 col=$2

  tui_at "$row" "$col"
  tui_draw_status_field registered "$TUI_STAT_REG" neutral
  printf '  '
  tui_draw_status_field orphans "$TUI_STAT_ORPH" "$(tui_stat_severity_zero_ok "$TUI_STAT_ORPH")"
  printf '  '
  tui_draw_status_field lint "$TUI_STAT_LINT" "$(tui_stat_severity_zero_ok "$TUI_STAT_LINT")"
  printf '  '
  tui_draw_status_field git-dirty "$TUI_STAT_GIT" "$(tui_stat_severity_zero_ok "$TUI_STAT_GIT")"
  printf '  '
  printf '%bbackup %b' "$(tui_style_accent)" "$(tui_reset)"
  if (( TUI_STAT_BACKUP )); then
    printf '%bstale' "$(tui_style_warn)"
  else
    printf '%bok' "$(tui_style_ok)"
  fi
  tui_reset
}

tui_draw_footer_hints() {
  local text=$1
  tui_at "$TUI_H" 3
  printf '%b%s' "$(tui_style_frame_muted)" "$(tui_truncate "$text" "$((TUI_INNER_W - 2))")"
  tui_reset
}

# Footer nav hints: pairs of (highlight rest), e.g. 'q' 'uit' → pink q + muted uit
tui_draw_footer_keys() {
  local key label first=1
  tui_at "$TUI_H" 3
  while [[ $# -ge 2 ]]; do
    key=$1
    label=$2
    shift 2
    (( first )) || printf '%b · %b' "$(tui_style_frame_muted)" "$(tui_style_frame_muted)"
    first=0
    printf '%b%s%b' "$(tui_style_frame_accent)" "$key" "$(tui_style_frame_muted)"
    [[ -n "$label" ]] && printf '%s' "$label"
  done
  tui_reset
}

tui_nav_mode_set() {
  TUI_NAV_MODE=$1
}

tui_nav_mode_sync() {
  if (( TUI_PAGER_ACTIVE )); then
    tui_nav_mode_set pager
  elif (( TUI_SCREEN )); then
    tui_nav_mode_set action
  elif [[ "$TUI_VIEW" == browse ]]; then
    tui_nav_mode_set browse
  else
    tui_nav_mode_set home
  fi
}

tui_draw_nav_footer() {
  tui_at "$TUI_H" 2
  printf '%b%*s' "$(tui_frame_bg)" "$TUI_INNER_W" ''
  tui_reset

  case "$TUI_NAV_MODE" in
    home)
      tui_draw_footer_keys '↑↓' ' move' 'Enter' '' '1-6' ' jump' 'q' 'uit'
      ;;
    browse)
      tui_draw_footer_keys '↑↓' ' scroll' 'Enter' '' 'b' 'ack' 'q' 'uit'
      ;;
    browse_actions)
      tui_draw_browse_actions_footer "${TUI_BROWSE_ACTIONS_ENABLED:-1}"
      ;;
    action)
      tui_draw_footer_keys 'Enter' '' 'b' 'ack' 'q' 'uit'
      ;;
    pager)
      tui_draw_footer_keys '↑↓' ' scroll' 'Enter' '' 'b' 'ack' 'q' 'uit'
      ;;
    *)
      tui_draw_footer_keys 'q' 'uit'
      ;;
  esac
}

tui_draw_browse_actions_footer() {
  local enabled=$1
  if (( enabled )); then
    tui_draw_footer_keys 'd' 'isable' 'n' ' rename' 'r' 'emove' 'b' 'ack' 'q' 'uit'
  else
    tui_draw_footer_keys 'e' 'nable' 'n' ' rename' 'r' 'emove' 'b' 'ack' 'q' 'uit'
  fi
}

tui_menu_items=(
  'Browse registry'
  'New alias'
  'Doctor / lint'
  'Backup registry'
  'Help'
  'Config'
)

tui_draw_home_menu_row() {
  local idx=$1 selected=$2
  local row=$((9 + idx))
  local label="${tui_menu_items[$idx]}"

  tui_draw_body_row "$row"
  tui_fill_inner_row "$row"
  tui_at "$row" 6
  if (( selected )); then
    printf '%b  %s %b%b%d%b  %s' \
      "$(tui_style_sel)" "$TUI_CH_SEL" \
      "$(tui_rgb_bg "${TUI_SEL_BG[@]}")" "$(tui_rgb_fg "${TUI_ACCENT[@]}")" "$((idx + 1))" \
      "$(tui_style_sel)" "$label"
    tui_reset
  else
    printf '%b    %b%d%b  %s' \
      "$(tui_style_text)" \
      "$(tui_style_accent)" "$((idx + 1))" "$(tui_style_text)" \
      "$label"
    tui_reset
  fi
}

tui_draw_home() {
  local i

  tui_stats_collect
  tui_nav_mode_set home
  tui_draw_frame ' ALI - alias registry cli '
  tui_draw_status_pills 3 4
  tui_draw_panel_divider 6

  tui_fill_inner_row 7
  tui_at 7 4
  printf '%bCOMMAND MENU' "$(tui_style_muted)$TUI_BOLD"
  tui_reset

  for i in "${!tui_menu_items[@]}"; do
    tui_draw_home_menu_row "$i" "$(( i == TUI_MENU_SEL ))"
  done
  tui_home_menu_cache_build

  tui_draw_panel_divider $((TUI_H - 3))
  tui_draw_nav_footer
}

tui_draw_home_delta() {
  local prev=$1
  tui_draw_home_menu_row "$prev" 0
  tui_draw_home_menu_row "$TUI_MENU_SEL" 1
}

tui_browse_split_col() { echo $((TUI_LIST_DASHES + 3)); }

tui_browse_list_fill_w() { echo $((TUI_LIST_DASHES + 1)); }

# List pane only — never repaint frame edges, splitter, or detail panel.
tui_fill_browse_list_area() {
  tui_fill_row "$1" 3 "$(tui_browse_list_fill_w)"
}

tui_browse_visible_rows() { echo $((TUI_H - 8)); }

tui_browse_ensure_visible() {
  local total=$1 vis
  vis=$(tui_browse_visible_rows)
  (( total == 0 )) && return
  (( TUI_BROWSE_SEL < 0 )) && TUI_BROWSE_SEL=0
  (( TUI_BROWSE_SEL >= total )) && TUI_BROWSE_SEL=$((total - 1))
  if (( TUI_BROWSE_SEL < TUI_BROWSE_OFF )); then
    TUI_BROWSE_OFF=$TUI_BROWSE_SEL
  elif (( TUI_BROWSE_SEL >= TUI_BROWSE_OFF + vis )); then
    TUI_BROWSE_OFF=$((TUI_BROWSE_SEL - vis + 1))
  fi
}

tui_draw_browse_divider() {
  tui_draw_panel_divider 4
  tui_at 4 3
  printf '%b COMMANDS' "$(tui_style_accent)$TUI_BOLD"
  tui_reset
  tui_at 4 "$TUI_DETAIL_COL"
  printf '%b DETAIL' "$(tui_style_accent)$TUI_BOLD"
  tui_reset
}

tui_draw_browse_list_row() {
  local slot=$2
  local idx=$3
  local total=$4
  local row=$((5 + slot))
  local name type_label path ready

  tui_fill_browse_list_area "$row"
  (( idx >= total )) && return
  tui_browse_idx_ok "$idx" "$total" || return

  name="${TUI_BC_NAMES[$idx]}"
  type_label="${TUI_BC_TYPES[$idx]}"
  path="${TUI_BC_PATHS[$idx]}"
  ready="${TUI_BC_READY[$idx]}"

  tui_at "$row" 3
  if (( idx == TUI_BROWSE_SEL )); then
    printf '%b%s%s%s' \
      "$(tui_style_sel)" "$(tui_fit_field "$TUI_CH_SEL" "$TUI_BROWSE_MARK_W")" \
      "$(tui_fit_field "$name" "$TUI_BROWSE_NAME_W")" \
      "$(tui_fit_field "$type_label" "$TUI_BROWSE_TYPE_W")"
    tui_reset
  else
    printf '%b%s%s%s' \
      "$(tui_style_text)" "$(tui_fit_field '' "$TUI_BROWSE_MARK_W")" \
      "$(tui_fit_field "$name" "$TUI_BROWSE_NAME_W")" \
      "$(tui_fit_field "$type_label" "$TUI_BROWSE_TYPE_W")"
    tui_reset
  fi

  tui_at "$row" "$TUI_BROWSE_STATUS_COL"
  if (( ! TUI_BC_ENABLED[$idx] )); then
    printf '%b-' "$(tui_style_muted)"
  elif (( ready )); then
    printf '%b+' "$(tui_style_ok)"
  elif (( idx == TUI_BROWSE_SEL )) && [[ ! -f "$path" ]]; then
    printf '%bx' "$(tui_style_err)"
  elif (( idx == TUI_BROWSE_SEL )); then
    printf '%b!' "$(tui_style_warn)"
  else
    printf '%b.' "$(tui_style_warn)"
  fi
  tui_reset
}

tui_draw_browse_detail_meta() {
  local total=$1
  local idx=$TUI_BROWSE_SEL
  local name type path reg_line

  (( total == 0 )) && return
  tui_browse_ensure_visible "$total"
  idx=$TUI_BROWSE_SEL
  tui_browse_idx_ok "$idx" "$total" || return

  name="${TUI_BC_NAMES[$idx]}"
  type="${TUI_BC_TYPE_FULL[$idx]}"
  path="${TUI_BC_PATHS[$idx]}"
  reg_line="${TUI_BC_REG_LINES[$idx]}"

  tui_fill_row 5 "$TUI_DETAIL_COL" "$TUI_DETAIL_W"
  tui_at 5 "$TUI_DETAIL_COL"
  printf '%bName%b     %b%s' "$(tui_style_muted)" "$(tui_reset)" "$(tui_style_accent)" "$name"
  tui_reset
  tui_fill_row 6 "$TUI_DETAIL_COL" "$TUI_DETAIL_W"
  tui_at 6 "$TUI_DETAIL_COL"
  printf '%bType%b     %s' "$(tui_style_muted)" "$(tui_reset)" "$type"
  tui_reset
  tui_fill_row 7 "$TUI_DETAIL_COL" "$TUI_DETAIL_W"
  tui_at 7 "$TUI_DETAIL_COL"
  printf '%bScript%b   %s' "$(tui_style_muted)" "$(tui_reset)" "$(tui_truncate "${path:-?}" "$((TUI_DETAIL_W - 10))")"
  tui_reset
  tui_fill_row 8 "$TUI_DETAIL_COL" "$TUI_DETAIL_W"
  tui_at 8 "$TUI_DETAIL_COL"
  printf '%bStatus%b   ' "$(tui_style_muted)" "$(tui_reset)"
  if (( ! TUI_BC_ENABLED[$idx] )); then
    printf '%bdisabled' "$(tui_style_muted)"
  elif (( TUI_BC_READY[$idx] )); then
    printf '%bready' "$(tui_style_ok)"
  elif [[ -n "$path" && ! -f "$path" ]]; then
    printf '%bmissing' "$(tui_style_err)"
  elif [[ -n "$path" ]]; then
    printf '%bnot executable' "$(tui_style_warn)"
  fi
  tui_reset
  tui_fill_row 10 "$TUI_DETAIL_COL" "$TUI_DETAIL_W"
  tui_at 10 "$TUI_DETAIL_COL"
  printf '%bRegistry' "$(tui_style_accent)$TUI_BOLD"
  tui_reset
  tui_fill_row 11 "$TUI_DETAIL_COL" "$TUI_DETAIL_W"
  tui_at 11 "$TUI_DETAIL_COL"
  printf '%b%s' "$(tui_style_text)" "$(tui_truncate "$reg_line" "$TUI_DETAIL_W")"
  tui_reset
}

tui_draw_browse_detail_preview() {
  local idx=$TUI_BROWSE_SEL
  local total=$1
  local path max_preview=$((TUI_H - 16)) ln pline preview_end row

  tui_browse_idx_ok "$idx" "$total" || return

  path="${TUI_BC_PATHS[$idx]}"

  (( max_preview < 3 )) && max_preview=3
  preview_end=$((13 + max_preview))

  for ((row = 13; row <= preview_end; row++)); do
    tui_fill_row "$row" "$TUI_DETAIL_COL" "$TUI_DETAIL_W"
  done

  [[ -z "$path" || ! -f "$path" ]] && return

  tui_at 13 "$TUI_DETAIL_COL"
  printf '%bPreview' "$(tui_style_accent)$TUI_BOLD"
  tui_reset
  ln=0
  while IFS= read -r pline && (( ln < max_preview )); do
    tui_at "$((14 + ln))" "$TUI_DETAIL_COL"
    printf '%b%s' "$(tui_style_muted)" "$(tui_truncate " $pline" "$TUI_DETAIL_W")"
    tui_reset
    ln=$((ln + 1))
  done < <(tui_preview_lines "$path" "$max_preview")
}

tui_draw_browse_detail_clear() {
  local row end_row=$((TUI_H - 4))
  for ((row = 5; row <= end_row; row++)); do
    tui_fill_row "$row" "$TUI_DETAIL_COL" "$TUI_DETAIL_W"
  done
}

tui_draw_browse_detail_if_needed() {
  local total=$1 force=${2:-0}

  (( ! force && TUI_BROWSE_SEL == TUI_BROWSE_DETAIL_SEL )) && return 0

  tui_draw_browse_detail_clear
  tui_draw_browse_detail_meta "$total"
  tui_draw_browse_detail_preview "$total"
  TUI_BROWSE_DETAIL_SEL=$TUI_BROWSE_SEL
}

tui_draw_browse_detail() {
  tui_draw_browse_detail_if_needed "$1" 1
}

tui_draw_browse_list_sel_delta() {
  local array_name=$1 total=$2 prev_sel=$3
  local vis prev_slot new_slot

  vis=$(tui_browse_visible_rows)
  prev_slot=$((prev_sel - TUI_BROWSE_OFF))
  new_slot=$((TUI_BROWSE_SEL - TUI_BROWSE_OFF))

  if (( prev_sel >= 0 && prev_sel < total && prev_slot >= 0 && prev_slot < vis )); then
    tui_draw_browse_list_row "$array_name" "$prev_slot" "$prev_sel" "$total"
  fi
  if (( new_slot >= 0 && new_slot < vis )); then
    tui_draw_browse_list_row "$array_name" "$new_slot" "$TUI_BROWSE_SEL" "$total"
  fi
}

tui_draw_browse_counter() {
  local total=$1 vis

  vis=$(tui_browse_visible_rows)
  (( total <= vis )) && return 0
  tui_fill_browse_list_area $((TUI_H - 4))
  tui_at $((TUI_H - 4)) 3
  printf '%b %d / %d' "$(tui_style_muted)" "$((TUI_BROWSE_SEL + 1))" "$total"
  tui_reset
}

tui_draw_browse_list_viewport() {
  local -n _names=$1
  local array_name=$1
  local total=$2 vis i idx
  vis=$(tui_browse_visible_rows)
  for ((i = 0; i < vis; i++)); do
    idx=$((TUI_BROWSE_OFF + i))
    tui_draw_browse_list_row "$array_name" "$i" "$idx" "$total"
  done
}

tui_draw_browse_splitter() {
  local row split_col=$((TUI_LIST_DASHES + 3))
  for ((row = 5; row <= TUI_H - 4; row++)); do
    tui_at "$row" "$split_col"
    printf '%b %b' "$(tui_style_panel_bar)" "$(tui_reset)"
  done
}

tui_draw_browse_list_viewport_cached() {
  local total=$1 vis i idx

  vis=$(tui_browse_visible_rows)
  tui_out_reset
  for ((i = 0; i < vis; i++)); do
    idx=$((TUI_BROWSE_OFF + i))
    (( idx >= total )) && continue
    if (( idx == TUI_BROWSE_SEL )); then
      tui_out_append "${TUI_ESC}[$((5 + i));3H${TUI_BC_LIST_SEL[$idx]}"
    else
      tui_out_append "${TUI_ESC}[$((5 + i));3H${TUI_BC_LIST_NORM[$idx]}"
    fi
  done
  tui_out_flush
}

tui_draw_browse() {
  local -n _names=$1
  local total=${#_names[@]}
  local vis

  tui_browse_ensure_visible "$total"
  vis=$(tui_browse_visible_rows)
  tui_browse_display_cache_build

  tui_stats_collect
  tui_nav_mode_set browse
  tui_draw_frame ' ALI - browse '
  tui_draw_status_pills 2 3
  tui_draw_browse_divider

  tui_draw_browse_list_viewport_cached "$total"
  tui_draw_browse_splitter

  if (( total == 0 )); then
    tui_at 6 5
    printf '%bNo registered commands.' "$TUI_C_MUTED"
    tui_out_reset
  elif (( total > vis )); then
    tui_out_reset
    tui_out_append "${TUI_ESC}[$((TUI_H - 4));3H${TUI_C_MUTED} $((TUI_BROWSE_SEL + 1)) / ${total}${TUI_C_APPBG}"
    tui_out_flush
  fi

  if (( total > 0 )) && tui_browse_idx_ok "$TUI_BROWSE_SEL" "$total"; then
    tui_out_reset
    tui_out_append "${TUI_BC_DETAIL_META[$TUI_BROWSE_SEL]}"
    tui_out_append "${TUI_BC_DETAIL_PREVIEW[$TUI_BROWSE_SEL]}"
    tui_out_flush
    TUI_BROWSE_DETAIL_SEL=$TUI_BROWSE_SEL
  fi

  tui_draw_panel_divider $((TUI_H - 3))
  tui_draw_nav_footer
}

tui_draw_browse_delta() {
  local -n _names=$1
  local array_name=$1
  local total=$2
  local prev_sel=$3
  local prev_off=$4

  (( prev_sel == TUI_BROWSE_SEL && prev_off == TUI_BROWSE_OFF )) && return 0

  tui_browse_ensure_visible "$total"

  if (( prev_off == TUI_BROWSE_OFF )); then
    tui_draw_browse_list_sel_delta "$array_name" "$total" "$prev_sel"
  else
    tui_draw_browse_list_viewport "$array_name" "$total"
  fi

  if (( prev_sel != TUI_BROWSE_SEL || prev_off != TUI_BROWSE_OFF )); then
    tui_draw_browse_counter "$total"
  fi

  tui_draw_browse_detail_if_needed "$total"
}

tui_resize_changed() {
  [[ "$TUI_W" != "$TUI_LAST_W" || "$TUI_H" != "$TUI_LAST_H" ]]
}

tui_mark_resize_seen() {
  TUI_LAST_W=$TUI_W
  TUI_LAST_H=$TUI_H
}

tui_render() {
  local names_array=$1
  local -n _names=$names_array
  local mode=$2
  local prev_menu=$3
  local prev_sel=$4
  local prev_off=$5
  local total=${#_names[@]}

  tui_begin_sync
  if (( TUI_NEED_FULL )) || tui_resize_changed; then
    if [[ "$TUI_VIEW" == home ]]; then
      tui_draw_home
    else
      tui_draw_browse "$names_array"
    fi
    TUI_NEED_FULL=0
    tui_mark_resize_seen
  elif [[ "$TUI_VIEW" == home ]]; then
    tui_draw_home_delta "$prev_menu"
  else
    tui_draw_browse_delta "$names_array" "$total" "$prev_sel" "$prev_off"
  fi
  tui_nav_mode_sync
  tui_draw_nav_footer
  tui_end_sync
}

tui_draw_local_box_top() {
  local row=$1 col=$2 width=$3 title=$4
  tui_at "$row" "$col"
  printf '%b%*s' "$(tui_style_panel_bar)" "$width" ''
  tui_reset
  if [[ -n "$title" ]]; then
    tui_at "$row" "$((col + 2))"
    printf '%b%s' "$(tui_style_accent)$TUI_BOLD" "$title"
    tui_reset
  fi
}

tui_draw_local_box_bottom() {
  local row=$1 col=$2 width=$3
  tui_at "$row" "$col"
  printf '%b%*s' "$(tui_style_panel_bar)" "$width" ''
  tui_reset
}

# --- In-TUI action screens (prompts, messages, pagers) ---

TUI_SCREEN=0
TUI_SCREEN_DRAWN=0
TUI_SCREEN_TITLE=' ALI '
TUI_SCR_ROW=4
TUI_SCR_COL=4

tui_strip_ansi() {
  sed 's/\x1b\[[0-9;]*m//g'
}

tui_screen_style() {
  case "$1" in
    ok|success) tui_style_ok ;;
    err|error) tui_style_err ;;
    warn)      tui_style_warn ;;
    muted)     tui_style_muted ;;
    accent)    tui_style_accent ;;
    primary)   tui_style_accent ;;
    *)         tui_style_text ;;
  esac
}

tui_screen_reset_cursor() {
  TUI_SCR_ROW=4
  TUI_SCR_COL=4
}

tui_screen_open() {
  local title=$1

  tui_nav_mode_set action
  tui_size_update
  tui_begin_sync
  tui_draw_frame "$title"
  tui_draw_panel_divider 3
  tui_draw_nav_footer
  tui_end_sync
  TUI_SCREEN_DRAWN=1
  TUI_SCREEN_TITLE=$title
  TUI_SCREEN_HINT=''
  tui_screen_reset_cursor
}

tui_screen_set_hint() {
  TUI_SCREEN_HINT=$1
  tui_screen_draw_hint
}

tui_screen_clear_hint() {
  TUI_SCREEN_HINT=''
  tui_fill_inner_row $((TUI_H - 2))
}

tui_screen_draw_hint() {
  tui_fill_inner_row $((TUI_H - 2))
  [[ -z "$TUI_SCREEN_HINT" ]] && return 0
  tui_at $((TUI_H - 2)) 4
  printf '%b%s' "$(tui_style_muted)" "$(tui_truncate "$TUI_SCREEN_HINT" "$((TUI_INNER_W - 6))")"
  tui_reset
}

# Back-compat alias — hints go above the persistent nav bar, not in it.
tui_screen_set_footer() {
  tui_screen_set_hint "$1"
}

tui_screen_ensure() {
  (( TUI_SCREEN_DRAWN )) || tui_screen_open "$TUI_SCREEN_TITLE" "$TUI_SCREEN_FOOTER"
}

tui_screen_say() {
  local style=${1:-text}
  shift
  local msg=$*
  local max=$((TUI_INNER_W - 6))

  tui_screen_ensure
  (( TUI_SCR_ROW < TUI_H - 2 )) || return 0
  tui_at "$TUI_SCR_ROW" "$TUI_SCR_COL"
  printf '%b%s' "$(tui_screen_style "$style")" "$(tui_truncate "$msg" "$max")"
  tui_reset
  TUI_SCR_ROW=$((TUI_SCR_ROW + 1))
}

tui_screen_rule() {
  tui_screen_ensure
  (( TUI_SCR_ROW < TUI_H - 2 )) || return 0
  tui_draw_panel_divider "$TUI_SCR_ROW"
  TUI_SCR_ROW=$((TUI_SCR_ROW + 1))
}

tui_read_line_at() {
  local row=$1 col=$2 width=$3
  local default=${4:-}
  local reply=$default

  tui_at "$row" "$col"
  printf '%b%*s' "$(tui_style_text)" "$width" ''
  tui_at "$row" "$col"
  tput cnorm 2>/dev/null || true
  tui_tty_apply cooked
  if [[ -n "$default" ]]; then
    read -r -e -i "$default" reply </dev/tty 2>/dev/null || read -r reply </dev/tty
  else
    read -r reply </dev/tty
  fi
  tui_tty_apply raw
  tput civis 2>/dev/null || true
  if [[ -z "$reply" && -n "$default" ]]; then
    reply=$default
  fi
  tui_at "$row" "$col"
  printf '%b%s' "$(tui_style_text)" "$reply"
  tui_reset
  TUI_PROMPT_REPLY=$reply
}

tui_prompt() {
  local message=$1
  local default=${2:-}
  local row=$((TUI_SCR_ROW + 1))

  tui_screen_ensure
  tui_screen_say text "$message"
  tui_read_line_at "$row" 6 $((TUI_INNER_W - 8)) "$default"
  TUI_SCR_ROW=$((row + 2))
}

tui_confirm() {
  local message=$1
  local reply

  tui_screen_ensure
  tui_screen_set_hint "$(tui_truncate "$message" $((TUI_INNER_W - 12))) [y/N]"
  tput cnorm 2>/dev/null || true
  tui_tty_apply cooked
  read -r reply </dev/tty
  tui_tty_apply raw
  tput civis 2>/dev/null || true
  tui_screen_clear_hint
  tui_begin_sync
  tui_draw_nav_footer
  tui_end_sync
  [[ "$reply" =~ ^[Yy]$ ]]
}

tui_press_enter() {
  local key

  tui_screen_ensure
  tui_screen_set_hint 'Press Enter or b to return...'
  while true; do
    key=$(tui_read_key_once)
    case "$key" in
      enter|back|quit|esc) break ;;
    esac
  done
  tui_screen_clear_hint
  tui_begin_sync
  tui_draw_nav_footer
  tui_end_sync
}

tui_suspend_for_external() {
  (( TUI_ACTIVE )) || return 0
  TUI_SCREEN_DRAWN=0
  tui_leave
}

tui_resume_from_external() {
  (( TUI_ACTIVE )) || return 0
  tui_enter
  TUI_NEED_FULL=1
}

tui_pager() {
  local title=$1
  local -n _pg_lines=$2
  local off=0 vis=$((TUI_H - 4)) total=${#_pg_lines[@]} key dir

  TUI_PAGER_ACTIVE=1
  tui_nav_mode_set pager
  (( vis < 1 )) && vis=1
  while true; do
    tui_begin_sync
    tui_draw_frame "$title"
    tui_draw_panel_divider 3
    local i max=$((TUI_INNER_W - 6))
    for ((i = 0; i < vis && i + off < total; i++)); do
      tui_at "$((4 + i))" 4
      printf '%b%s' "$(tui_style_text)" "$(tui_truncate "${_pg_lines[$((off + i))]}" "$max")"
      tui_reset
    done
    if (( total == 0 )); then
      tui_at 4 4
      printf '%b(no output)' "$(tui_style_muted)"
      tui_reset
    fi
    tui_draw_nav_footer
    tui_end_sync

    key=$(tui_read_key_once)
    dir=$(tui_nav_key "$key")
    case "$dir" in
      down)
        if (( off + vis < total )); then
          off=$((off + 1))
        fi
        ;;
      up)
        (( off > 0 )) && off=$((off - 1))
        ;;
      enter|esc|back|quit) break ;;
    esac
    case "$key" in
      b|B) break ;;
    esac
  done
  TUI_PAGER_ACTIVE=0
  tui_nav_mode_sync
  TUI_NEED_FULL=1
}

tui_overlay_message() {
  local title=$1
  shift
  local msg=$*
  local box_w box_h=8 row col i

  box_w=$((TUI_W * 70 / 100))
  (( box_w < 48 )) && box_w=48
  (( box_w > TUI_W - 4 )) && box_w=$((TUI_W - 4))
  row=$(( (TUI_H - box_h) / 2 ))
  col=$(( (TUI_W - box_w) / 2 ))

  tui_begin_sync
  for ((i = 0; i < box_h; i++)); do
    tui_at "$((row + i))" "$col"
    printf '%b%*s' "$(tui_style_panel_bar)" "$box_w" ''
    tui_reset
  done
  tui_draw_local_box_top "$row" "$col" "$box_w" " $title "
  tui_at "$((row + 3))" "$((col + 2))"
  printf '%b%s' "$(tui_style_text)" "$msg"
  tui_reset
  tui_at "$((row + box_h - 2))" "$((col + 2))"
  printf '%bPress any key...' "$(tui_style_muted)"
  tui_reset
  tui_draw_nav_footer
  tui_end_sync
  tui_read_byte _ 2>/dev/null || true
}
