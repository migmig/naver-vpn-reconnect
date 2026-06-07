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
ftop(){ printf '\n%s╭─%s %s📦 NAVER Cloud SSL VPN 설치%s %s──────────────%s\n' "$C_DIM" "$C_RESET" "$C_BOLD$C_CYAN" "$C_RESET" "$C_DIM" "$C_RESET"; }
fmid(){ printf '%s├──────────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"; }
fbot(){ printf '%s╰──────────────────────────────────────────────%s\n\n' "$C_DIM" "$C_RESET"; }
line(){ printf '%s│%s  %s\n' "$C_DIM" "$C_RESET" "$*"; }
sec(){  printf '%s│%s  %s%s %s%s\n' "$C_DIM" "$C_RESET" "$C_BOLD$C_CYAN" "$1" "$2" "$C_RESET"; }
bar(){  printf '%s│%s\n' "$C_DIM" "$C_RESET"; }
dim(){  printf '%s%s%s' "$C_DIM" "$1" "$C_RESET"; }
okm(){  printf '%s✅ %s%s\n'  "$C_GREEN"  "$*" "$C_RESET"; }
warn(){ printf '%s⚠️  %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
errm(){ printf '%s❌ %s%s\n'  "$C_RED"    "$*" "$C_RESET"; }

[ "$(id -u)" = "0" ] && { errm "'sudo make install' 말고 'make install' 로 실행하세요 (필요할 때만 sudo 가 호출됩니다)."; exit 1; }

# ---- 단축 명령(alias) 이름 결정 ----
# 우선순위: 환경변수 ALIAS > 기존 config 의 ALIAS > 기본 'vpn'
CUR_ALIAS="vpn"
[ -f "$CONF" ] && CUR_ALIAS="$( . "$CONF" 2>/dev/null; echo "${ALIAS:-vpn}" )"
ALIAS_NAME="${ALIAS:-}"

ftop
# ---- 별칭 ----
sec "🏷" "단축 명령(별칭)"
if [ -z "$ALIAS_NAME" ]; then
  if [ -t 0 ]; then
    line "$(dim "'naver-vpn' 은 항상 설치됩니다. 추가 별칭을 정하세요 ('-' 입력 시 없음).")"
    printf -v _ap '%s│%s  %s›%s 별칭 %s[%s]%s: ' "$C_DIM" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_DIM" "$CUR_ALIAS" "$C_RESET"
    read -r -p "$_ap" ALIAS_NAME
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
    naver-vpn|naver-vpn-keepalive) line "❌ '$ALIAS_NAME' 는 기본 명령과 충돌합니다."; fbot; exit 1 ;;
    *[!a-zA-Z0-9_-]*|"") line "❌ 별칭은 영문/숫자/_/- 만 가능합니다."; fbot; exit 1 ;;
  esac
  if command -v "$ALIAS_NAME" >/dev/null 2>&1; then
    existing="$(command -v "$ALIAS_NAME")"
    if ! { [ -L "$existing" ] && [ "$(readlink "$existing")" = "naver-vpn" ]; }; then
      line "⚠️  이미 '$ALIAS_NAME' 명령 존재 $(dim "$existing — 덮어쓰지 않음")"
    fi
  fi
fi
[ -n "$ALIAS_NAME" ] && line "$(dim "별칭 →") $C_CYAN${ALIAS_NAME}$C_RESET" || line "$(dim "별칭 없이 설치")"

# ---- 권한 안내 ----
bar
sec "🔐" "권한"
line "$(dim "잠시 후 ")맥 관리자(sudo) 비밀번호$(dim "를 물어볼 수 있습니다.")"
line "$(dim "VPN 비밀번호가 아니라, 이 컴퓨터(macOS) 로그인 암호입니다.")"

# ---- 설치 ----
bar
sec "📂" "설치"
sudo install -d -o root -g wheel -m 0755 "$BINDIR" "$SBINDIR"
sudo install -o root -g wheel -m 0755 "$PROJ/bin/naver-vpn"           "$BINDIR/naver-vpn"
sudo install -o root -g wheel -m 0755 "$PROJ/bin/naver-vpn-keepalive" "$BINDIR/naver-vpn-keepalive"
line "✅ 클라이언트  $(dim "$BINDIR/naver-vpn (+ keepalive)")"

if [ -n "$CUR_ALIAS" ] && [ "$CUR_ALIAS" != "$ALIAS_NAME" ] \
   && [ -L "$BINDIR/$CUR_ALIAS" ] && [ "$(readlink "$BINDIR/$CUR_ALIAS")" = "naver-vpn" ]; then
  sudo rm -f "$BINDIR/$CUR_ALIAS"; line "✅ 옛 별칭 제거  $(dim "$BINDIR/$CUR_ALIAS")"
fi
if [ -n "$ALIAS_NAME" ]; then
  sudo ln -sf naver-vpn "$BINDIR/$ALIAS_NAME"; line "✅ 별칭        $(dim "$BINDIR/$ALIAS_NAME → naver-vpn")"
fi

sed "s#@HOME@#$HOMEDIR#g" "$PROJ/sbin/naver-vpn-up.in" > /tmp/naver-vpn-up.gen
sudo install -o root -g wheel -m 0755 /tmp/naver-vpn-up.gen "$SBINDIR/naver-vpn-up"
rm -f /tmp/naver-vpn-up.gen
line "✅ root 래퍼   $(dim "$SBINDIR/naver-vpn-up")"

sed "s#@USER@#$REALUSER#g" "$PROJ/etc/naver-vpn.sudoers.in" > /tmp/naver-vpn.sudoers.gen
sudo visudo -cf /tmp/naver-vpn.sudoers.gen >/dev/null
sudo install -o root -g wheel -m 0440 /tmp/naver-vpn.sudoers.gen "$SUDOERSD/naver-vpn"
rm -f /tmp/naver-vpn.sudoers.gen
line "✅ sudoers     $(dim "NOPASSWD $SUDOERSD/naver-vpn")"

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

# ---- 마무리 ----
bar
{ [ -f "$CONF" ] && grep -q '^VPN_USER=' "$CONF"; } || line "⚠️  아직 설정이 없습니다 — $C_CYAN make setup$C_RESET 을 실행하세요."
grep -qs 'alias[[:space:]]\+vpn' "$HOMEDIR/.zshrc" && line "⚠️  ~/.zshrc 의 'alias vpn' 이 우선합니다 — 그 줄을 지우세요."
case ":$PATH:" in *":$BINDIR:"*) ;; *) line "⚠️  $BINDIR 가 PATH 에 없습니다.";; esac
fmid
if [ -n "$ALIAS_NAME" ]; then
  printf '%s│%s  %s🎉 설치 완료%s  %s실행:%s %s%s%s %s(또는 naver-vpn)%s\n' "$C_DIM" "$C_RESET" "$C_GREEN$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET" "$C_CYAN" "$ALIAS_NAME" "$C_RESET" "$C_DIM" "$C_RESET"
else
  printf '%s│%s  %s🎉 설치 완료%s  %s실행: naver-vpn%s\n' "$C_DIM" "$C_RESET" "$C_GREEN$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
fi
fbot
