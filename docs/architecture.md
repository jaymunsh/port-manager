# 아키텍처

## 레이어 구조

단방향 데이터 흐름 — Service가 수집하고, Store가 상태로 만들고, View가 표시한다.

```
┌─────────────────────────────────────────────────────────┐
│ Views (SwiftUI)                                         │
│   Ports / Network / Devices / Presets / Activity /      │
│   Settings / MenuBar(Label+Popover)                     │
├─────────────────────────────────────────────────────────┤
│ Stores (@MainActor ObservableObject)                    │
│   PortStore  DeviceStore  NetworkStore  PresetStore     │
│   ActivityStore  MonitorEngine                          │
├─────────────────────────────────────────────────────────┤
│ Services (Sendable struct — 상태 없는 수집기)             │
│   LsofProvider  NettopProvider  ProcessService          │
│   NetworkProvider  USBProvider  DiskService             │
│   NotifyService  Shell  ByteFormat  LsofParser          │
└─────────────────────────────────────────────────────────┘
```

규칙:
- Service는 모두 `Sendable` struct — 외부 프로세스 실행/파싱만 하고 상태를 안 들고 있음. `Background.run`에서 호출된다. DiskService는 메인 run loop에 연결되는 클래스 예외다.
- Store는 `@MainActor` — `@Published` 상태와 폴링 루프를 소유. 무거운 수집은 detached로 보내고 결과만 메인에 반영.
- View는 필요한 Store를 **개별** `@EnvironmentObject`로 주입받는다 (아래 함정 참고).

## 엔트리포인트와 Scene

`main.swift`가 `--selftest` 인자를 보고 테스트 러너/앱을 갈라 탄다.

```
PortManagerApp
├── WindowGroup("main")  → MainWindow (NavigationSplitView)
├── MenuBarExtra         → MenuBarPopover (content) + MenuBarLabel (status item)
└── Settings             → SettingsView (⌘, 플로팅 창 — 사이드바 탭과 같은 뷰)
```

`AppState`는 Store들을 소유하는 컨테이너일 뿐이고, `injectStores()`가 각 Store를 개별 environment object로 등록한다. `state.section`(`@Published`)은 팝오버→메인창 딥링크용 네비게이션 상태.

## Store별 역할

| Store | 역할 |
|-------|------|
| `PortStore` | `lsof` 스냅샷 폴링(기본 3초), CPU/Mem 통계(`ps` 1회 호출), nettop 대역폭, `docker ps` 매핑(15초), `groups` 프로세스 롤업. diff는 **리스너만** 계산해 핸들러에 통지 |
| `DeviceStore` | DiskArbitration 이벤트 구독 + 볼륨 목록, USB/Thunderbolt 트리 (`system_profiler -json`), unmount/eject 연결 |
| `NetworkStore` | 인터페이스별 바이트 카운터 폴링(2초) → delta → 초당 rate |
| `PresetStore` | 프리셋 CRUD + `presets.json` 영속화 + 상태 판정 |
| `AlertStore` | 대역폭 알림 규칙 CRUD + `alerts.json` 영속화 + 현재 rate 계산 |
| `ActivityStore` | 이벤트 로그 링버퍼(최대 500개) + `HistoryService`를 통한 JSONL 일별 파일 영속화 |
| `MonitorEngine` | Store diff/rate → Activity 로그 + 시스템 알림으로 변환하는 이벤트 라우터 |

## 폴링 모델

```
PortStore.pollTask      ──(interval, 기본 3s)──▶ lsof + ps
PortStore.netTask       ──(필요할 때, ≥5s)──▶ nettop     ← 호출당 ~5초 걸려서 분리됨
PortStore.dockerTask    ──(15s)──▶ docker ps   ← 없는 환경도 고려해 분리
NetworkStore.pollTask   ──(2s)──▶ netstat/ifconfig/CoreWLAN
NetworkStore metadata   ──(30s 캐시/주소 변경/수동 갱신)──▶ gateway/DNS
DeviceStore             ── DiskArbitration 콜백(이벤트 드리븐) + 수동 refresh
```

`lsof`/`ps`는 빠르지만 `nettop -x -l 1`은 무조건 ~5초를 소비하므로 별도 태스크로 분리 — 포트 테이블은 빠르게 갱신되고 Net 컬럼만 느리게 따라온다.

## diff → 이벤트 파이프라인

```
PortStore.refresh()
  └─ listener diff 계산 (첫 스냅샷은 baseline으로 스킵)
       └─ onDiff(added, removed)
            └─ MonitorEngine
                 ├─ ActivityStore.log(.listener, ...)
                 ├─ NotifyService.post (설정 토글 시)

PortStore.onSnapshot (첫 스냅샷 포함) / PresetStore.onChange
  └─ MonitorEngine → 프리셋 상태 전환 평가 (conflict 발생 시 알림)

DiskService 콜백 (DA appeared/changed/disappeared)
  └─ DeviceStore.handle — mount↔unmount 전환을 .appeared/.unmounted로 재해석
       └─ onDiskEvent → MonitorEngine → 로그 + 알림
```

"변화"만 이벤트가 된다 — 정적인 상태는 로그에 안 남는다. 기존 상태의 초기 flood는 baseline/suppression으로 억제.

## 디렉터리 맵

```
Sources/PortManager/
├── main.swift              # --selftest 분기
├── PortManagerApp.swift    # Scene 선언 + Store 주입
├── AppState.swift          # Store 컨테이너 + 사이드바 선택 상태
├── SelfTest.swift          # 인바이너리 테스트 러너
├── Models/                 # PortEntry, PortPreset, VolumeInfo, DeviceNode,
│                           #   ProcessInfo, ActivityEvent, NetInterface, NetRate,
│                           #   ProcessGroup, DockerContainer, BandwidthAlert
├── Services/               # 외부 프로세스/API 래퍼 (위 표 참고)
├── Stores/                 # @MainActor 상태 + 폴링 + diff
└── Views/
    ├── MainWindow.swift    # NavigationSplitView + 사이드바 (Settings 탭 포함)
    ├── Ports/              # 테이블, 인스펙터, KillSheet, IconCache
    ├── Network/            # 인터페이스 목록 뷰
    ├── Devices/            # 디바이스 트리, EjectSheet
    ├── Presets/            # 리스트 + 편집 시트
    ├── MenuBar/            # 라벨(리스너 수) + 팝오버
    ├── Activity/           # 로그 리스트
    └── Settings/           # 폼 — 사이드바 탭과 ⌘, 창 양쪽에서 재사용
```

## 동시성 규칙

- Swift 6 strict concurrency. 모든 Store는 `@MainActor`, Service는 `Sendable`.
- 무거운 호출은 `Background.run`의 detached task → 완료 후 메인에서 `@Published` 대입. 부모 취소가 수집기와 실행 중인 명령에 전파된다.
- `RefreshGate`는 Port/Network/Device의 수집을 직렬화하고 겹치는 요청은 최신 요청 하나로 합친다. 옵션이 변경된 동안 수집한 포트 결과는 버린다.
- rate는 monotonic uptime으로 계산하며, 사라진 PID/연결/인터페이스 카운터는 즉시 제거한다.
- 포트 폴링 간격 0은 일시정지다. 수동 새로고침은 가능하다.
- nettop은 Ports 화면이 보이거나 활성 대역폭 알림 규칙이 있을 때만 실행한다. 화면별 UUID로 여러 창의 수명을 구분한다.
- DiskArbitration 콜백은 DA 전용 큐에서 오므로 `Task { @MainActor in ... }`로 hop.
- 숫자 표시는 `Text(verbatim:)` 또는 미리 포맷한 `String` — `Text` 보간은 로케일 그룹핑(`91,595`)을 넣는다.
