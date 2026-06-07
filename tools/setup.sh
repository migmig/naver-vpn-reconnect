#!/bin/bash
#
# tools/setup.sh — 대화형 초기 설정 ('make setup' 이 호출)
#   - $HOME/.config/naver-vpn/config 작성
#   - VPN 비밀번호를 macOS 키체인에 저장
#
set -euo pipefail

CONFDIR="$HOME/.config/naver-vpn"
CONF="$CONFDIR/config"
mkdir -p "$CONFDIR"

if [ -z "${C_RESET+x}" ]; then
  if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'; C_DIM=$'\033[2m'; C_RED=$'\033[31m'
    C_GREEN=$'\033[32m'; C_YELLOW=$'\033[33m'; C_CYAN=$'\033[36m'
  else C_RESET=; C_BOLD=; C_DIM=; C_RED=; C_GREEN=; C_YELLOW=; C_CYAN=; fi
fi
okm(){   printf '%s✅ %s%s\n'  "$C_GREEN"  "$*" "$C_RESET"; }
warn(){  printf '%s⚠️  %s%s\n' "$C_YELLOW" "$*" "$C_RESET"; }
errm(){  printf '%s❌ %s%s\n'  "$C_RED"    "$*" "$C_RESET"; }
info(){  printf '%s   ℹ️  %s%s\n' "$C_CYAN"   "$*" "$C_RESET"; }
sec(){   printf '\n%s%s %s%s\n' "$C_BOLD$C_CYAN" "$1" "$2" "$C_RESET"; }
# ask <var> <label> <default>
ask(){
  local _p
  if [ -n "${3:-}" ]; then
    printf -v _p '   %s›%s %s %s[%s]%s: ' "$C_CYAN" "$C_RESET" "$2" "$C_DIM" "$3" "$C_RESET"
  else
    printf -v _p '   %s›%s %s: ' "$C_CYAN" "$C_RESET" "$2"
  fi
  read -r -p "$_p" "$1"
}

# 기존 설정 있으면 기본값으로 활용
OLD_USER=""; OLD_DOM=""; OLD_OVPN=""; OLD_TGT=""; OLD_ALIAS=""
if [ -f "$CONF" ]; then
  # shellcheck disable=SC1090
  . "$CONF" || true
  OLD_USER="${VPN_USER:-}"; OLD_DOM="${DOMAIN:-}"; OLD_OVPN="${OVPN_NAME:-}"; OLD_TGT="${TARGET:-}"; OLD_ALIAS="${ALIAS:-}"
fi
ALIAS_VAL="${OLD_ALIAS:-vpn}"   # 별칭 이름은 'make install' 에서 정함; 여기선 기존값 보존

DEF_DOM="${OLD_DOM:-https://sslvpn-kr-vpc-01.gov-ncloud.com:8443}"
DEF_TGT="${OLD_TGT:-10.0.0.4}"

# 프로필 이름(OVPN_NAME)은 계정별 식별자다. 기존 설정 → NAVER 앱이 받아둔
# 로컬 프로필 → 마지막 폴백 순으로 기본값을 정한다.
PROFD="$HOME/Library/Application Support/ncurion-sa-client/vpn/profiles"
DETECTED_OVPN="$(ls -t "$PROFD"/*.ovpn 2>/dev/null | head -1 | xargs -I{} basename {} 2>/dev/null || true)"
DEF_OVPN="${OLD_OVPN:-${DETECTED_OVPN:-vpn2033.ovpn}}"

# ---- 상단 프레임 ----
printf '\n%s╭─%s %s📡 NAVER Cloud SSL VPN 설정%s %s──────────────%s\n' "$C_DIM" "$C_RESET" "$C_BOLD$C_CYAN" "$C_RESET" "$C_DIM" "$C_RESET"
printf '%s│%s  %s설정 파일과 키체인 비밀번호를 만듭니다.%s\n' "$C_DIM" "$C_RESET" "$C_DIM" "$C_RESET"
printf '%s╰──────────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"

# ---- 기본 설정 ----
sec "🔧" "기본 설정"
if [ -z "${OLD_OVPN:-}" ] && [ -n "$DETECTED_OVPN" ]; then
  info "NAVER 앱 프로필에서 OVPN_NAME 자동 감지: $DETECTED_OVPN"
elif [ -z "${OLD_OVPN:-}" ] && [ -z "$DETECTED_OVPN" ]; then
  warn "로컬에 .ovpn 프로필이 없습니다 — NAVER 앱으로 한 번 로그인하면 자동 감지됩니다."
fi
ask VU "VPN 아이디"   "$OLD_USER"; VU="${VU:-$OLD_USER}"
[ -n "$VU" ] || { errm "아이디는 필수입니다."; exit 1; }
ask DM "포털 도메인"   "$DEF_DOM";  DM="${DM:-$DEF_DOM}"
ask OV "프로필 파일명" "$DEF_OVPN"; OV="${OV:-$DEF_OVPN}"
info "터널 IP·게이트웨이는 사람마다 달라 자동 감지합니다 (입력 불필요)."

# ---- keepalive ----
sec "🔁" "keepalive (유휴 끊김 방지)"
OLD_KA="${KEEPALIVE:-1}"; OLD_KAH="${KEEPALIVE_HOST:-}"; OLD_KAI="${KEEPALIVE_INTERVAL:-60}"
ask KA "사용하시겠어요? (Y/n)" "$([ "$OLD_KA" = 0 ] && echo n || echo Y)"
case "${KA:-y}" in [Nn]*) KAV="0";; *) KAV="1";; esac
KAH="$OLD_KAH"; KAI="$OLD_KAI"
if [ "$KAV" = "1" ]; then
  ask KAH "핑 대상 게이트웨이 (비우면 자동)" "${OLD_KAH:-자동}"
  [ "$KAH" = "자동" ] && KAH=""
  ask KAI "주기(초)" "$OLD_KAI"; KAI="${KAI:-$OLD_KAI}"
fi

umask 077
cat > "$CONF" <<EOF
# naver-vpn 설정 — 'make setup' 으로 생성됨
VPN_USER="$VU"
DOMAIN="$DM"
OVPN_NAME="$OV"
CLIENT_VERSION="1.1.3"
KC_SERVICE="naver-vpn"
# TARGET: 연결 확인은 openvpn 로그로 자동 판단한다. 특정 IP 도 확인하려면 지정(선택).
TARGET=""
# 단축 명령(별칭) 이름 — 'make install' 에서 정하고 갱신한다.
ALIAS="$ALIAS_VAL"
# MAC_JSON 을 비워두면 실행 시 자동탐지한다.
# 특정 값으로 고정하려면: MAC_JSON='["AA-BB-CC-DD-EE-FF"]'
MAC_JSON=""

# keepalive (유휴 끊김 방지)
KEEPALIVE="$KAV"
KEEPALIVE_INTERVAL="$KAI"
KEEPALIVE_HOST="$KAH"
KEEPALIVE_FAILS="3"
EOF
chmod 600 "$CONF"
echo
okm "설정 저장: $CONF"

# ---- 비밀번호 ----
sec "🔑" "비밀번호"
printf '   %s키체인에 저장합니다 (입력은 화면에 안 보이고, 두 번 입력)%s\n' "$C_DIM" "$C_RESET"
security add-generic-password -U -s naver-vpn -a "$VU" -w
okm "비밀번호 저장 완료 $(printf '%s(키체인 naver-vpn / %s)%s' "$C_DIM" "$VU" "$C_RESET")"

# ---- 마무리 ----
printf '\n%s├──────────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"
printf '%s│%s  %s▶ 다음 단계%s  %smake install%s %s→%s  naver-vpn 으로 연결\n' "$C_DIM" "$C_RESET" "$C_BOLD" "$C_RESET" "$C_CYAN" "$C_RESET" "$C_DIM" "$C_RESET"
printf '%s╰──────────────────────────────────────────────%s\n\n' "$C_DIM" "$C_RESET"
