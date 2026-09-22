# 디바이스 — 외장 스토리지, 안전 eject, USB/Thunderbolt

## 볼륨 추적: DiskArbitration

`DiskService`는 `DASession`을 만들고 `DADisk` description 콜백을 구독한다:

- `.appeared` / `.changed` / `.disappeared` 콜백 → `DiskEvent`로 변환
- 콜백은 DA 전용 큐에서 오므로 `Task { @MainActor in }`으로 Store에 전달

`volumeInfo(from:)`의 필터링 — DA는 파티션 맵 오브젝트까지 전부 알려준다:

| 제외 대상 | 판별 |
|-----------|------|
| 물리 디스크 자체 (`disk4`) | `VolumeName`/`VolumePath` 둘 다 없음 |
| APFS 컨테이너 | `kind`이 볼륨이 아님 |
| EFI 파티션 | `kind`가 `efi`가 **아니라** `msdos`로 보고됨(FAT32) → 볼륨명 `EFI` + GPT 콘텐츠 GUID `C12A7328-…`로 제외 |

통과 조건: `ejectable || !internal` (외장만).

## 이벤트 재해석 (DeviceStore.handle)

두 가지 함정을 흡수한다:

1. **시작 flood**: 세션 시작 시 DA가 이미 연결된 모든 디스크에 `.appeared`를 쏜다 → `suppressingBaseline`으로 약 2초간 이벤트 통지 억제 (목록에는 추가하되 로그/알림만 스킵)
2. **마운트 전환**: 같은 디스크의 mount↔unmount는 `.appeared`/`.disappeared`가 아니라 `.changed`로 온다 → `mountPoint` 전환을 비교해 `.appeared`(unmounted→mounted) / `.unmounted`(mounted→unmounted)로 재해석

## 안전 eject (`EjectSheet`)

흐름: 확인 → unmount → eject

- `DADiskUnmount` 먼저, 실패 시 `lsof`로 마운트 포인트 점유 프로세스를 찾아 목록 표시 → Force Eject(강제 unmount) 옵션 제공
- `DADiskEject`는 볼륨의 **부모 물리 디스크**를 꺼냄 — 파티션이 여러 개여도 디스크 전체가 안전 제거됨
- 성공/실패 모두 Activity 로그

실기 검증됨: 1TB 외장 NVMe(`LocalLLM`)로 unmount→eject→재마운트까지 확인.

## USB / Thunderbolt 트리

`USBProvider`는 `system_profiler SPUSBDataType -json` / `SPThunderboltDataType -json`을 파싱해 `DeviceNode` 트리를 만든다:

- `_items` 재귀로 버스 → 허브 → 디바이스 계층
- 노드 detail은 관심 키 화이트리스트(vendor_id, serial, speed, bus_power, route_string 등)를 `·`로 이어붙임
- `DeviceListView`는 `OutlineGroup`으로 트리 렌더 (children이 `Optional`이어야 함 — `nil`이 리프)
