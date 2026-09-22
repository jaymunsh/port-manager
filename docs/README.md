# PortManager 문서

macOS 네이티브 포트/디바이스 관리 앱. 네트워크 포트(LISTEN/연결) + 물리 포트(USB/Thunderbolt) + 외장 스토리지를 한 곳에서 보고, 안전하게 종료/꺼내기까지 제공한다.

## 기술 스택

- **Swift 6 + SwiftUI** (strict concurrency, `@MainActor` Store)
- **Xcode 없이** SwiftPM + 셸 스크립트로 `.app` 패키징 (CLT만 필요)
- 외부 프로세스 기반 수집: `lsof`, `nettop`, `ps`, `netstat`, `ifconfig`, `scutil`, `system_profiler`, `diskutil`
- 네이티브 API: DiskArbitration(디스크 이벤트/unmount/eject), UserNotifications, CoreWLAN(Wi-Fi), ServiceManagement(로그인 실행), NSWorkspace

## 문서 목록

| 문서 | 내용 |
|------|------|
| [architecture.md](architecture.md) | 레이어 구조, 데이터 흐름, 동시성 모델, 디렉터리 맵 |
| [build.md](build.md) | Xcode 없는 빌드/패키징/테스트 파이프라인, 아이콘 생성 |
| [ports.md](ports.md) | lsof 파싱, 포트 테이블, 안전 종료, nettop 대역폭 |
| [devices.md](devices.md) | DiskArbitration 볼륨 추적, 안전 eject, USB/Thunderbolt 트리 |
| [monitoring.md](monitoring.md) | 프리셋 규칙, MonitorEngine, 알림, Activity 로그, 메뉴바 |
| [pitfalls.md](pitfalls.md) | 개발 중 발견한 macOS/SwiftUI 함정 모음 |

## 5초 요약

```
make run    # 빌드 + .app 패키징 + 실행
make test   # 인바이너리 --selftest 실행
```

실행은 반드시 `.app` 번들로 — bare 바이너리는 `UNUserNotificationCenter` 크래시.
