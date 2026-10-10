# Open-HotSpot

[English](README.md) · [العربية](README.ar.md) · [简体中文](README.zh-CN.md) · [한국어](README.ko.md) · [Deutsch](README.de.md) · [日本語](README.ja.md)

Open-HotSpot은 [openNDS](https://opennds.readthedocs.io/)를 포털 및 트래픽 실행 엔진으로 사용하는 OpenWrt용 로컬 Captive Portal·핫스팟 관리 시스템입니다. LuCI에서 관리할 수 있습니다.

> **상태: 프로덕션 전 검증 후보.** 구현과 자동화 테스트는 상당히 진행되었지만 실제 라우터 검증 게이트가 아직 모두 닫히지 않았습니다. 현장 증거가 완료되기 전에는 `1.2.0-r112`를 프로덕션 기준선으로 사용하지 마십시오.

## 프로젝트의 목적

Open-HotSpot은 계정, 정책, 사용량 기록, 관리를 OpenWrt 라우터에 로컬로 유지하고, openNDS에 포털과 트래픽 집행을 맡깁니다. RADIUS, 클라우드 서비스, 외부 데이터베이스가 필요하지 않습니다.

## 주요 기능

| 기능 | 설명 |
|---|---|
| 계정 | 로컬 사용자 이름과 PIN |
| 장치 | 계정별 여러 장치, 수명주기 관리와 안전한 재할당 |
| 바우처 | 트랜잭션 기반 일회성 사용 |
| 프로필 | 시간, 기간, 업로드/다운로드 속도, 데이터, 장치 수 제한 |
| 쿼터 | 기간별 누적 사용량과 한도 초과 시 신규 접속 차단 |
| 대시보드 | openNDS 실시간 상태와 SQLite 이력 |
| 관리 | 기본 LuCI / RPC 인터페이스 |
| 포털 | 로컬 아랍어 RTL 및 영어 템플릿 |

## 동작 흐름

```text
클라이언트 → openNDS 포털 → 로컬 FAS → 계정/PIN 확인 → SQLite
                         ↓
                 openNDS 인증 및 트래픽 집행
                         ↓
                 BinAuth 이벤트 → SQLite 사용량 기록
                         ↓
                      LuCI / RPC
```

구조적 경계를 지킵니다. openNDS는 정책 집행 엔진이고 Open-HotSpot은 로컬 신원, 정책, 회계와 관리를 담당합니다. BinAuth는 이벤트 기반이며 `ndsctl`을 호출하지 않습니다.

## 저장소 구조

```text
starter-kit/   라우터에 설치되는 LuCI 및 런타임 파일
tools/         빌드, 검증, 설정, 진단 및 통제된 배포 도구
tests/         Python 테스트, Shell 계약, 통합 테스트
docs/          현재 기준, 아키텍처, 검증, 운영 문서와 보관 자료
specs/         요구사항, 결정, 계획과 작업
```

## 현재 후보

```text
Router:       Linksys EA8300
OpenWrt:      25.12.5
Target:       ipq40xx/generic
openNDS:      11.0.0
Open-HotSpot: 1.2.0-r112 — 설치된 후보; 하드웨어 검증 Pending Hardware Validation
```

현재 빌드와 상태는 [`docs/source-of-truth.md`](docs/source-of-truth.md)를 기준으로 합니다. r60과 openNDS 10.3.1-r3는 롤백 기준선으로 보존되어 있습니다.

## 화면 둘러보기

아래 이미지는 관리 화면을 보여줄 뿐이며 현장 검증 증거나 프로덕션 릴리스 주장이 아닙니다.

| 대시보드 | 프로필 |
|---|---|
| ![Open-HotSpot 대시보드](docs/screenshots/dashboard.png) | ![Open-HotSpot 프로필](docs/screenshots/profiles.png) |
| 계정, 세션, 쿼터와 속도 요약. | 시간, 데이터, 속도, 기간과 장치 제한. |

| 계정 | 장치 |
|---|---|
| ![Open-HotSpot 계정](docs/screenshots/accounts.png) | ![Open-HotSpot 장치](docs/screenshots/devices.png) |
| 신원, 프로필, 상태와 만료. | 소유권, 수명주기, 세션과 재할당. |

| 포털 템플릿 |
|---|
| ![Open-HotSpot 포털 템플릿](docs/screenshots/portal-templates.png) |
| 외부 URL에서 다운로드하지 않고 로컬 템플릿 언어를 선택합니다. |

## 완료된 영역과 남은 영역

| 영역 | 상태 |
|---|---|
| 데이터베이스, 쿼터, 바우처와 도메인 계약 | 로컬 Tested |
| Portal → FAS → openNDS → BinAuth 기본 경로 | 대상 경로 Verified |
| 카운터 방향과 네이티브 쿼터 차단 | Pending Hardware Validation — T006 |
| 재시작, 복구와 장애 격리 | 부분 완료 — T011/T086 |
| 중단된 설정의 반복 가능한 복구 | 미완료 — T052/T087 |
| 프로덕션 기준선 | T090 완료 전 차단 |

## 기여가 필요한 작업

- 실제 클라이언트에서 T006 업로드/다운로드 방향과 쿼터 차단을 측정합니다.
- T011/T086 재시작, 복구, 중복 callback과 장애 격리를 검증합니다.
- 깨끗한 대상에서 T052/T087 중단 설정과 복구를 시험합니다.
- T088/T090 및 릴리스 검증 매트릭스를 완료합니다.
- Family Captive Boundary 1/2를 구현하고 현장에서 검증합니다. 현재 OP-203 계약은 식별자 충돌 방지만 증명하며 daemon, FAS, 회계 또는 nftables 격리를 증명하지 않습니다.

먼저 [`CONTRIBUTING.md`](CONTRIBUTING.md), [`프로젝트 상태`](docs/project-status.md), [`릴리스 게이트`](docs/release-gates.md)를 읽어 주세요. mock, 스크린샷 또는 로컬 계약 테스트를 하드웨어 승인으로 해석하지 마십시오.

## 라이선스

[GPL-2.0-or-later](LICENSE) 라이선스를 따릅니다.
