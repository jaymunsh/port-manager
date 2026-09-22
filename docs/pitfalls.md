# macOS/SwiftUI 함정 모음

개발하면서 실제로 발로 밟은 것들 — 각각 재현/진단/해결을 겪은 이슈.

## 1. `MenuBarExtra(isInserted:)` + 라이브 바인딩 = 앱 전체 정지 ⚠️ 최악

```swift
// ✗ 이 코드는 앱을 죽인다
@AppStorage("menubar.enabled") var menuBarEnabled = true
MenuBarExtra(isInserted: $menuBarEnabled) { ... }
```

**증상**: 앱 프로세스는 살아있고 창도 그려지는데, CPU 100% + 모든 Task가 영영 스케줄 안 됨 (폴링 정지, "0 sockets").

**진단**: `sample`로 잡은 메인 스레드가 `makeMainMenu → AppMenuBarExtrasController.updateMenuBarExtras → MenuBarExtraController.observeValue(KVO) → updateButton → requestUpdate → graphDidChange → scenesDidChange` 를 무한 루프. status item 업데이트가 KVO를 다시 발사해 자기 자신을 재무효화.

**해결**: `isInserted`에는 `.constant(...)`만 — 실행 시 한 번 읽은 값으로 삽입 여부를 고정하고, 토글은 재시작 시 반영.

## 2. `openSettings()`는 MenuBarExtra에서 묵묵히 실패

`@Environment(\.openSettings)`를 MenuBarExtra 팝오버에서 호출하면, 앱이 비활성 상태일 때 아무 일도 안 일어난다 — 에러도 없음.

**해결**: 별도 Settings 창을 열지 말고 메인 창의 Settings 탭으로 딥링크 (`state.section = .settings` + `openWindow(id:) + NSApp.activate`). 창을 여는 경로는 항상 동작.

## 3. 중첩 ObservableObject는 전파되지 않는다

```swift
class AppState: ObservableObject {
    let ports = PortStore()  // PortStore도 ObservableObject
}
// View에서 @EnvironmentObject var state 만 잡으면
// ports.entries가 바뀌어도 뷰가 안 갱신됨 — let 프로퍼티라 objectWillChange가 안 탐
```

**증상**: `open`으로 실행하면 폴링은 도는데 UI가 "0 listeners"로 얼어붙음. 터미널 직접 실행은 정상이라 디버깅이 꼬였다(실행 경로 따라 다르게 보임).

**해결**: Store들을 각각 별도 `@EnvironmentObject`로 주입해 뷰가 직접 관찰하게.

## 4. `Text` 보간 숫자에 로케일 그룹핑

`Text("pid \(pid)")` → `pid 91,595`로 렌더된다 — `Text`의 LocalizedStringKey 보간이 숫자를 로케일 포맷하기 때문. 포트 번호 `8,123`으로 보이면 어색.

**해결**: `Text(verbatim: "\(pid)")` 또는 미리 만든 `String`.

## 5. bare 바이너리는 UNUserNotificationCenter 크래시

`swift build` 산출물을 `.app` 없이 직접 실행하면 `bundleProxyForCurrentProcess is nil`로 크래시 — UserNotifications는 번들 컨텍스트 필수. `.app`으로 패키징하고 `open`으로 실행할 것.

## 6. `nettop -x -l 1`은 무조건 ~5초

`-l 1`(샘플 1개), `-s`, `-P` 무관하게 호출당 5초를 소비한다 — 내부 샘플링 윈도우 때문으로 추정. 포트 폴링 경로에 넣으면 UI가 5초+씩 느려진다 → 별도 태스크로 분리.

보너스: `nettop`에서 `-P`를 빼면 프로세스 합계 헤더 + 연결별(`local<->remote`) 자식 행이 나온다 — 소켓별 대역폭을 얻을 수 있는 문서화 잘 안 된 출력.

## 7. DiskArbitration 이벤트의 함정 3개

- **시작 flood**: 세션 만들면 이미 붙어있는 디스크 전부에 `.appeared` 발사 → baseline 윈도우로 억제
- **마운트/언마운트는 `.changed`로 온다** — appeared/disappeared만 보면 재마운트를 놓침. `mountPoint` 전환 비교로 재해석
- **비볼륨 오브젝트**: 물리 디스크, APFS 컨테이너, EFI 파티션까지 이벤트가 옴 — EFI는 kind가 `msdos`(FAT32)로 보고되니 `efi` 체크로는 못 잡음

## 8. SwiftUI Table 제약

- `sortUsing:`의 comparator는 모든 컬럼에서 **하나의 concrete 타입**이어야 함 — `[any SortComparator]`는 안 됨. → 키 enum + 외부 데이터를 들고 있는 단일 `RowComparator` struct로 (Equatable/Hashable도 필요)
- 컬럼이 많아지면 **타입체커 타임아웃** — `@TableColumnBuilder` 프로퍼티로 분리하면 해결
- `OutlineGroup`의 `children` 키패스는 `Optional` 배열이어야 함 (`nil` = 리프)

## 9. `Self`는 stored property initializer에서 못 씀

```swift
@Published var x = Self.defaultsBool(...)  // ✗ covariant 'Self'
@Published var x = MonitorEngine.defaultsBool(...)  // ✓ 타입명 직접
```

didSet 등 인스턴스 컨텍스트에서는 `Self` 가능.

## 10. `swift test`가 CLT에서 조용히 아무것도 안 함

테스트 타겟이 컴파일은 되는데 런타임에 `Testing.framework`/`lib_TestingInterop.dylib`를 못 찾거나, 아무 출력 없이 종료. → 실행 타깃에 `--selftest` 플래그로 인바이너리 러너를 심는 게 확실하다.
