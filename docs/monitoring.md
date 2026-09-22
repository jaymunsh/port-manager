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
- `notifyBandwidth` — 대역폭 임계치 초과

**baseline 규칙**: 앱 시작 시 첫 스냅샷/디스크 flood는 "새 이벤트"가 아니라 기준선 — 알림/로그를 안 쏜다.

## 대역폭 알림 (BandwidthAlert)

`AlertStore`가 `alerts.json`에 규칙을 영속화. 규칙은 **포트** 또는 **프로세스명**(부분 포함) 타깃 + 임계치(bytes/s).

- Ports 테이블 우클릭 "Bandwidth Alert…"로 생성, Presets 탭의 "Bandwidth Alerts" 섹션에서 목록/편집/비활성화
- 평가: `PortStore`의 nettop 루프(~5초)가 끝날 때마다 `onRates` 핸들러 → `MonitorEngine.evaluateBandwidthAlerts`
- rate 계산: 포트 규칙은 해당 포트 소켓들의 connRates 합, 없으면 리스너 pid의 프로세스 합계. 프로세스 규칙은 매칭 pid들의 netRates 합
- **전환 알림**: `alertOver` 맵으로 이전 상태를 기억 — 정상→초과 순간만 로그+알림 (계속 초과 상태면 조용)

## Activity 로그 + 히스토리

`ActivityStore` — 최대 500개 링버퍼, 최신이 위. 종류: `listener`, `preset`, `disk`, `device`, `process`(안전 종료), `bandwidth`.

`HistoryService`가 각 이벤트를 JSONL로 `~/Library/Application Support/PortManager/history/history-YYYY-MM-DD.jsonl`에 append — 껐다 켜도 로그가 남는다. 보관일은 Settings의 "Keep activity for"(기본 7일, `history.retentionDays`), 시작 시 오래된 파일 prune + 최근 파일을 메모리로 로드.

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
