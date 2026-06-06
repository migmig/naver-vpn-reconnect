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
OLD_USER=""; OLD_DOM=""; OLD_OVPN=""; OLD_TGT=""
if [ -f "$CONF" ]; then
  # shellcheck disable=SC1090
  . "$CONF" || true
  OLD_USER="${VPN_USER:-}"; OLD_DOM="${DOMAIN:-}"; OLD_OVPN="${OVPN_NAME:-}"; OLD_TGT="${TARGET:-}"
fi

DEF_DOM="${OLD_DOM:-https://sslvpn-kr-vpc-01.gov-ncloud.com:8443}"
DEF_OVPN="${OLD_OVPN:-vpn2033.ovpn}"
DEF_TGT="${OLD_TGT:-10.0.0.4}"

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
