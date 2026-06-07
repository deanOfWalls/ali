#!/bin/bash
# Theme helpers — matches the magenta palette used across ~/aliases.

if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'
  C_BOLD=$'\033[1m'
  C_DIM=$'\033[2m'
  C_PRIMARY=$'\033[38;5;205m'
  C_ACCENT=$'\033[38;5;141m'
  C_SUCCESS=$'\033[38;5;84m'
  C_WARN=$'\033[38;5;214m'
  C_ERROR=$'\033[38;5;203m'
  C_MUTED=$'\033[38;5;245m'
  C_CYAN=$'\033[38;5;81m'
  C_HEADER_BG=$'\033[48;5;236m'
else
  C_RESET='' C_BOLD='' C_DIM='' C_PRIMARY='' C_ACCENT=''
  C_SUCCESS='' C_WARN='' C_ERROR='' C_MUTED='' C_CYAN='' C_HEADER_BG=''
fi

colorize() {
  local code=$1
  shift
  printf '%b%s%b' "$code" "$*" "$C_RESET"
}
