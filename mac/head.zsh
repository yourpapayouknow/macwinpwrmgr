#!/bin/zsh
# 集中定义 Mac 端依赖、校验、WoL 与 SSH 复用逻辑。

set -euo pipefail

typeset -gr MWP_HEAD_DIR="${${(%):-%N}:A:h}"
typeset -gr MWP_CFG_PATH="${MWP_CONFIG:-$MWP_HEAD_DIR/config.zsh}"
[[ -f "$MWP_CFG_PATH" ]] || {
  print -ru2 -- "macwinpwrmgr: config missing; copy config.example.zsh to config.zsh"
  exit 2
}
source "$MWP_CFG_PATH"

typeset -gr SSH_BIN="/usr/bin/ssh"
typeset -gr PERL_BIN="/usr/bin/perl"
typeset -gr SLEEP_BIN="/bin/sleep"
typeset -gr GREP_BIN="/usr/bin/grep"
typeset -gr TR_BIN="/usr/bin/tr"
typeset -gra SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=3)

# 输出错误信息并返回失败。
prterr() {
  print -ru2 -- "macwinpwrmgr: $*"
  return 1
}

# 校验固定环境配置。
vldcfg() {
  local mac_re='^([0-9A-Fa-f]{2}[:-]){5}[0-9A-Fa-f]{2}$'
  [[ "$WIN_MAC" =~ "$mac_re" ]] || prterr "invalid WIN_MAC: $WIN_MAC"
  [[ "$WIN_BCAST" == <0-255>.<0-255>.<0-255>.<0-255> ]] || prterr "invalid WIN_BCAST: $WIN_BCAST"
  (( WIN_WOL_PORT >= 1 && WIN_WOL_PORT <= 65535 )) || prterr "invalid WIN_WOL_PORT: $WIN_WOL_PORT"
  (( WIN_WAIT_SECS >= 1 )) || prterr "invalid WIN_WAIT_SECS: $WIN_WAIT_SECS"
}

# 发送经过验证格式的 Magic Packet。
sndwol() {
  local mac="${1:-$WIN_MAC}"
  local ip="${2:-$WIN_BCAST}"
  local port="${3:-$WIN_WOL_PORT}"

  "$PERL_BIN" -MSocket -e '
    use strict;
    use warnings;
    my ($mac, $ip, $port) = @ARGV;
    die "invalid MAC\n" unless $mac =~ /^(?:[0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i;
    die "invalid port\n" unless $port =~ /^\d+$/ && $port > 0 && $port <= 65535;
    $mac =~ s/[:-]//g;
    my $addr = inet_aton($ip) or die "invalid IPv4 address\n";
    my $pkt = pack("H*", ("ff" x 6) . ($mac x 16));
    socket(my $sock, AF_INET, SOCK_DGRAM, getprotobyname("udp")) or die "socket: $!\n";
    setsockopt($sock, SOL_SOCKET, SO_BROADCAST, 1) or die "broadcast: $!\n";
    send($sock, $pkt, 0, sockaddr_in($port, $addr)) == length($pkt) or die "send: $!\n";
    close($sock) or die "close: $!\n";
  ' "$mac" "$ip" "$port"
}

# 等待 Windows SSH 与 PowerShell 7 同时就绪，并按需重发唤醒包。
waitssh() {
  local wol_interval="${1:-0}"
  local elapsed=0
  while (( elapsed < WIN_WAIT_SECS )); do
    if (( wol_interval > 0 && elapsed % wol_interval == 0 )); then
      sndwol
    fi
    if "$SSH_BIN" "${SSH_OPTS[@]}" "$WIN_HOST" '$PSVersionTable.PSVersion.Major -ge 7' 2>/dev/null | "$TR_BIN" -d '\r' | "$GREP_BIN" -qx True; then
      return 0
    fi
    "$SLEEP_BIN" 1
    (( elapsed += 1 ))
  done
  prterr "Windows did not become ready within ${WIN_WAIT_SECS}s"
}

# 调用已安装的 Windows PowerShell 脚本。
rnrmt() {
  local script="$1"
  "$SSH_BIN" "${SSH_OPTS[@]}" -T "$WIN_HOST" "& '$WIN_ROOT\\$script'; exit \$LASTEXITCODE"
}
