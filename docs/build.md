# 빌드 시스템 — Xcode 없이 macOS 앱 만들기

이 프로젝트는 Xcode 프로젝트가 없다. Command Line Tools만으로 SwiftPM 빌드 → `.app` 번들 수동 조립 → ad-hoc 코드사인까지 한다.

## 파이프라인

```
make build
  └─ Scripts/build_app.sh release
       ├─ swift build -c release
       ├─ PortManager.app/Contents/{MacOS,Resources} 조립
       │    ├─ 바이너리 복사
       │    ├─ Resources/Info.plist 복사
       │    └─ Resources/AppIcon.icns 복사
       └─ codesign --force --deep --sign -   (ad-hoc)
```

`Makefile` 타겟:

| 명령 | 동작 |
|------|------|
| `make build` | release 빌드 + `.app` 패키징 |
| `make debug` | debug 빌드 + 패키징 |
| `make run` | build + 기존 인스턴스 종료 + `open` |
| `make test` | `swift build` + `.build/debug/PortManager --selftest` |
| `make clean` | `.build`, `.app` 제거 |

## 왜 ad-hoc 사인인가

개발용 로컬 앱이라 Developer ID가 없다. ad-hoc(`--sign -`) 사인이라도 번들이 "서명된" 상태가 되면:

- `UNUserNotificationCenter`가 정상 동작 (무사인 번들은 알림 등록 실패)
- TCC(권한) 상태가 번들 정체성에 귀속 — 코드 바뀌어도 권한 재요청 없음
- `SMAppService` 로그인 실행 등록이 가능

## 인바이너리 테스트 (`--selftest`)

CLT 환경에는 `swift test` 러너가 없다 (`Testing`/`XCTest` 프레임워크 경로/런타임 문제). 대신 실행 바이너리에 테스트 러너를 심었다:

```swift
// main.swift
if CommandLine.arguments.contains("--selftest") {
    Task { @MainActor in await SelfTest.run() }
    RunLoop.main.run()
} else {
    PortManagerApp.main()
}
```

`SelfTest.swift`는 간단한 `check(_:_:)` 어설션 + 섹션 출력 러너. 커버하는 것:

- `LsofParser` — TCP 리스너, UDP, IPv6, `->` remote 분리, `TST=` 상태
- `ProcessService.parseStats` — `ps` 출력 파싱
- `NettopProvider.parse` — 프로세스 헤더 + 연결별 카운터
- `PresetStore.status` — free/expected/conflict 규칙
- `LsofProvider` live — 실제 `lsof` 스냅샷이 비어있지 않은지
- 명령 실행 — stderr 대량 출력, 타임아웃, 취소 전달
- 기록/감시 — 여러 날짜의 히스토리 복원·삭제, 초기 프리셋 충돌과 규칙 변경
- 종료/꺼내기 — 보호 프로세스·PID 재사용 검사, 실패한 언마운트 이후 eject 중단
- Store 수명 — 수집 직렬화, 오래된 옵션 결과 폐기, 폴링 일시정지, 대역폭 수집의 시작·중단과 DNS 캐시

## 앱 아이콘

Xcode asset catalog 없이 스크립트로 만든다:

```
Scripts/render_icon.swift   # AppKit으로 1024px PNG 렌더링
                            # (파란 그라데이션 rounded-rect + "network" SF Symbol)
Scripts/make_icon.sh        # PNG → iconset → icns → Resources/AppIcon.icns
```

`render_icon.swift`는 `swift` 인터프리터로 바로 실행하는 단일 파일 — `NSImage.lockFocus` + `NSGradient` + `NSImage(systemSymbolName:)`.

## Info.plist 주의사항

최소한의 키만 들어있다 — 번들ID, 이름, 실행파일, `CFBundleIconFile`, `LSMinimumSystemVersion 15.0`, `NSPrincipalClass NSApplication`.

- **번들 실행 필수**: bare `.build/release/PortManager` 실행은 `UNUserNotificationCenter` 접근 시 `bundleProxyForCurrentProcess is nil` 크래시
- `LSUIElement` 미설정 — Dock + 메뉴바 둘 다 노출되는 일반 앱 모델
- Wi-Fi SSID는 위치 권한 없으면 macOS가 숨김 — 필요하면 `NSLocationUsageDescription` + Core Location 권한 추가 필요
