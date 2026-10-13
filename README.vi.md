> **Documentation version: v3.2.0-beta.1.** This translated guide describes the older release. Current UI and installer documentation: [English](README.md), [简体中文](README.zh-CN.md), [v3.3 Setup EXE](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.3.0-beta.1/WiFiProxyPilot-Setup-x64.exe). The application UI supports en-US and zh-CN; README translation does not imply another UI language.

<div align="center">
  <h1>WiFi Proxy Pilot</h1>
  <h3>Chuyển proxy thông minh theo Wi-Fi trên Windows</h3>
  <p>Tiện ích Windows nhẹ, hiện đại, tự động chuyển proxy hệ thống dựa trên SSID Wi-Fi, địa chỉ gateway và các quy tắc do bạn đặt.</p>

  ![Windows 11](https://img.shields.io/badge/Windows-11-0078D4)
  ![.NET 8](https://img.shields.io/badge/.NET-8-512BD4)
  ![WPF](https://img.shields.io/badge/UI-WPF-6557E8)
  [![Release](https://img.shields.io/github/v/release/jeffxuu/WiFiProxyPilot?include_prereleases)](https://github.com/jeffxuu/WiFiProxyPilot/releases)
  [![Giấy phép MIT](https://img.shields.io/badge/License-MIT-green)](LICENSE)
  [![GitHub Stars](https://img.shields.io/github/stars/jeffxuu/WiFiProxyPilot?style=flat)](https://github.com/jeffxuu/WiFiProxyPilot/stargazers)
</div>

**[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Tiếng Việt](README.vi.md)**

**Wi-Fi thay đổi, proxy chuyển theo.** Dùng proxy chạy trên gateway ở mạng Wi-Fi thông thường và kết nối trực tiếp ở các mạng bạn chọn. Quản lý qua giao diện WPF hiện đại hoặc biểu tượng ở khay hệ thống.

> **v3.2.0-beta.1 là bản Beta/Prerelease.** Ảnh chụp là ứng dụng WPF thật với dữ liệu mạng mô phỏng. Việc nghiệm thu mạng thật, đăng nhập/ngủ, cài đặt và gỡ cài đặt được thực hiện riêng với kiểm thử hồi quy cô lập. UI hiện chỉ có tiếng Trung giản thể; các bản README dịch không có nghĩa là UI đã hỗ trợ những ngôn ngữ này. Kho mã có trạng thái Public.

## Ảnh chụp màn hình

![Tổng quan — ứng dụng WPF thật, mạng mô phỏng](docs/images/dashboard.png)

| Quy tắc Wi-Fi | Cài đặt |
| --- | --- |
| ![Xem trước quy tắc Wi-Fi](docs/images/rules.png) | ![Xem trước cài đặt](docs/images/settings.png) |

![Menu khay hệ thống — ứng dụng thật, mạng mô phỏng](docs/images/tray.png)

<details>
<summary>Xem trước giao diện tối</summary>

![Giao diện tối — bố cục tổng quan WPF trước đây](docs/images/dashboard-dark.png)

</details>

Tất cả ảnh đều được chụp từ ứng dụng thật trong môi trường kiểm thử cô lập, **không chứng minh một kết nối proxy đang hoạt động**. Ảnh giao diện tối dùng bố cục tổng quan trước đây. Ảnh menu khay cũng được chụp trong môi trường kiểm thử ứng dụng cô lập với dữ liệu mạng mô phỏng.

## Chức năng chính

- Nhận diện Wi-Fi đang kết nối và so khớp toàn bộ SSID, không phân biệt chữ hoa/thường.
- Đọc **gateway mặc định IPv4** của giao diện Wi-Fi vật lý hiện tại, rồi áp dụng cổng proxy đã đặt; mặc định là `7890`.
- Dùng quy tắc kết nối trực tiếp cho mạng được chọn. Bản cài đặt mới **không có quy tắc Wi-Fi cài sẵn**; mọi quy tắc đều sửa hoặc xóa được.
- Cung cấp UI WPF lấy cảm hứng từ macOS, giao diện sáng/tối và khay hệ thống cùng trình theo dõi nền độc lập — watcher.
- Phân biệt quản lý tự động, trạng thái proxy thủ công Windows và chẩn đoán TCP/HTTP tùy chọn. Proxy bật không đồng nghĩa internet hoạt động.
- Lưu cấu hình theo cách nguyên tử và phân biệt “đã lưu” với “watcher đã áp dụng”.
- Giữ bản sao lưu proxy ban đầu, bảo vệ thay đổi sau đó của bạn hoặc ứng dụng khác.
- Cung cấp mã nguồn theo MIT để kiểm tra và đóng góp.

## Tải xuống và cài đặt

**[Tải v3.2.0-beta.1 — Beta/Prerelease](https://github.com/jeffxuu/WiFiProxyPilot/releases/tag/v3.2.0-beta.1)** · **[EXE](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/WiFiProxySwitcher.exe)** · **[ZIP](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/WiFiProxySwitcher.zip)** · **[SHA256](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/SHA256.txt)** · **[Tệp build](https://github.com/jeffxuu/WiFiProxyPilot/actions/workflows/build.yml)**

v3.2.0-beta.1 được cung cấp dưới dạng **Beta/Prerelease**, chưa phải bản chính thức hoàn toàn ổn định. Kiểm tra phiên bản, ghi chú phát hành và checksum trong `SHA256.txt` trước khi cài. Huy hiệu Release bao gồm cả Prerelease. Tệp build của GitHub có hạn lưu trữ; dùng các liên kết tệp release phía trên để tải phiên bản này.

Nền tảng mục tiêu là **Windows 11 x64**, Windows PowerShell 5.1, dịch vụ WLAN và Windows Script Host. EXE tự chứa không yêu cầu cài thêm .NET, Python, Node.js hay WebView2. Không khẳng định đã kiểm chứng tương thích với các phiên bản Windows khác. Chính sách tổ chức có thể hạn chế dữ liệu WLAN, thiết lập proxy hoặc tác vụ theo lịch. Các build hiện chưa được ký; hãy giữ bảo vệ Windows bật.

Tải EXE hoặc giải nén ZIP và so sánh hash với `SHA256.txt` đi kèm:

```powershell
Get-FileHash .\WiFiProxySwitcher.exe -Algorithm SHA256
```

Tên tệp vẫn là `WiFiProxySwitcher.exe` để giữ tương thích nâng cấp. Chạy bằng tài khoản Windows tương tác bạn thường dùng. Chỉ mở cửa sổ v3.2 chưa bật quản lý proxy. Không dùng tài khoản của quản trị viên khác để cài cho tài khoản hằng ngày của mình.

## Bắt đầu nhanh và cấu hình lần đầu

1. **Tải xuống** build và kiểm tra phiên bản/hash.
2. **Cấu hình** cổng của proxy đang chạy trên gateway Wi-Fi, rồi thêm tên Wi-Fi cần kết nối trực tiếp.
3. Xem lại các thiết lập ứng dụng sẽ quản lý, sau đó **bật chuyển đổi tự động**.

**Gateway phải thật sự chạy dịch vụ proxy. WiFi Proxy Pilot không cung cấp máy chủ proxy hoặc nút VPN.** Với điểm phát Android, gateway IPv4 hiện tại được nhận diện tự động. Đặt cổng lắng nghe của ứng dụng proxy riêng và cho phép thiết bị Windows đang chia sẻ mạng kết nối vào. Bản thân điểm phát không phải proxy.

## Cách hoạt động

```text
Wi-Fi kết nối → Đọc dữ liệu SSID/giao diện ổn định → So khớp quy tắc
  ├─ Khớp quy tắc trực tiếp → Tắt proxy thủ công Windows
  └─ Không khớp            → Đọc gateway IPv4 của Wi-Fi hiện tại
                            → Áp dụng gateway + cổng đã cấu hình
```

Watcher kiểm tra mạng hiện tại trước khi đổi thiết lập để không dùng lại gateway cũ sau khi chuyển Wi-Fi. Nếu không biết SSID, thiếu tuyến mạng hoặc giao diện không rõ ràng, ứng dụng giữ thiết lập hiện có, hiển thị lý do và thử lại. Khi xác nhận đã ngắt Wi-Fi, proxy thủ công sẽ tắt. PAC và tự động phát hiện giữ giá trị cũ và vẫn có thể ảnh hưởng đường đi của kết nối.

## Quản lý quy tắc Wi-Fi

Trong **Wi-Fi Rules**, bạn có thể thêm, đổi tên, xóa hoặc thêm mạng hiện tại đã được nhận diện đáng tin cậy. Danh sách rỗng cũng hợp lệ. So khớp dùng toàn bộ tên với `OrdinalIgnoreCase`, không dùng tiền tố hay chuỗi con. Khoảng trắng hợp lệ được giữ nguyên; tên phải dài 1–32 byte UTF-8, không chứa ký tự điều khiển.

**Save and Apply** kiểm tra chỉnh sửa đồng thời và ghi tệp nguyên tử. “Đã lưu” xác nhận ghi tệp. “Đã áp dụng” cần heartbeat mới, tương thích của watcher với cùng revision và mạng ổn định. Nếu chưa đủ, ứng dụng báo đang chờ áp dụng nền. Hủy bỏ loại bỏ thay đổi chưa lưu; quy tắc đã xóa không tự xuất hiện lại.

## Khay hệ thống và các chế độ proxy

| Thao tác | Kết quả |
| --- | --- |
| Bật chuyển đổi tự động | Đọc lại mạng và quản lý proxy thủ công theo quy tắc |
| Tạm dừng | Dừng thay đổi tự động; giữ nguyên thiết lập proxy hiện tại |
| Kết nối trực tiếp | Tạm dừng quản lý và chỉ tắt proxy thủ công Windows |
| Kiểm tra ngay | Yêu cầu quan sát mạng mới và đánh giá ổn định |
| Đóng cửa sổ | Mặc định ẩn vào khay; watcher tiếp tục chạy |
| Thoát giao diện | Đóng GUI/khay; watcher độc lập tiếp tục chạy |
| Khôi phục cấu hình ban đầu | Dừng quản lý và khôi phục bản sao lưu sau kiểm tra xung đột |

Lựa chọn tạm dừng và trực tiếp được giữ qua lần khởi động GUI và đăng nhập Windows tiếp theo. Khởi động watcher khi đăng nhập và khởi động khay là hai thiết lập riêng.

**Strict** áp dụng quy tắc đã chọn và báo lỗi chẩn đoán mà không tự âm thầm tắt proxy. **Safe** có thể chuyển sang trực tiếp sau số lần lỗi chẩn đoán liên tiếp đã đặt, nên một phần lưu lượng có thể không qua proxy. Kết quả chẩn đoán không xác định không được tính là hồi phục. TCP chỉ chứng minh có thể kết nối cổng; HTTP gửi yêu cầu thật qua proxy đến URL kiểm thử HTTP bạn đặt. Cả hai đều không bảo đảm mọi trang hoặc ứng dụng hoạt động.

## Khôi phục và gỡ cài đặt

Bản sao lưu proxy thủ công ban đầu là `state/proxy-before-install.json` trong thư mục cài đặt. Nâng cấp giữ bản này và quy tắc của bạn, không tạo bản “ban đầu” mới. Khi đổi cấu hình, tệp hợp lệ trước đó được giữ lại. Hãy giữ các tệp cục bộ này riêng tư.

Nếu đã cài, mở EXE mới và chọn **Settings → Advanced operations → Repair installation / Upgrade**. Không gỡ trước hoặc ghi đè cấu hình cá nhân bằng mặc định của kho mã. Xem [chuyển đổi cấu hình](docs/CONFIG_MIGRATION.md).

Dùng **Restore original configuration**, **Settings → Advanced operations → Uninstall** hoặc danh sách ứng dụng đã cài của Windows. Khôi phục/gỡ cài đặt so sánh giá trị hiện tại với bản gốc và giá trị cuối do công cụ ghi. Thay đổi bên ngoài về sau tạo xung đột thay vì bị ghi đè. Buộc khôi phục là lựa chọn rõ ràng; khi gỡ cũng có thể giữ proxy hiện tại. Chỉ xóa tác vụ/mục khởi động thuộc ứng dụng và tệp sản phẩm đã xác minh, bảo vệ tệp không liên quan hoặc đã được người dùng sửa. Chế độ trực tiếp vẫn giữ bản sao lưu gốc.

## Bảo mật và quyền riêng tư

- SSID, cấu hình proxy, trạng thái và nhật ký được xử lý cục bộ; không cần tài khoản đám mây hoặc dịch vụ phân tích.
- Ứng dụng không thu thập mật khẩu Wi-Fi. Chẩn đoán tùy chọn kết nối tới proxy đã chọn và, ở chế độ HTTP, URL bạn cấu hình.
- Bản sao lưu gốc được giữ. Cài đặt và quản lý tác vụ tôn trọng danh tính cùng kiểm tra quyền người dùng hiện tại.
- Công cụ quản lý **proxy thủ công** của người dùng Windows hiện tại, không đổi DNS, tuyến mạng hoặc quy tắc tường lửa.
- Nhật ký/chẩn đoán có thể chứa định danh mạng. Xem lại và ẩn thông tin riêng trước khi chia sẻ.

Báo vấn đề bảo mật theo [SECURITY.md](SECURITY.md).

## Câu hỏi thường gặp

**Làm sao tự chuyển proxy theo Wi-Fi trên Windows 11?** Đặt cổng proxy gateway, thêm SSID cho kết nối trực tiếp và bật chuyển tự động. Watcher đánh giá thay đổi Wi-Fi ổn định và áp dụng proxy thủ công cho người dùng hiện tại.

**Làm sao dùng gateway điểm phát Android làm proxy Windows?** Chạy dịch vụ proxy riêng trên điện thoại, cho phép thiết bị chia sẻ mạng truy cập và đặt cổng lắng nghe. Gateway được lấy từ giao diện Wi-Fi hiện tại. Nếu không kết nối được, kiểm tra dịch vụ và tường lửa điện thoại.

**WiFi Proxy Pilot có VPN không?** Không. Bạn cung cấp dịch vụ proxy. Ứng dụng dùng proxy riêng hoặc bỏ qua thiết lập Windows có thể hoạt động khác.

**Vì sao proxy bật nhưng không vào internet?** Gateway có thể không chạy proxy, cổng sai, dịch vụ dừng hoặc đích truy cập lỗi. Kiểm tra TCP/HTTP riêng. Tạm dừng giữ thiết lập, Trực tiếp tắt proxy thủ công. PAC vẫn có thể ảnh hưởng lưu lượng.

**Làm sao bỏ qua proxy ở một số mạng Wi-Fi?** Thêm SSID đầy đủ vào Wi-Fi Rules rồi lưu/áp dụng. Mọi quy tắc đều sửa và xóa được; danh sách rỗng hợp lệ.

**Làm sao khôi phục thiết lập proxy Windows?** Chọn khôi phục cấu hình ban đầu và xem xung đột do thay đổi bên ngoài. Trực tiếp chỉ tắt proxy thủ công, không trả lại máy chủ và danh sách bỏ qua ban đầu.

**Đóng cửa sổ thì ứng dụng còn chạy không?** Có. X mặc định ẩn vào khay. Thoát GUI cũng không dừng watcher độc lập. Dùng Tạm dừng hoặc Khôi phục để đổi quản lý nền.

**Vì sao không đọc được mạng hiện tại?** Quyền WLAN/vị trí, chính sách tổ chức, thiếu tuyến mạng, watcher dừng hoặc heartbeat cũ có thể gây ra vấn đề. UI hiển thị lý do và quan sát hợp lệ cuối cùng, không coi dữ liệu cũ là hiện tại.

**Đã kiểm thử những gì?** Xem [kết quả v3.2](docs/TEST_RESULTS_V3_2.md), [bằng chứng hiệu năng](docs/PERFORMANCE_V3_2.md), [danh sách kiểm tra release](docs/RELEASE_CHECKLIST.md). Kiểm thử cô lập không phải nghiệm thu mạng/cài đặt thật; mục tiêu hiệu năng không phải kết quả đo.

## Star History

Nếu WiFi Proxy Pilot giúp công việc thuận tiện hơn, hãy cân nhắc tặng dự án một Star.

<a href="https://star-history.com/#jeffxuu/WiFiProxyPilot&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
    <img alt="WiFi Proxy Pilot Star History" src="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
  </picture>
</a>

SVG trực tiếp chính thức dùng dữ liệu GitHub thật của kho mã công khai này. Số Star được xác minh ngày 2026-10-14 là 0, nên lịch sử rỗng là điều bình thường. Khi kiểm tra, URL ảnh cho cả giao diện sáng và tối đều trả về HTTP 200. Không bịa Star hay tăng trưởng. Xem [hướng dẫn nhúng chính thức](https://www.star-history.com/blog/how-to-use-github-star-history/).

## Đóng góp và lộ trình

Hoan nghênh Issues và Pull Requests từ người có quyền truy cập. Ghi rõ build, hành vi mong đợi/thực tế và bằng chứng đã ẩn thông tin riêng. [CONTRIBUTING.md](CONTRIBUTING.md) hướng dẫn build Windows và quy trình review. Không đính kèm cấu hình cá nhân, bản sao lưu proxy, thông tin xác thực hoặc nhật ký chưa biên tập.

Kế hoạch gồm nghiệm thu nâng cấp/đăng nhập/ngủ/gỡ trong môi trường thật, kiểm tra WPF còn lại về khả năng tiếp cận và bố cục, cải thiện tốc độ khởi động và bản địa hóa UI. Đây là kế hoạch, chưa phải tính năng đã phát hành. Tự động cập nhật chưa được triển khai.

Build bằng SDK trong `global.json` và Windows PowerShell:

```powershell
powershell.exe -NoProfile -File tests\Run-Tests.ps1 -ResultPath artifacts\engine-results.json
powershell.exe -NoProfile -File release\Build.ps1
```

Build tạo EXE tự chứa `win-x64`, không cài hoặc đổi proxy của máy đang build. Các định danh cài đặt, registry, mutex và tác vụ `WiFiProxySwitcher` hiện có được giữ để tương thích.

## Giấy phép

Mã nguồn dự án được cấp phép [MIT](LICENSE). Tài liệu/tài sản bên thứ ba giữ điều khoản riêng; xem [thông báo bên thứ ba](docs/THIRD_PARTY_NOTICES.md). Phông hệ thống Windows được sử dụng nhưng không phân phối lại.
