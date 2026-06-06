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
install:
	@if [ "$$(id -u)" = "0" ]; then echo "❌ 'sudo make install' 말고 'make install' 로 실행하세요 (필요할 때만 sudo 가 호출됩니다)."; exit 1; fi
	@echo "==> 클라이언트 설치: $(BINDIR)/naver-vpn  (+ keepalive, vpn 심볼릭)"
	sudo install -d -o root -g wheel -m 0755 $(BINDIR) $(SBINDIR)
	sudo install -o root -g wheel -m 0755 bin/naver-vpn $(BINDIR)/naver-vpn
	sudo install -o root -g wheel -m 0755 bin/naver-vpn-keepalive $(BINDIR)/naver-vpn-keepalive
	sudo ln -sf naver-vpn $(BINDIR)/vpn
	@echo "==> root 래퍼 설치: $(SBINDIR)/naver-vpn-up  (HOME=$(HOMEDIR))"
	sed 's#@HOME@#$(HOMEDIR)#g' sbin/naver-vpn-up.in > /tmp/naver-vpn-up.gen
	sudo install -o root -g wheel -m 0755 /tmp/naver-vpn-up.gen $(SBINDIR)/naver-vpn-up
	@rm -f /tmp/naver-vpn-up.gen
	@echo "==> sudoers 설치: $(SUDOERSD)/naver-vpn  (user=$(REALUSER))"
	sed 's#@USER@#$(REALUSER)#g' etc/naver-vpn.sudoers.in > /tmp/naver-vpn.sudoers.gen
	sudo visudo -cf /tmp/naver-vpn.sudoers.gen
	sudo install -o root -g wheel -m 0440 /tmp/naver-vpn.sudoers.gen $(SUDOERSD)/naver-vpn
	@rm -f /tmp/naver-vpn.sudoers.gen
	@echo ""
	@echo "✅ 설치 완료."
	@[ -f $(CONFDIR)/config ] || echo "   ⚠️  아직 설정이 없습니다 — 'make setup' 을 실행하세요."
	@if grep -qs 'alias[[:space:]]\+vpn' $(HOMEDIR)/.zshrc; then \
	  echo "   ⚠️  ~/.zshrc 의 'alias vpn' 가 $(BINDIR)/vpn 보다 우선합니다. 그 줄을 지우면 새 vpn 명령이 적용됩니다."; fi
	@case ":$$PATH:" in *":$(BINDIR):"*) ;; *) echo "   ⚠️  $(BINDIR) 가 PATH 에 없습니다. naver-vpn 전체경로로 실행하거나 PATH 에 추가하세요.";; esac

# ---- 제거 (설정/키체인 유지) ----
uninstall:
	@echo "==> 설치물 제거"
	@if [ -L $(BINDIR)/vpn ] && [ "$$(readlink $(BINDIR)/vpn)" = "naver-vpn" ]; then sudo rm -f $(BINDIR)/vpn; fi
	-@command -v naver-vpn-keepalive >/dev/null 2>&1 && naver-vpn-keepalive stop >/dev/null 2>&1 || true
	sudo rm -f $(BINDIR)/naver-vpn $(BINDIR)/naver-vpn-keepalive $(SBINDIR)/naver-vpn-up $(SUDOERSD)/naver-vpn
	@echo "✅ 제거 완료 (설정 $(CONFDIR), 키체인은 유지). 완전삭제: make purge"

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
