# NAVER Cloud SSL VPN 재연결 — 설치/제거 Makefile
#
#   make setup      대화형 설정 (아이디/도메인 + 키체인 비밀번호)
#   make install    클라이언트 + root 래퍼 + NOPASSWD sudoers 설치 (sudo 필요)
#   make uninstall  설치물 제거 (설정/키체인은 유지)
#   make purge      uninstall + 설정파일/키체인까지 삭제
#   make status     설치/설정/연결 상태 확인
#   make doc        README.md → README.html 생성
#
PREFIX   ?= /usr/local
BINDIR    := $(PREFIX)/bin
SBINDIR   := $(PREFIX)/sbin
SUDOERSD  := /etc/sudoers.d
REALUSER  := $(if $(SUDO_USER),$(SUDO_USER),$(shell id -un))
HOMEDIR   := $(shell eval echo ~$(REALUSER))
CONFDIR   := $(HOMEDIR)/.config/naver-vpn

.DEFAULT_GOAL := help

help:
	@echo "NAVER VPN 재연결 — 사용 가능한 명령:"
	@echo "  make setup      대화형 설정 (아이디 + 키체인 비밀번호)"
	@echo "  make install    설치 (클라이언트 + root 래퍼 + NOPASSWD)   [sudo]"
	@echo "  make uninstall  제거 (설정/키체인 유지)                    [sudo]"
	@echo "  make purge      완전 삭제 (설정/키체인 포함)               [sudo]"
	@echo "  make status     상태 확인"
	@echo "  make doc        README.html 생성"
	@echo ""
	@echo "처음이라면:  make setup  →  make install  →  naver-vpn"

# ---- 설정 (root 불필요) ----
setup:
	@if [ "$$(id -u)" = "0" ]; then echo "❌ 'sudo make setup' 말고 'make setup' 으로 실행하세요."; exit 1; fi
	@bash tools/setup.sh

# ---- 설치 (root 래퍼/sudoers 는 sudo 필요) ----
# 단축 명령 이름을 대화형으로 정함. 지정하려면: make install ALIAS=nvpn  (생략은 ALIAS=-)
install:
	@PREFIX="$(PREFIX)" BINDIR="$(BINDIR)" SBINDIR="$(SBINDIR)" SUDOERSD="$(SUDOERSD)" \
	  REALUSER="$(REALUSER)" HOMEDIR="$(HOMEDIR)" CONFDIR="$(CONFDIR)" ALIAS="$(ALIAS)" \
	  bash tools/install.sh

# ---- 제거 (설정/키체인 유지) ----
uninstall:
	@PREFIX="$(PREFIX)" BINDIR="$(BINDIR)" SBINDIR="$(SBINDIR)" SUDOERSD="$(SUDOERSD)" \
	  REALUSER="$(REALUSER)" HOMEDIR="$(HOMEDIR)" CONFDIR="$(CONFDIR)" \
	  bash tools/uninstall.sh

# ---- 완전 삭제 ----
purge: uninstall
	@echo "==> 설정/키체인 삭제"
	@if [ -f $(CONFDIR)/config ]; then \
	  . $(CONFDIR)/config 2>/dev/null; \
	  security delete-generic-password -s "$${KC_SERVICE:-naver-vpn}" -a "$$VPN_USER" >/dev/null 2>&1 \
	    && echo "   키체인 항목 삭제됨" || true; \
	fi
	rm -rf $(CONFDIR)
	@echo "✅ 완전 삭제 완료"

# ---- 상태 ----
status:
	@bash tools/status.sh $(BINDIR) $(SBINDIR) $(SUDOERSD)

# ---- 문서 ----
doc: README.html
README.html: README.md tools/md2html.py
	@if command -v pandoc >/dev/null 2>&1; then \
	  pandoc -s --metadata title="NAVER VPN Reconnect" -o README.html README.md; \
	else \
	  python3 tools/md2html.py README.md README.html; \
	fi
	@echo "✅ README.html 생성됨"

.PHONY: help setup install uninstall purge status doc
