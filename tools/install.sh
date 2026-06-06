#!/bin/bash
#
# tools/install.sh — 클라이언트 + keepalive + root 래퍼 + NOPASSWD sudoers 설치.
# 'make install' 이 환경변수(PREFIX/BINDIR/...)를 넘겨 호출한다.
# 단축 명령(alias) 이름을 대화형으로 정하고 config 에 기록한다.
#   비대화형/지정: make install ALIAS=nvpn   (또는 ALIAS=- 로 별칭 생략)
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
PROJ="$(cd "$(dirname "$0")/.." && pwd)"

# ---- 색 (make 가 export 한 값 사용, 단독 실행 시 TTY 감지) ----
if [ -z "${C_RESET+x}" ]; then
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_BLUE=$'\033[34m'; C_CYAN=$'\033[36m'
  else C_RESET=; C_BOLD=; C_DIM=; C_RED=; C_GREEN=; C_YELLOW=; C_BLUE=; C_CYAN=; fi
fi
hdr(){  printf '%s==>%s %s\n' "$C_BLUE"   "$C_RESET" "$*"; }
okm(){  printf '%s✅ %s%s\n'  "$C_GREEN"  "$*" "$C_RESET"; }
warn(){ printf '%s⚠️  %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
errm(){ printf '%s❌ %s%s\n'  "$C_RED"    "$*" "$C_RESET"; }

[ "$(id -u)" = "0" ] && { errm "'sudo make install' 말고 'make install' 로 실행하세요 (필요할 때만 sudo 가 호출됩니다)."; exit 1; }

# ---- 단축 명령(alias) 이름 결정 ----
# 우선순위: 환경변수 ALIAS > 기존 config 의 ALIAS > 기본 'vpn'
CUR_ALIAS="vpn"
[ -f "$CONF" ] && CUR_ALIAS="$( . "$CONF" 2>/dev/null; echo "${ALIAS:-vpn}" )"
ALIAS_NAME="${ALIAS:-}"
if [ -z "$ALIAS_NAME" ]; then
  if [ -t 0 ]; then
    printf '%s단축 명령(alias) 이름을 정하세요.%s %s'\''naver-vpn'\'' 은 항상 설치되며, 이건 추가 별칭입니다.%s\n' "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
    read -r -p "$(printf '  별칭 [%s%s%s]  (별칭 없이 가려면 '\''-'\'' 입력): ' "$C_CYAN" "$CUR_ALIAS" "$C_RESET")" ALIAS_NAME
    ALIAS_NAME="${ALIAS_NAME:-$CUR_ALIAS}"
  else
    ALIAS_NAME="$CUR_ALIAS"
  fi
fi
# 검증
if [ "$ALIAS_NAME" = "-" ]; then
  ALIAS_NAME=""
else
  case "$ALIAS_NAME" in
    naver-vpn|naver-vpn-keepalive) errm "'$ALIAS_NAME' 는 기본 명령과 충돌합니다. 다른 이름을 쓰세요."; exit 1 ;;
    *[!a-zA-Z0-9_-]*|"") errm "별칭은 영문/숫자/_/- 만 사용할 수 있습니다."; exit 1 ;;
  esac
  # 우리 심볼릭이 아닌 동일 이름 명령이 이미 있으면 경고
  if command -v "$ALIAS_NAME" >/dev/null 2>&1; then
    existing="$(command -v "$ALIAS_NAME")"
    if ! { [ -L "$existing" ] && [ "$(readlink "$existing")" = "naver-vpn" ]; }; then
      warn "이미 '$ALIAS_NAME' 명령이 존재합니다: $existing — 덮어쓰지 않고 진행합니다(아래 PATH 우선순위 주의)."
    fi
  fi
fi

# ---- 설치 ----
hdr "클라이언트 설치: $BINDIR/naver-vpn  (+ keepalive)"
sudo install -d -o root -g wheel -m 0755 "$BINDIR" "$SBINDIR"
sudo install -o root -g wheel -m 0755 "$PROJ/bin/naver-vpn"           "$BINDIR/naver-vpn"
sudo install -o root -g wheel -m 0755 "$PROJ/bin/naver-vpn-keepalive" "$BINDIR/naver-vpn-keepalive"

# 별칭(이전 이름과 다르면 옛 심볼릭 제거 후 새로 생성)
if [ -n "$CUR_ALIAS" ] && [ "$CUR_ALIAS" != "$ALIAS_NAME" ] \
   && [ -L "$BINDIR/$CUR_ALIAS" ] && [ "$(readlink "$BINDIR/$CUR_ALIAS")" = "naver-vpn" ]; then
  sudo rm -f "$BINDIR/$CUR_ALIAS"; hdr "옛 별칭 제거: $BINDIR/$CUR_ALIAS"
fi
if [ -n "$ALIAS_NAME" ]; then
  sudo ln -sf naver-vpn "$BINDIR/$ALIAS_NAME"; hdr "별칭 생성: $BINDIR/$ALIAS_NAME → naver-vpn"
else
  hdr "별칭 없이 설치 (naver-vpn 명령만 사용)"
fi

hdr "root 래퍼 설치: $SBINDIR/naver-vpn-up  (HOME=$HOMEDIR)"
sed "s#@HOME@#$HOMEDIR#g" "$PROJ/sbin/naver-vpn-up.in" > /tmp/naver-vpn-up.gen
sudo install -o root -g wheel -m 0755 /tmp/naver-vpn-up.gen "$SBINDIR/naver-vpn-up"
rm -f /tmp/naver-vpn-up.gen

hdr "sudoers 설치: $SUDOERSD/naver-vpn  (user=$REALUSER)"
sed "s#@USER@#$REALUSER#g" "$PROJ/etc/naver-vpn.sudoers.in" > /tmp/naver-vpn.sudoers.gen
sudo visudo -cf /tmp/naver-vpn.sudoers.gen
sudo install -o root -g wheel -m 0440 /tmp/naver-vpn.sudoers.gen "$SUDOERSD/naver-vpn"
rm -f /tmp/naver-vpn.sudoers.gen

# ---- 선택한 별칭을 config 에 기록 ----
mkdir -p "$CONFDIR"
if [ -f "$CONF" ]; then
  if grep -q '^ALIAS=' "$CONF"; then
    tmp="$(mktemp)"; sed "s|^ALIAS=.*|ALIAS=\"$ALIAS_NAME\"|" "$CONF" > "$tmp" && cat "$tmp" > "$CONF" && rm -f "$tmp"
  else
    printf 'ALIAS="%s"\n' "$ALIAS_NAME" >> "$CONF"
  fi
else
  umask 077; printf 'ALIAS="%s"\n' "$ALIAS_NAME" > "$CONF"
fi

echo ""
okm "설치 완료."
[ -f "$CONF" ] && grep -q '^VPN_USER=' "$CONF" || warn "아직 설정이 없습니다 — 'make setup' 을 실행하세요."
if grep -qs 'alias[[:space:]]\+vpn' "$HOMEDIR/.zshrc"; then
  warn "~/.zshrc 의 'alias vpn' 이 $BINDIR 의 명령보다 우선합니다. 그 줄을 지우세요."
fi
case ":$PATH:" in *":$BINDIR:"*) ;; *) warn "$BINDIR 가 PATH 에 없습니다. 전체경로로 실행하거나 PATH 에 추가하세요.";; esac
if [ -n "$ALIAS_NAME" ]; then printf '   %s실행:%s  %s%s%s   (또는 naver-vpn)\n' "$C_DIM" "$C_RESET" "$C_CYAN" "$ALIAS_NAME" "$C_RESET"
else printf '   %s실행:%s  %snaver-vpn%s\n' "$C_DIM" "$C_RESET" "$C_CYAN" "$C_RESET"; fi
