# v3.3 startup measurement

The v3.2 measurements remain in [PERFORMANCE_V3_2.md](PERFORMANCE_V3_2.md): two successful warm WPF content renders at 1706.42 and 1751.59 ms, one cache-cold render at 4176.44 ms, and a separate access-denied cache failure. Those results are not reassigned to a newer binary.

The installed v3.3 distribution uses an ordinary self-contained runtime directory, avoiding the portable single-file runtime extraction cost. The application opens before loading its command payload. When a command is needed, an installer-owned engine directory is checked against the embedded SHA256 manifest in place, avoiding duplicate payload extraction while preserving full verification. Portable mode retains the verified content-addressed cache.

MainWindow uses the standard native Windows frame and Segoe UI. Pages are still retained and loaded lazily. ResourceManager translation lookup does not launch PowerShell. Actual measurements and any failing rows will be recorded after the final build; no target is declared achieved before measuring.

Run `tools/Measure-Startup.ps1 -Exe <built executable> -OutputDirectory <owned measurement directory>` to collect cache-cold and warm samples. The tool uses a clearly labelled fixture without Windows proxy/task/network changes. A new extraction directory is not an OS-cold or reboot-cold test. Caption/control interaction timing, initialized-window rendering and resident reopening are distinct measurements.
