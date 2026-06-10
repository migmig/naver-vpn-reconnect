# NAVER Cloud SSL VPN 재연결 — 설치/제거 Makefile
#
#   make setup      대화형 설정 (아이디/도메인 + 키체인 비밀번호)
#   make install    클라이언트 + root 래퍼 + NOPASSWD sudoers 설치 (sudo 필요)
#   make uninstall  설치물 제거 (설정/키체인은 유지)
#   make purge      uninstall + 설정파일/키체인까지 삭제
#   make status     설치/설정/연결 상태 확인
#   make doc        README.html 열기
#
PREFIX   ?= /usr/local
BINDIR    := $(PREFIX)/bin
SBINDIR   := $(PREFIX)/sbin
SUDOERSD  := /etc/sudoers.d
REALUSER  := $(if $(SUDO_USER),$(SUDO_USER),$(shell id -un))
HOMEDIR   := $(shell eval echo ~$(REALUSER))
CONFDIR   := $(HOMEDIR)/.config/naver-vpn

# ---- 색 (NO_COLOR 환경변수면 비활성) ----
ifeq ($(strip $(NO_COLOR)),)
  C_RESET  := $(shell printf '\033[0m')
  C_BOLD   := $(shell printf '\033[1m')
  C_DIM    := $(shell printf '\033[2m')
  C_RED    := $(shell printf '\033[31m')
  C_GREEN  := $(shell printf '\033[32m')
  C_YELLOW := $(shell printf '\033[33m')
  C_BLUE   := $(shell printf '\033[34m')
  C_CYAN   := $(shell printf '\033[36m')
endif
export C_RESET C_BOLD C_DIM C_RED C_GREEN C_YELLOW C_BLUE C_CYAN

.DEFAULT_GOAL := help

help:
	@printf '\n$(C_DIM)╭─$(C_RESET) $(C_BOLD)$(C_CYAN)📡 NAVER Cloud SSL VPN 재연결$(C_RESET) $(C_DIM)──────────────$(C_RESET)\n'
	@printf '$(C_DIM)│$(C_RESET)  $(C_DIM)터미널 재연결 · 키체인 비번 · 문자 OTP · keepalive$(C_RESET)\n'
	@printf '$(C_DIM)│$(C_RESET)\n'
	@printf '$(C_DIM)│$(C_RESET)  $(C_BOLD)$(C_CYAN)📋 명령$(C_RESET)\n'
	@printf '$(C_DIM)│$(C_RESET)    🔧 $(C_GREEN)make setup$(C_RESET)      대화형 설정 (아이디 + 키체인 비번)\n'
	@printf '$(C_DIM)│$(C_RESET)    📦 $(C_GREEN)make install$(C_RESET)    설치 (클라이언트 + 래퍼 + NOPASSWD)  $(C_YELLOW)[sudo]$(C_RESET)\n'
	@printf '$(C_DIM)│$(C_RESET)    🧹 $(C_GREEN)make uninstall$(C_RESET)  제거 (설정/키체인 유지)  $(C_YELLOW)[sudo]$(C_RESET)\n'
	@printf '$(C_DIM)│$(C_RESET)    💥 $(C_GREEN)make purge$(C_RESET)      완전 삭제 (설정/키체인 포함)  $(C_YELLOW)[sudo]$(C_RESET)\n'
	@printf '$(C_DIM)│$(C_RESET)    📊 $(C_GREEN)make status$(C_RESET)     설치/연결 상태 확인\n'
	@printf '$(C_DIM)│$(C_RESET)    📄 $(C_GREEN)make doc$(C_RESET)        README.html 열기\n'
	@printf '$(C_DIM)│$(C_RESET)\n'
	@printf '$(C_DIM)├──────────────────────────────────────────────$(C_RESET)\n'
	@printf '$(C_DIM)│$(C_RESET)  $(C_BOLD)▶ 처음이라면$(C_RESET)  $(C_CYAN)make setup$(C_RESET) $(C_DIM)→$(C_RESET) $(C_CYAN)make install$(C_RESET) $(C_DIM)→$(C_RESET) $(C_CYAN)naver-vpn$(C_RESET)\n'
	@printf '$(C_DIM)╰──────────────────────────────────────────────$(C_RESET)\n\n'

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
	@printf '$(C_BLUE)==>$(C_RESET) 설정/키체인 삭제\n'
	@if [ -f $(CONFDIR)/config ]; then \
	  . $(CONFDIR)/config 2>/dev/null; \
	  security delete-generic-password -s "$${KC_SERVICE:-naver-vpn}" -a "$$VPN_USER" >/dev/null 2>&1 \
	    && printf '    키체인 항목 삭제됨\n' || true; \
	fi
	rm -rf $(CONFDIR)
	@printf '$(C_GREEN)✅ 완전 삭제 완료$(C_RESET)\n'

# ---- 상태 ----
status:
	@bash tools/status.sh $(BINDIR) $(SBINDIR) $(SUDOERSD)

# ---- 문서 ----
# README.html 은 직접 작성/유지하는 파일이다(자동 생성하지 않음). 그냥 연다.
doc:
	@open README.html 2>/dev/null && printf '$(C_GREEN)✅ README.html 열기$(C_RESET)\n' \
	  || printf '$(C_DIM)README.html: %s/README.html$(C_RESET)\n' "$$PWD"

.PHONY: help setup install uninstall purge status doc
