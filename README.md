# NAVER Cloud SSL VPN 재연결 (`naver-vpn`)

NAVER Cloud SSL VPN(정부 클라우드, `gov-ncloud`) 을 **터미널 한 줄로 재연결**하는 도구.
GUI 앱을 띄우지 않고, 키체인에 저장된 비밀번호로 로그인 → 문자 OTP 입력 → OpenVPN 연결까지 자동으로 처리한다.

```
naver-vpn            # 문자 발송 후 OTP를 물어봄
naver-vpn 123456     # 문자가 이미 와 있으면 OTP를 인자로
```

---

## 왜 필요한가

NAVER Cloud SSL VPN 데스크톱 앱은 연결이 끊길 때마다(`INACTIVE_TIMEOUT` 등) 앱을 열어
아이디·비밀번호·OTP를 매번 입력해야 한다. 이 도구는 그 과정을 CLI로 옮겨:

- 비밀번호는 **macOS 키체인**에서 자동으로 꺼내 입력
- macOS 관리자(맥) 비밀번호 입력 창도 **NOPASSWD sudo 래퍼**로 제거

남는 수동 입력은 **문자로 받은 OTP 한 번뿐**이다. (OTP는 SMS 기반이라 완전 무인 자동화는 불가능.)

또한 연결 후에는 **keepalive** 가 자동으로 돌면서 터널이 유휴로 끊기는 것을 막는다.

---

## 동작 방식 (상세)

NAVER Cloud SSL VPN 앱은 사실 **Electron + OpenVPN** 조합이고, 인증은 2단계다.
이 도구는 앱이 내부적으로 하는 HTTPS 호출을 그대로 재현한다.

```
┌─────────────┐  ① POST /api/v3/authstate (ID + 비번)         ┌──────────────────┐
│  naver-vpn  │ ───────────────────────────────────────────▶ │  포털 :8443      │
│  (이 도구)  │ ◀─────────────────────────────────────────── │  (gov-ncloud)    │
└─────────────┘   success / state / profile_body(.ovpn)        └──────────────────┘
       │                    └─ 서버가 ② 휴대폰으로 OTP 문자 발송 ──▶ 📱
       │
       │  ③ 사용자가 문자 OTP 입력
       │
       │  ④ auth-file = "아이디\nOTP" 작성 (임시, chmod 600)
       ▼
┌─────────────┐  ⑤ sudo naver-vpn-up  (root 래퍼)             ┌──────────────────┐
│  openvpn    │ ───────────────────────────────────────────▶ │  VPN 게이트웨이  │
│  --daemon   │     username=아이디 / password=OTP 로 인증     │  :12033 (TCP)    │
└─────────────┘ ◀─────────────────────────────────────────── └──────────────────┘
       └─ utun 인터페이스에 10.0.0.x 할당 → 사내망 접근
```

1. **`POST /api/v3/authstate`** — 헤더 `Api-Version: 1`, 본문에 `user_id`, `passwd`(평문, HTTPS),
   `type:"connect"`, `ovpn_file_name`, `client_version`, `os_name/os_version`, `mac[]` 을 보낸다.
   서버가 비밀번호를 검증하면 **OTP 문자를 발송**하고, `state` 토큰과 base64 인코딩된
   `.ovpn` 프로필(`profile_body`)을 돌려준다.
2. 받은 `.ovpn` 을 앱 데이터 디렉토리(`~/Library/Application Support/ncurion-sa-client/vpn/profiles/`)에 저장한다.
3. 문자로 받은 **OTP** 를 입력받는다.
4. `아이디\nOTP` 두 줄짜리 **임시 인증파일**(`/tmp/naver-vpn-auth.XXXX`, 권한 600)을 만든다.
5. **root 래퍼**(`/usr/local/sbin/naver-vpn-up`)를 `sudo` 로 호출 → 기존 openvpn 종료 후
   `openvpn --config <프로필> --auth-user-pass <인증파일> --daemon` 실행.
   게이트웨이는 비밀번호 자리의 **OTP** 로 최종 인증한다.
6. `utun` 에 `10.0.0.x` 가 잡히면 성공. (`TARGET` IP ping 으로 확인)

> **핵심 포인트:** 처음에는 `/api/v2/*` 로 시도했으나 그 엔드포인트는 서버에서 폐기되어
> 항상 `{"success":false}` 를 반환한다. 실제 동작 경로는 **`/api/v3`** 이다.
> (mitmproxy 로 앱의 실제 트래픽을 캡처해서 확인했다.)

---

## 유휴 끊김 방지 (keepalive)

서버는 **실제 데이터 트래픽** 이 없으면 일정 시간 후 세션을 끊는다(`INACTIVE_TIMEOUT`).
프로필에 OpenVPN 자체 `keepalive 10 30` 이 있지만 이건 제어채널 핑이라 서버의 유휴 판정을 막지 못한다.

그래서 연결 성공 후 **keepalive 데몬**이 백그라운드로 떠서, 일정 주기마다 터널 너머
게이트웨이(`KEEPALIVE_HOST`, 기본 `10.0.0.1`)로 핑을 보내 **실제 터널 트래픽**을 만든다.

- ⚠️ 핑 대상은 반드시 **터널 너머의 IP**(게이트웨이 등)여야 한다. 로컬 터널 IP(`10.0.0.4`)로
  핑하면 패킷이 터널을 타지 않아 유휴 타이머가 리셋되지 않는다.
- openvpn 프로세스가 사라지거나 핑이 연속 실패하면 keepalive 는 **스스로 종료**한다.
- 재연결(`vpn`) 시 기존 keepalive 는 정리되고 새로 시작된다.

```bash
naver-vpn-keepalive status    # 상태
naver-vpn-keepalive stop      # 수동 중지
naver-vpn-keepalive start     # 수동 시작
```

설정(`~/.config/naver-vpn/config`):

| 변수 | 기본값 | 설명 |
|------|--------|------|
| `KEEPALIVE` | `1` | 연결 후 자동 시작 (0 이면 비활성) |
| `KEEPALIVE_INTERVAL` | `60` | 핑 주기(초) |
| `KEEPALIVE_HOST` | `10.0.0.1` | 핑 대상(터널 너머 게이트웨이) |
| `KEEPALIVE_FAILS` | `3` | 연속 실패 N회면 종료 |

로그: `~/.config/naver-vpn/keepalive.log`

---

## 요구 사항

- macOS
- **NAVER Cloud SSL VPN.app** 설치 (`/Applications/` — 내부의 `openvpn` 바이너리를 사용)
- `jq`, `curl` (`brew install jq`)
- 관리자(sudo) 권한 — 설치 시 1회

### 프로필 이름(`OVPN_NAME`)에 대해 — 중요

`.ovpn` 프로필 **파일** 자체는 의존성이 아니다. 클라이언트는 매번 서버 응답(`profile_body`)에서
프로필을 새로 받아 저장하므로, 저장소에 프로필을 넣을 필요가 없다(넣지도 않는다).

다만 **`OVPN_NAME`(예: `vpn2033.ovpn`)은 계정/테넌트별 식별자**다. v3 `authstate` 요청의
`ovpn_file_name` 으로 전송되어 서버가 어떤 VPN 프로필을 줄지 결정한다. 따라서 **다른 계정/환경에서는
이 값이 다르며**, 저장소의 기본값을 그대로 쓰면 접속되지 않을 수 있다.

이 이름은 **NAVER Cloud SSL VPN 앱이 로그인 시 받아 저장**한다. 그래서:

- `make setup` 은 `~/Library/Application Support/ncurion-sa-client/vpn/profiles/*.ovpn` 에서
  **OVPN_NAME 을 자동 감지**해 기본값으로 제시한다.
- 새 기기라면 **NAVER 앱으로 한 번 로그인**해 프로필을 받은 뒤 `make setup` 을 실행하면 된다.
  (앱은 어차피 `openvpn` 바이너리 때문에 필요하다.)
- 이름을 이미 안다면 `make setup` 에서 직접 입력해도 된다.

---

## 설치

```bash
cd ~/work/naver-vpn

make setup      # ① 아이디/도메인/프로필 + 비밀번호를 키체인에 저장
make install    # ② 클라이언트 + root 래퍼 + NOPASSWD 설치 (sudo 1회)
                #    설치 중 단축 명령(별칭) 이름을 물어봄 (기본 vpn)
make status     # (선택) 설치/연결 상태 확인
```

**단축 명령(별칭) 이름**은 `make install` 중에 정한다(기본 `vpn`). `naver-vpn` 은 항상 설치되고,
별칭은 그 심볼릭 링크다. 선택한 이름은 `config` 에 기록되어 `uninstall` 도 같은 이름을 정리한다.

```bash
make install ALIAS=nvpn   # 비대화형으로 별칭 지정
make install ALIAS=-      # 별칭 없이 (naver-vpn 만)
```

설치되는 것:

| 파일 | 위치 | 소유/권한 | 역할 |
|------|------|-----------|------|
| `naver-vpn` | `/usr/local/bin/naver-vpn` | root:wheel 0755 | CLI 클라이언트 |
| `naver-vpn-keepalive` | `/usr/local/bin/naver-vpn-keepalive` | root:wheel 0755 | 유휴 끊김 방지 데몬 |
| `<별칭>` | `/usr/local/bin/<별칭>` | → `naver-vpn` 심볼릭 | 설치 시 정한 단축 명령(기본 `vpn`) |
| `naver-vpn-up` | `/usr/local/sbin/naver-vpn-up` | root:wheel 0755 | openvpn 실행 root 래퍼 |
| `naver-vpn` | `/etc/sudoers.d/naver-vpn` | root:wheel 0440 | 래퍼 NOPASSWD 허용 |
| `config` | `~/.config/naver-vpn/config` | 0600 | 사용자 설정 |
| (비밀번호) | macOS 키체인 `naver-vpn` | — | VPN 비밀번호 |

---

## 사용법

```bash
vpn                  # 또는 naver-vpn
```

실행하면:

1. `▶ 로그인 요청 중...` → 잠시 후 **휴대폰으로 OTP 문자** 도착
2. `▶ 문자로 받은 OTP 입력:` 에 숫자 입력
3. `✅ VPN 연결 완료 — 10.0.0.4 접근 가능`
4. keepalive 자동 시작 → 이후 유휴로 끊기지 않음 (`naver-vpn-keepalive status` 로 확인)

문자가 이미 도착해 있으면 한 번에:

```bash
vpn 204767
```

---

## 화면 예시

실제 출력은 색이 입혀져 나온다(터미널 기준; 파이프하거나 `NO_COLOR=1` 이면 색 제거).

`make setup` — 대화형 설정:

```text
╭─ 📡 NAVER Cloud SSL VPN 설정 ──────────────
│  설정 파일과 키체인 비밀번호를 만듭니다.
╰──────────────────────────────────────────────

🔧 기본 설정
   ℹ️  NAVER 앱 프로필에서 OVPN_NAME 자동 감지: vpn2033.ovpn
   › VPN 아이디 [migmig01]:
   › 포털 도메인 [https://sslvpn-kr-vpc-01.gov-ncloud.com:8443]:
   › 프로필 파일명 [vpn2033.ovpn]:
   › 연결확인 IP [10.0.0.4]:

🔁 keepalive (유휴 끊김 방지)
   › 사용하시겠어요? (Y/n) [Y]:
   › 핑 대상(게이트웨이) [10.0.0.1]:
   › 주기(초) [60]:

✅ 설정 저장: ~/.config/naver-vpn/config

🔑 비밀번호
   키체인에 저장합니다 (입력은 화면에 안 보이고, 두 번 입력)
✅ 비밀번호 저장 완료 (키체인 naver-vpn / migmig01)

├──────────────────────────────────────────────
│  ▶ 다음 단계  make install →  naver-vpn 으로 연결
╰──────────────────────────────────────────────
```

`make` (인자 없이) — 명령 안내:

```text
╭─ 📡 NAVER Cloud SSL VPN 재연결 ──────────────
│  터미널 재연결 · 키체인 비번 · 문자 OTP · keepalive
│
│  📋 명령
│    🔧 make setup      대화형 설정 (아이디 + 키체인 비번)
│    📦 make install    설치 (클라이언트 + 래퍼 + NOPASSWD)  [sudo]
│    🧹 make uninstall  제거 (설정/키체인 유지)  [sudo]
│    💥 make purge      완전 삭제 (설정/키체인 포함)  [sudo]
│    📊 make status     설치/연결 상태 확인
│    📄 make doc        README.html 생성
│
├──────────────────────────────────────────────
│  ▶ 처음이라면  make setup → make install → naver-vpn
╰──────────────────────────────────────────────
```

`make status` — 설치/연결 상태:

```text
╭─ 📡 NAVER Cloud SSL VPN — 상태 ──────────────
│
│  📦 설치
│    ✅  client     /usr/local/bin/naver-vpn
│    ✅  keepalive  /usr/local/bin/naver-vpn-keepalive
│    ✅  alias      vpn → naver-vpn
│    ✅  wrapper    /usr/local/sbin/naver-vpn-up
│    ✅  sudoers    NOPASSWD /etc/sudoers.d/naver-vpn
│
│  ⚙️ 설정
│    ✅  config     user=migmig01  ovpn=vpn2033.ovpn
│    ✅  keychain   비밀번호 저장됨
│
│  🌐 연결
│    ✅  tunnel     10.0.0.4 활성
│    ✅  keepalive  실행중 pid 12140 · 60s → 10.0.0.1
│
├──────────────────────────────────────────────
│  🟢 VPN 연결됨
╰──────────────────────────────────────────────
```

`make install` — 설치(별칭 선택 + 권한 안내):

```text
╭─ 📦 NAVER Cloud SSL VPN 설치 ──────────────
│  🏷 단축 명령(별칭)
│     › 별칭 [vpn]: nvpn
│     별칭 → nvpn
│
│  🔐 권한
│     잠시 후 맥 관리자(sudo) 비밀번호를 물어볼 수 있습니다.
│     VPN 비밀번호가 아니라, 이 컴퓨터(macOS) 로그인 암호입니다.
│
│  📂 설치
│     ✅ 클라이언트  /usr/local/bin/naver-vpn (+ keepalive)
│     ✅ 별칭        /usr/local/bin/nvpn → naver-vpn
│     ✅ root 래퍼   /usr/local/sbin/naver-vpn-up
│     ✅ sudoers     NOPASSWD /etc/sudoers.d/naver-vpn
│
├──────────────────────────────────────────────
│  🎉 설치 완료  실행: nvpn (또는 naver-vpn)
╰──────────────────────────────────────────────
```

`naver-vpn` (또는 별칭) — 연결:

```text
╭─ 📡 NAVER Cloud SSL VPN 연결 ──────────────
│  🔐 로그인 요청 중…  휴대폰으로 OTP 문자 발송
│  ✅ 비번 확인 · 프로필 수신  vpn2033.ovpn
│  📱 문자로 받은 OTP 입력: 204767
│  🔌 VPN 연결 중…
│  ⏳ 연결 확인 중…
│  ✅ 연결 완료 — 10.0.0.4 접근 가능
│  🔁 keepalive 시작  60s → 10.0.0.1
╰──────────────────────────────────────────────
```

---

## Make 명령 요약

| 명령 | 설명 |
|------|------|
| `make setup` | 대화형 설정 — 아이디/도메인/프로필 + 키체인 비밀번호 저장 (sudo 불필요) |
| `make install` | 클라이언트·래퍼·sudoers 설치 (필요 시 sudo 호출) |
| `make uninstall` | 설치물 제거 (설정·키체인은 **유지**) |
| `make purge` | `uninstall` + 설정파일·키체인 항목까지 삭제 |
| `make status` | 설치/설정/연결 상태 출력 |
| `make doc` | `README.md` → `README.html` 변환 |
| `make help` | 명령 목록 |

비밀번호만 다시 바꾸려면:

```bash
make setup
# 또는 직접:
security add-generic-password -U -s naver-vpn -a <아이디> -w
```

---

## 제거

```bash
make uninstall   # 바이너리/래퍼/sudoers 제거 (설정·키체인 유지)
make purge       # 위 + ~/.config/naver-vpn 및 키체인 비밀번호까지 삭제
```

제거 후에도 NAVER Cloud SSL VPN 앱 자체는 그대로 남으며, 앱으로 평소처럼 연결할 수 있다.

---

## 보안 메모

- **비밀번호는 키체인에만** 저장된다. 설정파일·스크립트에 평문으로 남지 않는다.
- **OTP·인증파일**은 임시파일(`/tmp/naver-vpn-auth.*`, 권한 600)로 만들어지고 종료 시 삭제된다.
  OpenVPN 은 `--auth-nocache` 로 메모리에 캐시하지 않는다.
- **NOPASSWD 의 범위를 최소화**했다. `openvpn` 바이너리에 직접 NOPASSWD 를 주면
  openvpn 설정의 `--up` 스크립트로 임의 명령을 root 로 실행할 수 있어 사실상 전체 root 권한이 된다.
  그래서 대신 **하는 일이 고정된 root 래퍼**(`naver-vpn-up`)에만 권한을 준다. 래퍼는:
  - openvpn 설정 디렉토리를 코드에 **고정** (임의 설정 실행 불가)
  - 프로필 파일명(슬래시 없는 `*.ovpn`)·인증파일 경로(`/tmp/naver-vpn-auth.*`)를 **검증**
  - root 소유·사용자 쓰기 불가
- 평문 비밀번호는 앱과 동일하게 **HTTPS** 로만 전송된다.

---

## 문제 해결

| 증상 | 원인 / 조치 |
|------|-------------|
| `로그인 실패` | 키체인 비밀번호가 틀림 → `make setup` 으로 재등록. 아이디(`VPN_USER`) 확인. |
| OTP 입력 후 실패 | OTP 만료/오타. 다시 `vpn` 실행(새 문자 발송). 한 번에 하나의 OTP만 유효. |
| 맥 비밀번호 창이 뜸 | NOPASSWD 미설치 → `make install`. (`make status` 로 sudoers 확인) |
| `command not found: vpn` | `/usr/local/bin` 이 PATH 에 없거나 `~/.zshrc` 의 옛 `alias vpn` 이 가림. |
| `jq 가 필요합니다` | `brew install jq` |
| 연결은 됐는데 `❌` 표시 | `TARGET` IP 가 환경과 다름 → `make setup` 에서 수정. `make status` 로 utun 확인. |
| 그래도 유휴로 끊김 | keepalive 동작 확인(`naver-vpn-keepalive status`). 주기를 줄이거나(`KEEPALIVE_INTERVAL`) `KEEPALIVE_HOST` 를 터널 너머 응답 IP로. 로그: `~/.config/naver-vpn/keepalive.log` |

로그: `~/Library/Application Support/ncurion-sa-client/vpn/vpn.log`

---

## 파일 구성

```
work/naver-vpn/
├── Makefile                 설치/제거/상태/문서 타깃
├── README.md / README.html  문서
├── config.example           설정 예시
├── bin/naver-vpn            CLI 클라이언트
├── bin/naver-vpn-keepalive  유휴 끊김 방지 데몬
├── sbin/naver-vpn-up.in     root 래퍼 템플릿 (@HOME@ 치환)
├── etc/naver-vpn.sudoers.in NOPASSWD 규칙 템플릿 (@USER@ 치환)
└── tools/
    ├── setup.sh             대화형 설정
    ├── install.sh           설치 (별칭 선택 포함)
    ├── uninstall.sh         제거
    ├── status.sh            상태 출력
    └── md2html.py           Markdown→HTML 변환기
```
