<div align="center">
  <h1>WiFi Proxy Pilot</h1>
  <h3>Windows용 스마트 Wi-Fi 프록시 전환</h3>
  <p>Wi-Fi SSID, 게이트웨이 주소와 사용자 규칙에 따라 시스템 프록시를 자동으로 전환하는 가볍고 현대적인 Windows 유틸리티입니다.</p>

  ![Windows 11](https://img.shields.io/badge/Windows-11-0078D4)
  ![.NET 8](https://img.shields.io/badge/.NET-8-512BD4)
  ![WPF](https://img.shields.io/badge/UI-WPF-6557E8)
  [![Release](https://img.shields.io/github/v/release/jeffxuu/WiFiProxyPilot?include_prereleases)](https://github.com/jeffxuu/WiFiProxyPilot/releases)
  [![MIT 라이선스](https://img.shields.io/badge/License-MIT-green)](LICENSE)
  [![GitHub Stars](https://img.shields.io/github/stars/jeffxuu/WiFiProxyPilot?style=flat)](https://github.com/jeffxuu/WiFiProxyPilot/stargazers)
</div>

**[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Tiếng Việt](README.vi.md)**

**Wi-Fi가 바뀌면 프록시도 따라 바뀝니다.** 일반 Wi-Fi에서는 게이트웨이에서 제공하는 프록시를 사용하고, 선택한 네트워크에서는 직접 연결할 수 있습니다. 현대적인 WPF 창이나 시스템 트레이에서 관리하세요.

> **v3.2.0-beta.1은 Beta/Prerelease입니다.** 스크린샷은 실제 WPF 앱에 모의 네트워크 데이터를 표시한 것입니다. 실제 네트워크, 로그인/절전, 설치/제거에 대한 검증은 격리된 회귀 테스트와 별도입니다. 현재 UI는 중국어 간체만 지원하며, README 번역이 UI 다국어 지원을 뜻하지는 않습니다. 저장소는 Public 상태입니다.

## 스크린샷

![Overview — 실제 WPF 앱, 모의 네트워크](docs/images/dashboard.png)

| Wi-Fi 규칙 | 설정 |
| --- | --- |
| ![Wi-Fi 규칙 미리 보기](docs/images/rules.png) | ![설정 미리 보기](docs/images/settings.png) |

![시스템 트레이 메뉴 — 실제 앱, 모의 네트워크](docs/images/tray.png)

<details>
<summary>다크 테마 미리 보기</summary>

![다크 테마 — 이전 WPF Overview 레이아웃](docs/images/dashboard-dark.png)

</details>

모든 이미지는 격리된 테스트 환경에서 실제 앱을 촬영한 것이며 **실제 프록시 연결의 증거가 아닙니다**. 다크 테마 이미지는 이전 Overview 레이아웃을 사용합니다. 트레이 메뉴도 격리된 앱 테스트 환경에서 모의 네트워크 데이터로 촬영했습니다.

## 주요 기능

- 연결된 Wi-Fi를 인식하고 전체 SSID를 대소문자 구분 없이 비교합니다.
- 현재 물리 Wi-Fi 인터페이스의 **IPv4 기본 게이트웨이**를 찾고 설정한 프록시 포트를 적용합니다. 기본값은 `7890`입니다.
- 지정한 네트워크에 직접 연결 규칙을 적용합니다. 새 설치에는 **기본 Wi-Fi 규칙이 없으며**, 모든 규칙을 수정하거나 삭제할 수 있습니다.
- macOS에서 영감을 받은 WPF UI, 라이트/다크 테마, 독립적인 백그라운드 감시 프로세스와 시스템 트레이를 제공합니다.
- 자동 관리, Windows 수동 프록시 상태, 선택적 TCP/HTTP 진단을 구분합니다. 프록시가 켜졌다고 인터넷 접속이 보장되지는 않습니다.
- 설정을 원자적으로 저장하고, ‘저장됨’과 ‘감시 프로세스가 적용함’을 구분합니다.
- 원래 프록시 설정의 백업을 보관하고 사용자나 다른 앱이 나중에 변경한 설정을 보호합니다.
- MIT 라이선스로 소스 코드를 제공하여 검토와 기여를 지원합니다.

## 다운로드 및 설치

**[v3.2.0-beta.1 다운로드 — Beta/Prerelease](https://github.com/jeffxuu/WiFiProxyPilot/releases/tag/v3.2.0-beta.1)** · **[EXE](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/WiFiProxySwitcher.exe)** · **[ZIP](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/WiFiProxySwitcher.zip)** · **[SHA256](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/SHA256.txt)** · **[빌드 아티팩트](https://github.com/jeffxuu/WiFiProxyPilot/actions/workflows/build.yml)**

v3.2.0-beta.1은 **Beta/Prerelease**이며 완전히 안정적인 정식 버전은 아닙니다. 설치 전에 버전, 릴리스 노트, `SHA256.txt`의 체크섬을 확인하세요. Release 배지는 Prerelease도 포함합니다. GitHub 빌드 아티팩트에는 보관 기간이 있으므로 이 버전은 위의 릴리스 파일 링크에서 다운로드하세요.

대상 환경은 **Windows 11 x64**, Windows PowerShell 5.1, WLAN 서비스, Windows Script Host입니다. 자체 포함 EXE는 .NET, Python, Node.js, WebView2의 별도 설치가 필요 없습니다. 다른 Windows 버전의 호환성을 검증했다고 주장하지 않습니다. 조직 정책은 WLAN 정보, 프록시 설정, 예약 작업을 제한할 수 있습니다. 현재 빌드는 서명되지 않았으므로 Windows 보안 보호를 켜 두세요.

EXE를 다운로드하거나 ZIP을 풀고 동봉된 `SHA256.txt`와 해시를 비교하세요.

```powershell
Get-FileHash .\WiFiProxySwitcher.exe -Algorithm SHA256
```

업그레이드 호환성을 위해 실행 파일 이름은 `WiFiProxySwitcher.exe`를 유지합니다. 평소 사용하는 대화형 Windows 사용자 계정으로 실행하세요. v3.2 창을 여는 것만으로 프록시 관리가 활성화되지는 않습니다. 다른 관리자의 계정으로 자신의 일상 계정용 설치를 진행하지 마세요.

## 빠른 시작과 첫 설정

1. **다운로드**하고 버전과 해시를 확인합니다.
2. **설정**에서 Wi-Fi 게이트웨이에 실제로 실행 중인 프록시의 포트를 지정하고 직접 연결할 Wi-Fi 이름을 추가합니다.
3. 앱이 관리할 설정을 검토한 뒤 **자동 전환을 활성화**합니다.

**게이트웨이에서 실제 프록시 서비스가 실행되어야 합니다. WiFi Proxy Pilot은 프록시 서버나 VPN 노드를 제공하지 않습니다.** Android 핫스팟에서는 현재 IPv4 게이트웨이를 자동으로 찾습니다. 별도 프록시 앱의 수신 포트를 설정하고 연결된 Windows 기기의 접근을 허용하세요. 핫스팟 자체는 프록시가 아닙니다.

## 작동 방식

```text
Wi-Fi 연결 → 안정적인 SSID/인터페이스 정보 읽기 → 사용자 규칙 비교
  ├─ 직접 연결 규칙 일치 → Windows 수동 프록시 끄기
  └─ 직접 연결 규칙 없음 → 현재 Wi-Fi의 IPv4 게이트웨이 찾기
                          → 게이트웨이 + 설정 포트 적용
```

감시 프로세스는 설정 변경 전에 현재 네트워크를 다시 확인하여 Wi-Fi가 바뀐 후 이전 게이트웨이를 사용하지 않도록 합니다. SSID를 알 수 없거나 경로가 없거나 인터페이스가 모호하면 기존 설정을 유지하고 이유를 표시한 뒤 재시도합니다. 연결 해제가 확인되면 수동 프록시를 끕니다. PAC와 자동 검색은 기존 값을 유지하므로 앱의 통신 경로에 계속 영향을 줄 수 있습니다.

## Wi-Fi 규칙 관리

**Wi-Fi Rules**에서 규칙을 추가, 이름 변경, 삭제하거나 확실하게 감지한 현재 네트워크를 추가할 수 있습니다. 빈 목록도 지원합니다. `OrdinalIgnoreCase`로 전체 이름을 비교하며 접두어나 부분 문자열로 비교하지 않습니다. 허용된 공백은 유지됩니다. 이름은 UTF-8 기준 1–32바이트이고 제어 문자를 포함하면 안 됩니다.

**Save and Apply**는 동시 편집을 검사하고 원자적으로 기록합니다. ‘저장됨’은 파일 기록을 확인합니다. ‘적용됨’에는 같은 리비전의 최신 호환 감시 프로세스 heartbeat와 안정적인 네트워크가 필요합니다. 그렇지 않으면 백그라운드 적용 대기를 표시합니다. 취소는 저장하지 않은 편집을 버립니다. 삭제한 규칙은 자동으로 되살아나지 않습니다.

## 시스템 트레이와 프록시 모드

| 작업 | 결과 |
| --- | --- |
| 자동 전환 활성화 | 네트워크를 다시 관찰하고 규칙에 따라 수동 프록시 관리 |
| 일시 중지 | 자동 변경을 멈추고 현재 프록시 설정 유지 |
| 직접 연결 | 관리를 일시 중지하고 Windows 수동 프록시만 끄기 |
| 지금 확인 | 새 네트워크 관찰과 안정적인 평가 요청 |
| 창 닫기 | 기본적으로 트레이로 숨기며 감시 프로세스는 계속 실행 |
| UI 종료 | GUI/트레이를 종료해도 독립적인 감시 프로세스는 계속 실행 |
| 원래 설정 복원 | 관리를 중지하고 충돌을 확인한 뒤 백업 복원 |

일시 중지와 직접 연결 선택은 GUI 재시작과 Windows 로그인 후에도 유지됩니다. 로그인 시 감시 프로세스 시작과 트레이 시작은 별도 설정입니다.

**Strict**는 선택한 규칙을 적용하고 진단 실패를 보고하며, 프록시를 조용히 끄지 않습니다. **Safe**는 설정한 횟수만큼 연속 진단이 실패하면 직접 연결로 전환할 수 있으므로 일부 트래픽이 프록시를 우회할 수 있습니다. 알 수 없는 진단 결과는 복구로 처리하지 않습니다. TCP 진단은 포트에 연결할 수 있는지만 확인합니다. HTTP 진단은 설정한 HTTP 테스트 URL로 실제 프록시 요청을 보냅니다. 어느 진단도 모든 사이트나 앱의 작동을 보장하지 않습니다.

## 복원 및 제거

원래 수동 프록시 백업은 설치 폴더의 `state/proxy-before-install.json`에 있습니다. 업그레이드는 이 백업과 규칙을 보존하며 새로운 ‘원래 설정’ 백업을 만들지 않습니다. 설정 변경 시 이전의 유효한 파일을 유지합니다. 이 로컬 파일은 비공개로 보관하세요.

기존 설치가 있다면 새 EXE를 열고 **Settings → Advanced operations → Repair installation / Upgrade**를 사용하세요. 먼저 제거하거나 자신의 설정을 저장소 기본값으로 덮어쓰지 마세요. [설정 마이그레이션](docs/CONFIG_MIGRATION.md)을 참고하세요.

**Restore original configuration**, **Settings → Advanced operations → Uninstall** 또는 Windows의 설치된 앱을 사용합니다. 복원/제거는 현재 값을 원래 값 및 이 도구가 마지막으로 기록한 값과 비교합니다. 이후의 외부 변경은 덮어쓰지 않고 충돌로 표시합니다. 강제 복원은 명시적으로 선택해야 하며 제거할 때 현재 프록시를 유지할 수도 있습니다. 제거 대상은 소유한 작업/시작 항목과 확인된 제품 파일로 한정하여, 관련 없는 파일과 사용자가 변경한 파일을 보호합니다. 직접 연결 모드에서도 원래 백업은 유지합니다.

## 보안 및 개인정보 보호

- SSID, 프록시 설정, 상태, 로그는 로컬에서 처리하며 클라우드 계정이나 분석 서비스가 필요 없습니다.
- Wi-Fi 비밀번호를 수집하지 않습니다. 선택적 진단은 선택한 프록시와, HTTP 모드에서는 설정한 URL에 연결합니다.
- 원래 프록시 백업을 보관합니다. 설치와 작업 관리에서 현재 사용자 신원과 권한 검사를 준수합니다.
- 현재 Windows 사용자의 **수동 프록시**를 관리하며 DNS, 라우팅, 방화벽 규칙은 변경하지 않습니다.
- 로그와 진단에 네트워크 식별자가 포함될 수 있습니다. 공유 전에 확인하고 민감한 정보를 가리세요.

보안 문제는 [SECURITY.md](SECURITY.md)에 따라 신고하세요.

## 자주 묻는 질문

**Windows 11에서 Wi-Fi별로 프록시를 자동 전환하려면?** 게이트웨이 프록시 포트를 설정하고 직접 연결용 SSID를 추가한 뒤 자동 전환을 활성화하세요. 감시 프로세스가 안정적인 Wi-Fi 변경을 평가하여 현재 사용자의 수동 프록시를 적용합니다.

**Android 핫스팟의 게이트웨이를 Windows 프록시로 쓰려면?** 휴대전화에서 별도의 프록시 서비스를 실행하고 테더링 기기의 접근을 허용한 뒤 수신 포트를 설정하세요. 게이트웨이는 현재 Wi-Fi 인터페이스에서 찾습니다. 연결되지 않으면 휴대전화의 서비스와 방화벽을 확인하세요.

**VPN이 포함되어 있나요?** 아닙니다. 서비스는 직접 준비해야 합니다. 자체 프록시를 사용하거나 Windows 설정을 따르지 않는 앱은 다르게 작동할 수 있습니다.

**프록시는 켜져 있는데 인터넷이 안 되는 이유는?** 게이트웨이에 프록시가 없거나 포트가 틀리거나 서비스가 중지되었거나 목적지가 응답하지 않을 수 있습니다. TCP/HTTP 진단을 따로 확인하세요. 일시 중지는 설정을 유지하고 직접 연결은 수동 프록시를 끕니다. PAC가 계속 통신에 영향을 줄 수도 있습니다.

**특정 Wi-Fi에서 프록시를 우회하려면?** 전체 SSID를 Wi-Fi Rules에 추가하고 저장/적용하세요. 모든 규칙을 수정·삭제할 수 있고 빈 목록도 유효합니다.

**Windows 프록시 설정을 복원하려면?** 원래 설정 복원을 선택하고 외부 변경 충돌을 확인하세요. 직접 연결은 수동 프록시만 끄며 원래 서버와 우회 목록을 복원하지 않습니다.

**창을 닫아도 계속 실행되나요?** 예. 기본적으로 X는 창을 트레이로 숨깁니다. GUI를 종료해도 독립 감시 프로세스는 계속 실행됩니다. 백그라운드 관리를 바꾸려면 일시 중지나 복원을 사용하세요.

**현재 네트워크를 읽지 못하는 이유는?** WLAN/위치 권한, 조직 정책, 누락된 경로, 중지된 감시 프로세스나 오래된 heartbeat가 원인일 수 있습니다. UI는 오래된 데이터를 현재 상태로 표시하지 않고 이유와 마지막 유효 관찰을 보여 줍니다.

**어떤 테스트가 수행되었나요?** [v3.2 테스트 결과](docs/TEST_RESULTS_V3_2.md), [성능 근거](docs/PERFORMANCE_V3_2.md), [릴리스 체크리스트](docs/RELEASE_CHECKLIST.md)를 참고하세요. 격리된 테스트는 실제 네트워크/설치 검증이 아니며 성능 목표는 측정 결과가 아닙니다.

## Star History

WiFi Proxy Pilot이 작업을 편하게 해 준다면 프로젝트에 Star를 남겨 주세요.

<a href="https://star-history.com/#jeffxuu/WiFiProxyPilot&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
    <img alt="WiFi Proxy Pilot Star History" src="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
  </picture>
</a>

공식 실시간 SVG는 이 공개 저장소의 실제 GitHub 데이터를 사용합니다. 2026-10-14에 확인한 Star 수는 0개이므로 빈 기록은 예상된 상태입니다. 확인 당시 라이트·다크 테마 이미지 URL 모두 HTTP 200을 반환했습니다. Star나 성장을 꾸며 내지 않습니다. [공식 임베딩 안내](https://www.star-history.com/blog/how-to-use-github-star-history/)를 참고하세요.

## 기여 및 로드맵

저장소 접근 권한이 있는 사용자의 Issue와 Pull Request를 환영합니다. 빌드, 기대한 동작, 실제 동작, 민감 정보를 가린 근거를 포함하세요. Windows 빌드 및 검토 절차는 [CONTRIBUTING.md](CONTRIBUTING.md)에 있습니다. 개인 설정, 프록시 백업, 인증 정보, 편집하지 않은 로그를 올리지 마세요.

계획된 작업은 실제 업그레이드/로그인/절전/제거 검증, 남은 WPF 접근성 및 레이아웃 확인, 시작 성능 개선, UI 현지화입니다. 이들은 계획이며 출시된 기능이 아닙니다. 자동 업데이트는 구현되지 않았습니다.

`global.json`의 SDK와 Windows PowerShell로 빌드합니다.

```powershell
powershell.exe -NoProfile -File tests\Run-Tests.ps1 -ResultPath artifacts\engine-results.json
powershell.exe -NoProfile -File release\Build.ps1
```

빌드는 자체 포함 `win-x64` EXE를 생성하며 설치하거나 호스트의 프록시를 변경하지 않습니다. 기존 `WiFiProxySwitcher` 설치, 레지스트리, mutex, 작업 식별자는 호환성을 위해 유지합니다.

## 라이선스

프로젝트 소스는 [MIT](LICENSE) 라이선스를 따릅니다. 제3자 자료에는 각각의 조건이 적용됩니다. [제3자 고지](docs/THIRD_PARTY_NOTICES.md)를 참고하세요. Windows 시스템 글꼴을 사용하며 글꼴을 재배포하지 않습니다.
