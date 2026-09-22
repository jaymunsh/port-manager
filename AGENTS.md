# PortManager

macOS port manager — 네트워크 포트(LISTEN 조회/안전 종료/프리셋/모니터링) + 물리 포트(USB/Thunderbolt/외장 스토리지 + 안전 eject)를 통합 관리하는 SwiftUI 앱. Dock 메인 윈도우 + 메뉴바 팝오버.

## Build / Run / Test

Xcode 없이 SwiftPM + 스크립트로 개발한다 (CLT만 설치된 환경).

- `make build` — release 빌드 + `PortManager.app` 패키징
- `make debug` — debug 빌드 + 패키징
- `make run` — build + `open PortManager.app`
- `make test` — `swift build` 후 `.build/debug/PortManager --selftest` 실행
- `make clean`
- `./Scripts/make_icon.sh` — `Resources/AppIcon.icns` 재생성 (아이콘 소스는 `Scripts/render_icon.swift`)

## 주의사항

- **테스트는 `swift test`가 아니라 인바이너리 `--selftest`** — CLT에는 사용 가능한 test runner가 없다. 테스트 추가는 `Sources/PortManager/SelfTest.swift`에 `check(...)` 호출로.
- **반드시 .app 번들로 실행할 것** — bare 바이너리로 실행하면 `UNUserNotificationCenter`가 `bundleProxyForCurrentProcess is nil` 예외로 크래시한다.
- **Store 주입 규칙** — `AppState`의 프로퍼티(`ports`, `devices`, `presets`, `activity`, `monitor`)는 각각 별도 `@EnvironmentObject`로 주입된다. `AppState` 자체는 `let` 프로퍼티라 중첩 `ObservableObject` 변경이 전파되지 않으므로, 뷰는 필요한 Store 타입으로 선언해야 UI가 갱신된다 (`@EnvironmentObject var ports: PortStore`).
- **LocalizedStringKey 함정** — `Text("pid \(pid)")` 같이 보간된 숫자는 로케일 그룹핑(`91,595`)이 붙는다. 포트/PID 표시는 `Text(verbatim:)` 또는 `String`을 먼저 만들어 사용.
- Swift 6 strict concurrency — Store는 `@MainActor`, Service는 `Sendable` struct/함수.

## 구조

- `Models/` — PortEntry, PortPreset, VolumeInfo, DeviceNode, ProcessInfo, ActivityEvent, NetInterface, NetRate
- `Services/` — LsofProvider(lsof -F 파싱, `includeConnections`로 outbound 포함), LsofParser(TST=state, `->` remote), ProcessService(proc_pidpath/kill/ps stats), NettopProvider(프로세스별 누적 바이트→Store에서 rate 계산), NetworkProvider(netstat -ibn/ifconfig/scutil/CoreWLAN), USBProvider, DiskService(DiskArbitration), NotifyService(UN), Shell, ByteFormat
- `Stores/` — PortStore(폴링+diff는 리스너만+netRates), DeviceStore, PresetStore(JSON 영속화), ActivityStore, MonitorEngine(diff→알림), NetworkStore(2s 폴링+rate delta)
- `Views/` — Ports/, Network/, Devices/, Presets/, MenuBar/(팝오버+라이브 ↓레이트 라벨), Activity/, Settings/
- 설정 영속화 — UserDefaults(`ports.*`, `notify.*`) + `@AppStorage`(뷰 상태). Table 정렬은 컬럼 전부 하나의 `RowComparator` 타입을 써야 함(SwiftUI Table 제약).
- `main.swift` — `--selftest` 분기 후 `PortManagerApp.main()`

## 권한/제약

- root/타유저 프로세스 kill은 EPERM — UI에서 `sudo kill` 안내 (권한 헬퍼는 코드사이닝 필요로 미구현)
- 외장 디스크 eject는 DiskArbitration `DADiskUnmount`/`DADiskEject` — busy 시 `lsof`로 점유 프로세스 표시 후 force 옵션
