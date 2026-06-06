#!/bin/bash
#
# tools/uninstall.sh — 설치물 제거. config 의 ALIAS 를 읽어 해당 별칭 심볼릭도 제거한다.
# 'make uninstall' 이 환경변수(BINDIR/...)를 넘겨 호출. (설정/키체인은 유지)
#
set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
BINDIR="${BINDIR:-$PREFIX/bin}"
SBINDIR="${SBINDIR:-$PREFIX/sbin}"
SUDOERSD="${SUDOERSD:-/etc/sudoers.d}"
REALUSER="${REALUSER:-$(id -un)}"
HOMEDIR="${HOMEDIR:-$(eval echo ~"$REALUSER")}"
CONFDIR="${CONFDIR:-$HOMEDIR/.config/naver-vpn}"
CONF="$CONFDIR/config"

if [ -z "${C_RESET+x}" ]; then
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_GREEN=$'\033[32m'; C_BLUE=$'\033[34m'
  else C_RESET=; C_GREEN=; C_BLUE=; fi
fi
hdr(){ printf '%s==>%s %s\n' "$C_BLUE" "$C_RESET" "$*"; }

hdr "설치물 제거"

# keepalive 중지
command -v naver-vpn-keepalive >/dev/null 2>&1 && naver-vpn-keepalive stop >/dev/null 2>&1 || true

# 별칭 심볼릭 제거 (config 의 ALIAS + 혹시 모를 기본 'vpn')
ALIAS_NAME=""
[ -f "$CONF" ] && ALIAS_NAME="$( . "$CONF" 2>/dev/null; echo "${ALIAS:-}" )"
for a in "$ALIAS_NAME" vpn; do
  [ -n "$a" ] || continue
  if [ -L "$BINDIR/$a" ] && [ "$(readlink "$BINDIR/$a")" = "naver-vpn" ]; then
    sudo rm -f "$BINDIR/$a"; echo "    별칭 제거: $BINDIR/$a"
  fi
done

sudo rm -f "$BINDIR/naver-vpn" "$BINDIR/naver-vpn-keepalive" \
           "$SBINDIR/naver-vpn-up" "$SUDOERSD/naver-vpn"

printf '%s✅ 제거 완료%s (설정 %s, 키체인은 유지). 완전삭제: make purge\n' "$C_GREEN" "$C_RESET" "$CONFDIR"
