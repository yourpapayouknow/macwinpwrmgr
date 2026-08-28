#!/bin/zsh
# 将 Mac 端用户级安装移入可恢复目录。

set -euo pipefail

typeset -gr DST_DIR="$HOME/.local/lib/macwinpwrmgr"
typeset -gr LINK_PATH="$HOME/.local/bin/winctl"
typeset -gr REC_DIR="$HOME/.local/share/macwinpwrmgr/removed-$(/bin/date +%Y%m%d-%H%M%S)"

# 移动安装文件以便恢复。
uninst() {
  /bin/mkdir -p "$REC_DIR"
  [[ -e "$DST_DIR" ]] && /bin/mv "$DST_DIR" "$REC_DIR/"
  [[ -L "$LINK_PATH" || -e "$LINK_PATH" ]] && /bin/mv "$LINK_PATH" "$REC_DIR/"
  print -r -- "moved installed files to: $REC_DIR"
}

uninst

