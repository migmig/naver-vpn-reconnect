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
if [ -z "${OLD_OVPN:-}" ] && [ -n "$DETECTED_OVPN" ]; then
  echo "ℹ️  NAVER 앱 프로필에서 OVPN_NAME 자동 감지: $DETECTED_OVPN"
elif [ -z "${OLD_OVPN:-}" ] && [ -z "$DETECTED_OVPN" ]; then
  echo "⚠️  로컬에 .ovpn 프로필이 없습니다. NAVER Cloud SSL VPN 앱으로 한 번 로그인하면"
  echo "    프로필이 받아지고 이름을 자동 감지할 수 있습니다. (계정별 식별자, 예: vpnXXXX.ovpn)"
fi

echo "==================== NAVER VPN 설정 ===================="
read -r -p "VPN 아이디${OLD_USER:+ [$OLD_USER]}: " VU; VU="${VU:-$OLD_USER}"
[ -n "$VU" ] || { echo "❌ 아이디는 필수입니다."; exit 1; }
read -r -p "포털 도메인 [$DEF_DOM]: " DM; DM="${DM:-$DEF_DOM}"
read -r -p "프로필 파일명 [$DEF_OVPN]: " OV; OV="${OV:-$DEF_OVPN}"
read -r -p "연결확인 IP [$DEF_TGT]: " TG; TG="${TG:-$DEF_TGT}"

OLD_KA="${KEEPALIVE:-1}"; OLD_KAH="${KEEPALIVE_HOST:-10.0.0.1}"; OLD_KAI="${KEEPALIVE_INTERVAL:-60}"
read -r -p "유휴 끊김 방지(keepalive) 사용? [Y/n]: " KA
case "${KA:-y}" in [Nn]*) KAV="0";; *) KAV="1";; esac
KAH="$OLD_KAH"; KAI="$OLD_KAI"
if [ "$KAV" = "1" ]; then
  read -r -p "  keepalive 핑 대상(게이트웨이) [$OLD_KAH]: " KAH; KAH="${KAH:-$OLD_KAH}"
  read -r -p "  keepalive 주기(초) [$OLD_KAI]: " KAI; KAI="${KAI:-$OLD_KAI}"
fi

umask 077
cat > "$CONF" <<EOF
# naver-vpn 설정 — 'make setup' 으로 생성됨
VPN_USER="$VU"
DOMAIN="$DM"
OVPN_NAME="$OV"
CLIENT_VERSION="1.1.3"
KC_SERVICE="naver-vpn"
TARGET="$TG"
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
echo "✅ 설정 저장: $CONF"
echo

echo "VPN 비밀번호를 키체인에 저장합니다 (입력은 화면에 보이지 않음, 두 번 입력)."
security add-generic-password -U -s naver-vpn -a "$VU" -w
echo "✅ 비밀번호 저장 완료 (키체인 서비스 'naver-vpn', 계정 '$VU')"
echo
echo "다음 단계: 'make install' (root 래퍼 + NOPASSWD 설치) 후  naver-vpn  으로 연결"
