> **Documentation version: v3.2.0-beta.1.** This translated guide describes the older release. Current UI and installer documentation: [English](README.md), [简体中文](README.zh-CN.md), [v3.3 Setup EXE](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.3.0-beta.1/WiFiProxyPilot-Setup-x64.exe). The application UI supports en-US and zh-CN; README translation does not imply another UI language.

<div align="center">
  <h1>WiFi Proxy Pilot</h1>
  <h3>Windows 智慧 Wi-Fi Proxy 切換工具</h3>
  <p>輕量、現代的 Windows 工具，根據 Wi-Fi SSID、閘道位址與使用者自訂規則，自動切換系統 Proxy。</p>

  ![Windows 11](https://img.shields.io/badge/Windows-11-0078D4)
  ![.NET 8](https://img.shields.io/badge/.NET-8-512BD4)
  ![WPF](https://img.shields.io/badge/UI-WPF-6557E8)
  [![Release](https://img.shields.io/github/v/release/jeffxuu/WiFiProxyPilot?include_prereleases)](https://github.com/jeffxuu/WiFiProxyPilot/releases/tag/v3.2.0-beta.1)
  [![MIT License](https://img.shields.io/badge/License-MIT-green)](LICENSE)
  [![GitHub Stars](https://img.shields.io/github/stars/jeffxuu/WiFiProxyPilot?style=flat)](https://github.com/jeffxuu/WiFiProxyPilot/stargazers)
</div>

**[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Tiếng Việt](README.vi.md)**

**Wi-Fi 切換，Proxy 隨行。** 在一般 Wi-Fi 網路使用閘道提供的 Proxy，並在你指定的網路直接連線。透過現代 WPF 桌面介面或系統匣管理。

> **v3.2.0-beta.1 為 Beta／Prerelease。** 螢幕擷取來自實際執行的 WPF 應用程式，網路資料為模擬。實際網路、登入／睡眠、安裝與解除安裝驗收，與隔離回歸測試分別記錄。目前軟體介面使用簡體中文；README 翻譯不表示介面已支援這些語言。儲存庫為 Public；下載入口請見下方說明。

## 軟體畫面

![Overview — 實際 WPF 應用程式，模擬網路](docs/images/dashboard.png)

| Wi-Fi 規則 | 設定 |
| --- | --- |
| ![Wi-Fi 規則預覽](docs/images/rules.png) | ![設定預覽](docs/images/settings.png) |

<details>
<summary>深色佈景主題預覽</summary>

![深色佈景主題 — 較早的 WPF 首頁版面](docs/images/dashboard-dark.png)

</details>

![系統匣選單 — 目前應用程式，隔離模擬狀態](docs/images/tray.png)

所有圖片都是隔離測試環境中的真實應用程式畫面，**不能作為實際 Proxy 連線成功的證據**。深色畫面採用較早的首頁版面。系統匣圖片來自目前應用程式實際顯示的選單，使用隔離模擬狀態。

## 核心功能

- 識別目前連線的 Wi-Fi，以完整 SSID 比對使用者規則，不區分大小寫。
- 自動取得目前實體 Wi-Fi 介面的 **IPv4 預設閘道**，搭配你設定的 Proxy 連接埠，預設為 `7890`。
- 為指定網路設定直接連線規則。新安裝**沒有內建 Wi-Fi 規則**，每條規則都能編輯或刪除。
- 提供 macOS-inspired WPF 介面、淺色／深色佈景主題、系統匣與獨立背景 Watcher。
- 分別呈現自動管理、Windows 手動 Proxy 狀態與選用 TCP／HTTP 診斷。啟用 Proxy 不表示網際網路可用。
- 以不可分割的方式儲存設定，明確區分「已儲存」與「背景已套用」。
- 保留原始手動 Proxy 備份，保護使用者或其他應用程式後續修改的設定。
- 提供 MIT 授權的原始碼，方便檢查及參與貢獻。

## 下載與安裝

**[下載 v3.2.0-beta.1 — Beta／Prerelease](https://github.com/jeffxuu/WiFiProxyPilot/releases/tag/v3.2.0-beta.1)** · **[瀏覽 Releases](https://github.com/jeffxuu/WiFiProxyPilot/releases)** · **[Windows 建置結果](https://github.com/jeffxuu/WiFiProxyPilot/actions/workflows/build.yml)**

此發行包含上方展示的 v3.2 WPF 介面，標記為 Beta／Prerelease，尚未完成所有實際網路與安裝生命週期驗收。安裝前請核對發行說明與 SHA256。Release 徽章包含預發行版本；Actions 建置產物有保留期限。

- [下載 EXE](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/WiFiProxySwitcher.exe)
- [下載 ZIP](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/WiFiProxySwitcher.zip)
- [下載 SHA256 驗證檔案](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/SHA256.txt)

目標平台為 **Windows 11 x64**，需要 Windows PowerShell 5.1、WLAN 服務與 Windows Script Host。自包含 EXE 不需要另外安裝 .NET、Python、Node.js 或 WebView2。不宣稱已驗證更廣泛的 Windows 相容性。組織原則可能限制 WLAN 資訊、Proxy 設定或排程工作。目前的建置未簽署，請保持 Windows 安全防護啟用。

下載 EXE 或解壓縮 ZIP，並與隨附的 `SHA256.txt` 核對雜湊值：

```powershell
Get-FileHash .\WiFiProxySwitcher.exe -Algorithm SHA256
```

執行檔保留 `WiFiProxySwitcher.exe` 名稱，以維持升級相容性。請以日常使用的一般 Windows 互動式使用者執行。僅開啟 v3.2 視窗不會啟用 Proxy 管理。不要用另一位系統管理員的帳戶替日常帳戶安裝。

## 快速開始與首次設定

1. **下載**建置，核對版本與雜湊值。
2. **設定**現有閘道 Proxy 服務的監聽連接埠，並新增需要直接連線的 Wi-Fi 名稱。
3. 檢閱程式即將管理的設定後，**啟用自動切換**。

**閘道必須確實執行 Proxy 服務。WiFi Proxy Pilot 不提供 Proxy 伺服器或 VPN 節點。** 使用 Android 熱點時，程式會自動讀取目前的 IPv4 閘道；你需要設定手機 Proxy 應用程式的監聽連接埠，並確保它允許透過熱點連線的 Windows 裝置存取。熱點本身並不是 Proxy 服務。

## 運作方式

```text
連線 Wi-Fi → 讀取穩定的 SSID／介面快照 → 比對使用者規則
  ├─ 符合直接連線規則 → 關閉 Windows 手動 Proxy
  └─ 沒有符合的規則   → 取得目前 Wi-Fi 的 IPv4 閘道
                        → 套用閘道位址 + 設定的連接埠
```

背景在套用變更前重新確認目前網路，避免切換 Wi-Fi 後沿用舊閘道。SSID 無法確認、路由缺失或介面有歧義時，保留現有設定、說明原因並重試。確認已中斷連線後，關閉手動 Proxy。PAC 與自動偵測保留原值，仍可能影響應用程式的實際路由。

## Wi-Fi 規則管理

開啟**「Wi-Fi 規則」**即可新增、重新命名、刪除網路，或新增目前可靠識別的網路。支援空白規則清單。比對使用完整名稱的 `OrdinalIgnoreCase` 比較，不比對前綴或子字串。合法空白字元原樣保留；名稱必須為 1–32 個 UTF-8 位元組，且不可含控制字元。

**「儲存並套用」**檢查並行編輯後，以不可分割的方式寫入。「已儲存」只確認檔案寫入；「已套用」需要新的、相容的 Watcher 心跳確認相同設定版本，且目前網路已穩定。尚未符合條件時顯示等待背景套用。取消可放棄尚未儲存的修改。已刪除規則不會被背景悄悄加回。

## 系統匣與 Proxy 模式

| 操作 | 效果 |
| --- | --- |
| 啟用自動切換 | 重新取樣網路，依使用者規則管理手動 Proxy |
| 暫停 | 停止自動寫入 Proxy；保留目前設定 |
| 直接連線 | 暫停管理，僅關閉 Windows 手動 Proxy |
| 立即檢查 | 要求新的網路觀測，並經過穩定確認 |
| 關閉視窗 | 預設隱藏至系統匣；背景繼續執行 |
| 結束介面 | 關閉 GUI／系統匣；獨立背景繼續執行 |
| 還原安裝前設定 | 停止管理，經衝突檢查安全還原原始備份 |

暫停與直接連線意圖在 GUI 重新啟動及重新登入後仍會保留。背景登入啟動與系統匣自動啟動是兩項獨立設定。

**Strict** 依選定規則套用 Proxy，探測失敗時回報原因，不會悄悄關閉 Proxy。**Safe** 可在診斷連續失敗達到設定門檻後改為直接連線，因此部分流量可能略過 Proxy。未知診斷不表示服務恢復。TCP 診斷只證明可連線至該連接埠；HTTP 診斷會透過 Proxy 實際要求你設定的 HTTP 測試 URL。兩者都不能保證所有網站與應用程式正常運作。

## 還原與解除安裝

原始手動 Proxy 備份位於安裝目錄下的 `state/proxy-before-install.json`。升級保留它與使用者規則，不重新建立另一份「原始」備份。設定修改會保留前一份有效檔案。請勿公開這些本機檔案。

已有安裝可開啟 v3.2 EXE，進入**「設定 → 進階操作 → 修復安裝／升級」**。不要先解除安裝，也不要用儲存庫預設值覆蓋個人設定。詳見[設定移轉](docs/CONFIG_MIGRATION.md)。

使用**「還原安裝前設定」**、**「設定 → 進階操作 → 解除安裝」**，或 Windows「已安裝的應用程式」。還原／解除安裝會比較目前設定與原始設定、工具最後寫入的設定。後續外部修改會觸發衝突，避免遭到覆蓋。強制還原需要明確選擇；解除安裝時也可以保留目前 Proxy。清理僅針對自有工作／啟動記錄與已驗證歸屬的產品檔案，保護無關或使用者修改過的檔案。直接連線模式保留原始備份。

## 安全與隱私

- SSID、Proxy 設定、狀態與記錄在本機處理；不需要雲端帳戶或分析服務。
- 程式不收集 Wi-Fi 密碼。選用診斷會連線至所選 Proxy；HTTP 模式也會存取你設定的 URL。
- 保留原始 Proxy 備份；安裝與工作操作遵循目前使用者的身分及權限檢查。
- 程式管理目前使用者的 Windows **手動 Proxy**，不變更 DNS、路由或防火牆規則。
- 記錄與診斷可能包含網路識別資訊，分享前請檢查並遮蔽敏感內容。

安全問題回報方式見 [SECURITY.md](SECURITY.md)。

## 常見問題

**如何在 Windows 11 依 Wi-Fi 自動切換 Proxy？** 設定閘道 Proxy 連接埠、新增直接連線 SSID，然後啟用自動切換。背景會穩定確認 Wi-Fi 變化，並管理目前使用者的 Windows 手動 Proxy 設定。

**如何將 Android 熱點閘道當作 Windows Proxy？** 在手機上執行獨立 Proxy 服務，允許熱點連線的裝置存取，並在 Pilot 填入監聽連接埠。閘道從目前 Wi-Fi 介面自動取得。無法存取時，檢查手機上的 Proxy 服務與防火牆。

**WiFi Proxy Pilot 包含 VPN 嗎？** 不包含。它管理 Windows 手動 Proxy 設定，你需要自行提供服務。使用自己的 Proxy 或忽略 Windows 設定的應用程式，可能有不同的行為。

**Proxy 已啟用，為什麼網際網路仍不可用？** 閘道可能沒有 Proxy 服務、連接埠可能有誤、服務可能已停止，或目的網站無法存取。請個別查看 TCP／HTTP 診斷。暫停保留目前設定，直接連線關閉手動 Proxy；PAC 仍可能影響流量。

**如何讓特定 Wi-Fi 略過 Proxy？** 將完整 SSID 新增至「Wi-Fi 規則」，儲存並套用。每條規則都能編輯或刪除；空白清單也有效。

**如何還原 Windows Proxy 設定？** 選擇「還原安裝前設定」，並檢閱後續外部修改造成的衝突。直接連線僅關閉手動 Proxy，不會還原原始伺服器位址與略過清單。

**關閉視窗後，程式仍會執行嗎？** 會。X 預設隱藏至系統匣。結束 GUI 後獨立背景仍會執行；要變更背景管理，請使用暫停或還原操作。

**為什麼無法讀取目前網路？** WLAN／位置權限、組織原則、路由缺失、背景停止或心跳過期，都可能影響可靠狀態。介面會顯示原因與上次有效觀測，不會把舊資料當作目前資料。

**哪些行為已經測試？** 請參閱 [v3.2 測試結果](docs/TEST_RESULTS_V3_2.md)、[效能證據](docs/PERFORMANCE_V3_2.md)與[發行檢查表](docs/RELEASE_CHECKLIST.md)。隔離檢查不等於實際網路或安裝驗收；效能目標也不等於實測結果。

## Star History

如果 WiFi Proxy Pilot 讓你的日常工作更輕鬆，歡迎為專案點一個 Star。

<a href="https://star-history.com/#jeffxuu/WiFiProxyPilot&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
    <img alt="WiFi Proxy Pilot Star History" src="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
  </picture>
</a>

官方即時 SVG 使用本儲存庫真實的 GitHub 資料。截至 2026-10-14，經核驗的星標數為 0，因此空白圖表是預期結果。不會偽造星標或成長，也不會用虛構資料取代空白歷史。參閱[官方嵌入說明](https://www.star-history.com/blog/how-to-use-github-star-history/)。

## 貢獻與路線圖

歡迎有儲存庫存取權限的使用者提交 Issues 與 Pull Requests。請說明建置版本、預期／實際行為，並附已遮蔽敏感內容的證據。Windows 建置與審查流程見 [CONTRIBUTING.md](CONTRIBUTING.md)。不要提交個人設定、Proxy 備份、憑證或未遮蔽敏感內容的記錄。

計畫包含實際升級／登入／睡眠／解除安裝驗收、剩餘 WPF 無障礙與版面檢查、啟動效能改善，以及介面本地化。這些是計畫，不是已交付的功能；自動更新尚未實作。

使用 `global.json` 指定的 SDK 與 Windows PowerShell 建置：

```powershell
powershell.exe -NoProfile -File tests\Run-Tests.ps1 -ResultPath artifacts\engine-results.json
powershell.exe -NoProfile -File release\Build.ps1
```

建置會產生自包含的 `win-x64` EXE，不會安裝程式或變更本機 Proxy。現有 `WiFiProxySwitcher` 安裝、登錄、互斥鎖與工作識別名稱繼續保留，以維持相容性。

## 授權

專案原始碼採用 [MIT](LICENSE) 授權。第三方資料遵循各自條款，請參閱[第三方聲明](docs/THIRD_PARTY_NOTICES.md)。系統字型直接使用 Windows 已安裝的資源，不重新散布字型檔案。
