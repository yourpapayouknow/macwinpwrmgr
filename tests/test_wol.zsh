#!/bin/zsh
# 验证 Mac Magic Packet 的长度与完整字节序列。

set -euo pipefail

typeset -gr TEST_DIR="${0:A:h}"
typeset -gx MWP_CONFIG="$TEST_DIR/../mac/config.example.zsh"
source "$TEST_DIR/../mac/head.zsh"

# 启动一次性 UDP 接收器并写出十六进制载荷。
rcvpkt() {
  local port="$1"
  local output="$2"
  "$PERL_BIN" -MSocket -e '
    use strict;
    use warnings;
    my ($port, $path) = @ARGV;
    socket(my $sock, AF_INET, SOCK_DGRAM, getprotobyname("udp")) or die "socket: $!\n";
    bind($sock, sockaddr_in($port, inet_aton("127.0.0.1"))) or die "bind: $!\n";
    my $peer = recv($sock, my $pkt, 2048, 0);
    die "recv failed\n" unless defined $peer;
    open(my $fh, ">", $path) or die "open: $!\n";
    print {$fh} unpack("H*", $pkt);
    close($fh) or die "close: $!\n";
  ' "$port" "$output"
}

# 执行单个字节级 WoL 测试。
tstwol() {
  local tmpdir
  tmpdir="$(/usr/bin/mktemp -d /tmp/macwinpwrmgr-wol.XXXXXX)"
  local output="$tmpdir/payload.hex"
  local port=54321
  local mac_hex="010203040506"
  local expected="ffffffffffff"
  local count
  for count in {1..16}; do expected+="$mac_hex"; done

  rcvpkt "$port" "$output" &
  local receiver=$!
  "$SLEEP_BIN" 1
  sndwol "01:02:03:04:05:06" "127.0.0.1" "$port"
  wait "$receiver"
  [[ "$(<"$output")" == "$expected" ]] || prterr "Magic Packet bytes differ"
  (( ${#expected} == 204 )) || prterr "expected packet is not 102 bytes"
  /bin/rm -rf -- "$tmpdir"
  print -r -- "PASS: Magic Packet is exactly 102 bytes"
}

tstwol
