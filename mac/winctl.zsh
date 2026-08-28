#!/bin/zsh
# 提供 Mac 端唤醒、调用、状态与安全睡眠入口。

set -euo pipefail
typeset -gr MWP_BIN_DIR="${0:A:h}"
source "$MWP_BIN_DIR/head.zsh"

# 显示命令帮助。
usage() {
  print -r -- "usage:
  winctl.zsh wake
  winctl.zsh run '<PowerShell 7 command>'
  winctl.zsh status
  winctl.zsh sleep"
}

# 唤醒并等待 Windows 就绪。
wakeup() {
  local attempt
  for attempt in 1 2 3; do
    sndwol
    "$SLEEP_BIN" 1
  done
  waitssh 5
  print -r -- "Windows is ready at $WIN_HOST"
}

# 在原生电源租约内运行一个远程命令。
rncmd() {
  (( $# == 1 )) || prterr "run requires one quoted PowerShell command string"
  wakeup >/dev/null
  local command_rc=0
  print -rn -- "$1" | rnrmt run.ps1 || command_rc=$?
  return "$command_rc"
}

# 查询 Windows 在线与电源状态。
shwst() {
  if "$SSH_BIN" "${SSH_OPTS[@]}" -T "$WIN_HOST" "& '$WIN_ROOT\\status.ps1'"; then
    return 0
  fi
  print -r -- '{"State":"sleeping-or-offline"}'
  return 1
}

# 请求 Windows 按原生安全空闲策略睡眠。
rqslp() {
  rnrmt sleep.ps1
}

# 分派命令行操作。
main() {
  (( $# >= 1 )) || { usage; return 2; }
  vldcfg

  local action="$1"
  shift
  case "$action" in
    wake) (( $# == 0 )) || prterr "wake takes no arguments"; wakeup ;;
    run) rncmd "$@" ;;
    status) (( $# == 0 )) || prterr "status takes no arguments"; shwst ;;
    sleep) (( $# == 0 )) || prterr "sleep takes no arguments"; rqslp ;;
    help|-h|--help) usage ;;
    *) usage; prterr "unknown action: $action" ;;
  esac
}

main "$@"
