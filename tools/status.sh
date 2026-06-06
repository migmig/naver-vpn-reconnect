#!/bin/bash
# tools/status.sh — 설치/설정/연결 상태 출력 ('make status')
set -u

BINDIR="${1:-/usr/local/bin}"
SBINDIR="${2:-/usr/local/sbin}"
SUDOERSD="${3:-/etc/sudoers.d}"
CONF="$HOME/.config/naver-vpn/config"

if [ -z "${C_RESET+x}" ]; then
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_RED=$'\033[31m'; C_BOLD=$'\033[1m'
  else C_RESET=; C_GREEN=; C_RED=; C_BOLD=; fi
fi
ok(){ printf "  %s✔%s %s\n" "$C_GREEN" "$C_RESET" "$1"; }
no(){ printf "  %s✗%s %s\n" "$C_RED" "$C_RESET" "$1"; }

printf '%s== 설치 상태 ==%s\n' "$C_BOLD" "$C_RESET"
[ -x "$BINDIR/naver-vpn" ] && ok "client    $BINDIR/naver-vpn" || no "client    미설치"
[ -x "$BINDIR/naver-vpn-keepalive" ] && ok "keepalive $BINDIR/naver-vpn-keepalive" || no "keepalive 미설치"
AL="$( . "$HOME/.config/naver-vpn/config" 2>/dev/null; echo "${ALIAS:-}" )"
if [ -n "$AL" ] && [ -L "$BINDIR/$AL" ] && [ "$(readlink "$BINDIR/$AL")" = "naver-vpn" ]; then
  ok "alias     $BINDIR/$AL → naver-vpn"
else
  no "alias     별칭 없음 (make install 에서 지정)"
fi
[ -x "$SBINDIR/naver-vpn-up" ] && ok "wrapper   $SBINDIR/naver-vpn-up" || no "wrapper   미설치"
[ -f "$SUDOERSD/naver-vpn" ] && ok "sudoers   $SUDOERSD/naver-vpn (NOPASSWD)" || no "sudoers   미설치 (연결 시 비번 필요)"

printf '%s== 설정 ==%s\n' "$C_BOLD" "$C_RESET"
if [ -f "$CONF" ]; then
  # shellcheck disable=SC1090
  . "$CONF" 2>/dev/null || true
  ok "config    $CONF (user=${VPN_USER:-?})"
  if security find-generic-password -s "${KC_SERVICE:-naver-vpn}" -a "${VPN_USER:-}" >/dev/null 2>&1; then
    ok "keychain  비밀번호 저장됨"
  else
    no "keychain  비밀번호 없음 (make setup)"
  fi
else
  no "config    없음 (make setup)"
fi

printf '%s== 연결 ==%s\n' "$C_BOLD" "$C_RESET"
TGT="${TARGET:-10.0.0.4}"
if ifconfig 2>/dev/null | grep -q "inet ${TGT} "; then
  ok "tunnel    $TGT 활성"
elif ping -c1 -t2 "$TGT" >/dev/null 2>&1; then
  ok "reach     $TGT 접근 가능"
else
  no "tunnel    연결 안됨 (naver-vpn 으로 연결)"
fi

KAPID="$HOME/.config/naver-vpn/keepalive.pid"
if [ -f "$KAPID" ] && kill -0 "$(cat "$KAPID" 2>/dev/null)" 2>/dev/null; then
  ok "keepalive 실행중 (pid $(cat "$KAPID"), ${KEEPALIVE_INTERVAL:-60}s → ${KEEPALIVE_HOST:-10.0.0.1})"
else
  no "keepalive 중지됨"
fi
