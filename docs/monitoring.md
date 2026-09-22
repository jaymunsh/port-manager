# 모니터링 — 프리셋, 알림, Activity, 메뉴바

## 프리셋 규칙

"이 포트는 원래 이 프로세스가 쓴다"를 선언해두는 감시 규칙.

`PresetStore.status(for:entries:)`:

```
매칭 키: port + proto(TCP/UDP)   ← bind 주소는 보지 않음

free      — 매칭 리스너 없음
expected  — 리스너 있고 (expectedCommand 비어있음 || command가 부분 포함 매칭)
conflict  — 리스너 있는데 command가 expectedCommand와 불일치
```

- `expectedCommand` 매칭은 대소문자 무시 **부분 포함** — `docker`면 `com.docker.backend`도 매칭
- `expectedCommand`를 비우면 "점유 여부"만 감시

`MonitorEngine.evaluatePresets`는 매 폴링마다 상태 전환을 추적한다 (`presetStatuses` 맵에 이전 상태 저장 — 상태가 바뀐 순간만 이벤트):

| 전환 | 이벤트 |
|------|--------|
| → conflict | 로그 + 알림 "Port conflict :8080 held by java" |
| conflict → expected | 로그 "back to expected process" |
| → free | 로그 "is now free" |

## 알림 (NotifyService)

`UNUserNotificationCenter` — alert+sound 권한을 `MonitorEngine.start()`에서 요청.

설정에서 이벤트별 토글 (UserDefaults `notify.*`):
- `notifyNewListeners` — 새 리스너 등장
- `notifyPresetConflicts` — 프리셋 충돌
- `notifyDiskEvents` — 마운트/제거

**baseline 규칙**: 앱 시작 시 첫 스냅샷/디스크 flood는 "새 이벤트"가 아니라 기준선 — 알림/로그를 안 쏜다.

## Activity 로그

`ActivityStore` — 최대 300개 링버퍼, 최신이 위. 종류: `listener`, `preset`, `disk`, `device`, `process`(안전 종료).

"변화"만 기록 — 정적 상태는 안 올라온다.

## 메뉴바

- **라벨** (`MenuBarLabel`): globe 아이콘 + 활성 리스너 수. 네트워크 속도였다가 포트 중심 요구로 교체
- **팝오버** (`MenuBarPopover`, `.window` 스타일, 340×480):
  - 헤더: 리스너/충돌/디스크 수
  - Presets: 상태 점 + 이름 + 포트, conflict 시 Kill 버튼
  - Listeners: CPU 상위 10개 컴팩트 행 + "… N more"
  - External Disks: 볼륨 + eject 버튼
  - 푸터: Open(메인창) / Settings(메인창 Settings 탭으로 딥링크) / Quit

딥링크는 `AppState.section`(@Published)을 바꾸고 `openWindow(id: "main")` — `openSettings()`는 MenuBarExtra에서 앱 비활성 시 묵묵히 실패하는 함정이 있어 쓰지 않는다.

메뉴바 on/off: Settings의 "Show in menu bar" 토글 → `menubar.enabled` UserDefaults → 다음 실행부터 `MenuBarExtra(isInserted: .constant(...))`에 반영. **라이브 바인딩은 KVO 피드백 루프로 앱을 멈추게 하므로 constant만 허용** — [pitfalls.md](pitfalls.md) 참고.
