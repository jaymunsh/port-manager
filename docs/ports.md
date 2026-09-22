# 포트 관리 — 수집, 테이블, 안전 종료, 대역폭

## 개념: 포트 vs 소켓 — 왜 같은 포트가 여러 행으로 나오나

테이블의 행 단위는 "포트"가 아니라 **소켓(파일 디스크립터) 하나**다. 포트 하나에 여러 소켓이 걸릴 수 있다:

```
5432  *            TCP   remote=·            ← LISTEN 소켓 (대기)
5432  127.0.0.1    TCP   remote=127.0.0.1:57909   ← 수락된 연결 #1
5432  127.0.0.1    TCP   remote=127.0.0.1:53319   ← 수락된 연결 #2
...                                              ← 클라이언트 수만큼 반복
```

- **LISTEN 소켓**: 서버 프로세스가 `bind()` + `listen()`으로 여는 대기 소켓. remote가 없다. "포트를 점유했다"는 보통 이걸 말한다.
- **연결 소켓**: 클라이언트가 접속할 때마다 `accept()`로 새로 생기는 별개의 소켓. 로컬 주소는 리스너와 같지만(같은 포트 5432), remote 쪽의 **임시 포트(ephemeral port)**가 연결마다 다르다 — `(로컬IP:로컬포트, 원격IP:원격포트)` 4-튜플로 구분되므로 같은 포트에 연결이 무한히 붙을 수 있다.
- 같은 포트라도 바인드 주소가 다르면(`*`와 `127.0.0.1`을 각각 `bind`) 리스너 소켓 자체가 2개일 수 있다.

그래서 `⇄ 연결 표시` 토글을 켜면 포트당 행이 N개로 늘어나고, 끄면 리스너만 남아 포트당 대략 1행이 된다. 알림/diff도 리스너 기준으로만 돌아서 연결 churn이 로그를 오염시키지 않는다.

## 소켓 수집: lsof -F

`LsofProvider`는 lsof의 **머신 리더블 `-F` 출력**을 쓴다 (`-nP`로 호스트/포트 이름 해석 끔):

```
lsof -nP -FpcnPLfT -iTCP [-sTCP:LISTEN] [-iUDP]
```

- `-sTCP:LISTEN` — 기본: 리스너만
- 생략 — `showConnections` 토글: 모든 TCP 소켓 (ESTABLISHED 포함)
- `-iUDP` — UDP 토글 시 바인드된 UDP 소켓도 포함

`LsofParser`는 필드 스트림을 상태 머신으로 파싱한다:

```
p<pid>   — 프로세스 블록 시작 (이전 fd 레코드 flush)
c<cmd>   — 프로세스 명령어
L<user>  — 소유자
f<fd>    — 파일 디스크립터 레코드 시작 (소켓 하나당 하나)
P<proto> — TCP / UDP
n<name>  — 엔드포인트: `*:3000`, `127.0.0.1:7265`, `a:1->b:2`
TST=<st> — TCP 상태 (LISTEN, ESTABLISHED, ...)
```

`splitEndpoint`가 `host:port[->peer:port]`를 분리 — `[fe80::x]:port` IPv6 브래킷과 `*:*` 무바인드(포트 없음 → 버림) 처리. `remote`가 있으면 아웃바운드 연결 행이 된다.

`PortEntry.isListener`: `remote == nil && (proto == .udp || state == "LISTEN")` — UDP는 LISTEN 상태가 없어서 바인드 소켓을 리스너 취급.

## 뷰 모드: 소켓 테이블 / 프로세스 그룹

툴바의 `square.stack.3d.up` 토글로 두 모드를 바꾼다 (`ports.groupByProcess` 영속화):

- **소켓 모드** (기본): 소켓당 한 행의 `Table` — 정렬/필터/CSV 대상
- **프로세스 모드**: `ProcessGroupView` — pid로 `ProcessGroup`을 만들어 DisclosureGroup 리스트로 표시. 헤더에 포트 목록·연결 수·CPU/Mem·프로세스 대역폭 합계, 펼치면 소켓 행들. "누가 뭘 쓰나"를 볼 때 유용

## Docker 매핑

호스트의 published 포트는 `com.docker.backend`(프록시 shim)가 점유해서 실제 컨테이너가 보이지 않는다. `DockerProvider`가 `docker ps --format '{{.ID}}|{{.Image}}|{{.Names}}|{{.Ports}}'`를 15초 주기로 폴링해 `hostPort → DockerContainer` 맵을 만든다 (`PortStore.dockerByPort`). `Ports` 필드(`0.0.0.0:5432->5432/tcp, :::5432->5432/tcp`)에서 `->` 왼쪽의 마지막 `:` 뒤 숫자만 hostPort로 파싱 — `mapping.range(of: "->")`를 써야 한다 (`firstIndex(of: ">")`로 자르면 `5432-`가 남아 실패 — 실제로 테스트가 잡아낸 버그).

표시 위치: Process 컬럼의 이미지 배지(`postgres:16`), 그룹 헤더의 `🐳` 배지, 인스펙터의 "Docker Container" 섹션(name/image/id). docker 없는 환경에서는 조용히 빈 맵.

## 프로세스 체인

`ps -axo pid=,ppid=,%cpu=,%mem=,comm=` 스냅샷이 ppid까지 수집하므로, `ProcessService.ancestorChain`이 테이블을 타고 launchd까지 올라간다. 인스펙터 "Launched by"에 `launchd → Terminal → npm → node` 형태로 표시 — "이 포트 점유자가 어디서 떴나" 추적용.

## 테이블

`PortListView` — SwiftUI `Table` + 커스텀 `RowComparator`(모든 컬럼이 같은 concrete `SortComparator` 타입이어야 하는 SwiftUI 제약):

- 컬럼: Port / Process(실제 앱 아이콘) / PID / Bind / Proto / CPU / Mem / Net / User / Remote(연결 모드 시) / Preset 배지
- 필터: 검색(포트/프로세스/주소), localhost-only, UDP 포함, 연결 포함
- 정렬 상태와 토글은 UserDefaults/`@AppStorage`로 영속화
- 우클릭: 종료, 프리셋 저장, 브라우저 열기, Port/PID/Remote/lsof 복사
- CSV보내기 (NSSavePanel)
- 인스펙터: 기본 접힘, 행 선택 시 `.inspector`로 오픈 — 실행 경로, 시작 시각, CPU/Mem, 열린 파일 수, 자식 프로세스

프로세스 아이콘은 `IconCache` — `proc_pidpath` → `NSWorkspace.icon(forFile:)` 캐시.

## 안전 종료 (`KillSheet`)

상태 머신: `confirm → working → (done | needsForce | blocked | failed)`

1. confirm — 프로세스 정보 표시 (경로, 시작 시각, **자식 프로세스 경고**), 보호 대상(pid 0/1, kernel_task/launchd/WindowServer/loginwindow)은 버튼 비활성
2. SIGTERM 전송 → 500ms 간격으로 최대 5초 `kill(pid,0)` 생존 확인
3. 안 죽으면 → `needsForce` — SIGKILL은 명시적 사용자 선택으로만
4. `EPERM` → `blocked` — `sudo kill <pid>` 복사 버튼 제공 (권한 헬퍼는 코드사이닝 필요로 미구현)
5. 성공 → Activity 로그 + 즉시 refresh

## 대역폭: nettop

`NettopProvider`는 `nettop -x -l 1 -J bytes_in,bytes_out`을 파싱한다. 출력은 2단 구조:

```
node.836                                    1000    500      ← 프로세스 합계 (name.pid)
   tcp4 10.1.0.4:63294<->17.57.145.25:5223   700    300      ← 소켓별 카운터
```

- 프로세스 행 → `perPid[pid]`
- 연결 행 → `perConn[ConnKey(pid, localPort, remotePort)]` — lsof의 `remote`에서 포트를 뽑아 같은 키로 매칭. 와일드카드(`*:*`)는 remotePort 0

Store에서 연속 스냅샷의 **delta ÷ 경과시간**으로 초당 rate를 만든다.

표시 규칙 (Net 컬럼):
- **리스너 행** → 프로세스 합계 (리스너 소켓 자체는 accept만 하고 트래픽은 자식 연결이 오감)
- **연결 행** → 그 소켓 자신의 rate — 같은 pid의 소켓들이 전부 같은 값을 보여주던 문제 해결

주의: `nettop` 호출은 무조건 ~5초 — PortStore의 별도 `netTask` 루프에서 돌아 포트 목록 갱신을 막지 않는다.
