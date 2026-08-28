#!/bin/zsh
# 安装 Mac 端用户级命令并保留旧版本备份。

set -euo pipefail

typeset -gr SRC_DIR="${0:A:h}"
typeset -gr DST_DIR="$HOME/.local/lib/macwinpwrmgr"
typeset -gr BIN_DIR="$HOME/.local/bin"
typeset -gr LINK_PATH="$BIN_DIR/winctl"
typeset -gr BAK_DIR="$HOME/.local/share/macwinpwrmgr/backup-$(/bin/date +%Y%m%d-%H%M%S)"

# 备份现有用户级安装。
bkpold() {
  if [[ -e "$DST_DIR" || -L "$LINK_PATH" || -e "$LINK_PATH" ]]; then
    /bin/mkdir -p "$BAK_DIR"
    [[ -e "$DST_DIR" ]] && /bin/cp -R "$DST_DIR" "$BAK_DIR/"
    [[ -L "$LINK_PATH" || -e "$LINK_PATH" ]] && /bin/cp -P "$LINK_PATH" "$BAK_DIR/"
  fi
}

# 安装脚本与命令链接。
instll() {
  [[ -f "$SRC_DIR/config.zsh" ]] || {
    print -ru2 -- "macwinpwrmgr: copy config.example.zsh to config.zsh and edit it first"
    return 2
  }
  bkpold
  /bin/mkdir -p "$DST_DIR" "$BIN_DIR"
  /bin/cp "$SRC_DIR/config.zsh" "$SRC_DIR/head.zsh" "$SRC_DIR/winctl.zsh" "$DST_DIR/"
  /bin/chmod 0755 "$DST_DIR/winctl.zsh"
  /bin/ln -sfn "$DST_DIR/winctl.zsh" "$LINK_PATH"
  print -r -- "installed: $LINK_PATH"
}

instll
