#!/bin/bash
# tools/status.sh — 설치/설정/연결 상태 출력 ('make status')
set -u

BINDIR="${1:-/usr/local/bin}"
SBINDIR="${2:-/usr/local/sbin}"
SUDOERSD="${3:-/etc/sudoers.d}"
CONF="$HOME/.config/naver-vpn/config"

# ---- 색 (make export 사용, 단독 실행 시 TTY 감지) ----
if [ -z "${C_RESET+x}" ]; then
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'
  else C_RESET=; C_BOLD=; C_DIM=; C_RED=; C_GREEN=; C_YELLOW=; C_CYAN=; fi
fi

LW=10   # 라벨 폭(ASCII)
sec(){ printf '\n%s%s▸ %s%s\n' "$C_BOLD" "$C_CYAN" "$1" "$C_RESET"; }
# row <ok|warn|no> <label> <value>
row(){
  local g c
  case "$1" in
    ok)   g='✔'; c="$C_GREEN"  ;;
    warn) g='!'; c="$C_YELLOW" ;;
    *)    g='✗'; c="$C_RED"    ;;
  esac
  printf '   %s%s%s  %s%-*s%s %s\n' "$c" "$g" "$C_RESET" "$C_DIM" "$LW" "$2" "$C_RESET" "$3"
}
dimp(){ printf '%s%s%s' "$C_DIM" "$1" "$C_RESET"; }   # 경로 등 흐리게

printf '\n %s%s NAVER Cloud SSL VPN — 상태 %s\n' "$C_BOLD" "$C_CYAN" "$C_RESET"

# ===== 설치 =====
sec "설치"
[ -x "$BINDIR/naver-vpn" ]           && row ok   "client"    "$(dimp "$BINDIR/naver-vpn")"           || row no   "client"    "미설치"
[ -x "$BINDIR/naver-vpn-keepalive" ] && row ok   "keepalive" "$(dimp "$BINDIR/naver-vpn-keepalive")" || row no   "keepalive" "미설치"
AL="$( . "$CONF" 2>/dev/null; echo "${ALIAS:-}" )"
if [ -n "$AL" ] && [ -L "$BINDIR/$AL" ] && [ "$(readlink "$BINDIR/$AL")" = "naver-vpn" ]; then
  row ok   "alias"     "$C_CYAN$AL$C_RESET $(dimp "→ naver-vpn")"
else
  row warn "alias"     "없음 $(dimp "(make install 에서 지정)")"
fi
[ -x "$SBINDIR/naver-vpn-up" ]       && row ok   "wrapper"   "$(dimp "$SBINDIR/naver-vpn-up")"       || row no   "wrapper"   "미설치"
[ -f "$SUDOERSD/naver-vpn" ]         && row ok   "sudoers"   "NOPASSWD $(dimp "$SUDOERSD/naver-vpn")" || row warn "sudoers"   "미설치 $(dimp "(연결 시 맥 비번 필요)")"

# ===== 설정 =====
sec "설정"
if [ -f "$CONF" ]; then
  # shellcheck disable=SC1090
  . "$CONF" 2>/dev/null || true
  row ok "config"   "user=$C_BOLD${VPN_USER:-?}$C_RESET  $(dimp "ovpn=${OVPN_NAME:-?}")"
  if security find-generic-password -s "${KC_SERVICE:-naver-vpn}" -a "${VPN_USER:-}" >/dev/null 2>&1; then
    row ok "keychain" "비밀번호 저장됨"
  else
    row no "keychain" "비밀번호 없음 $(dimp "(make setup)")"
  fi
else
  row no "config"   "없음 $(dimp "(make setup)")"
fi

# ===== 연결 =====
sec "연결"
TGT="${TARGET:-10.0.0.4}"
CONNECTED=0
if ifconfig 2>/dev/null | grep -q "inet ${TGT} "; then
  row ok "tunnel"  "$C_GREEN$TGT 활성$C_RESET"; CONNECTED=1
elif ping -c1 -t2 "$TGT" >/dev/null 2>&1; then
  row ok "tunnel"  "$TGT 접근 가능"; CONNECTED=1
else
  row no "tunnel"  "연결 안됨 $(dimp "(naver-vpn 으로 연결)")"
fi
KAPID="$HOME/.config/naver-vpn/keepalive.pid"
if [ -f "$KAPID" ] && kill -0 "$(cat "$KAPID" 2>/dev/null)" 2>/dev/null; then
  row ok   "keepalive" "실행중 $(dimp "pid $(cat "$KAPID") · ${KEEPALIVE_INTERVAL:-60}s → ${KEEPALIVE_HOST:-10.0.0.1}")"
else
  row warn "keepalive" "중지됨"
fi

# ===== 요약 =====
if [ "$CONNECTED" = 1 ]; then
  printf '\n %s● VPN 연결됨%s\n\n' "$C_GREEN" "$C_RESET"
else
  printf '\n %s○ VPN 연결 안됨%s  %s→ naver-vpn 으로 연결%s\n\n' "$C_RED" "$C_RESET" "$C_DIM" "$C_RESET"
fi
