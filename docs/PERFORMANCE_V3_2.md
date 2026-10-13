# v3.2 macOS-inspired preview performance

2026-10-14. This is an early visual checkpoint. Startup budget is **not passed**.

Development device: Windows 11 Enterprise 10.0.26200, Intel Core Ultra 7 155H, 22 logical processors, 15.465 GiB RAM. SDK 8.0.425 / self-contained runtime 8.0.31. Defender/security software was not disabled. Network/configuration were isolated fixtures; no real proxy/task writes.

## Recorded samples

One cache-cold attempt and three warm attempts used tools/Measure-Startup.ps1. New native/payload directories do not imply OS-cold caches or reboot-cold timing. Raw stage records remain in artifacts/perf-macos-v32-fixed; redacted numeric evidence is in [evidence/v32-preview-performance.json](evidence/v32-preview-performance.json).

| Sample | Visible ms | First WPF content render ms | Cache | Result |
| --- | ---: | ---: | --- | --- |
| Cache-cold | 3963.73 | 4176.44 | New | Payload ready 4603.33 ms |
| Warm 1 | 1545.56 | 1706.42 | Hit, full verification 123.55 ms | Valid startup; tray next-frame timing incomplete |
| Warm 2 | 1611.70 | 1751.59 | Hit, full verification 101.09 ms | Valid startup |
| Warm 3 | 2130.84 | 2292.79 | Verification access denied | UI rendered; payload initialization failed safely. Not a passing startup sample |

Two successful warm content-render observations are approximately 1.71–1.75 s. Load was not controlled, so no rigorous A/B percentage is claimed. No claim is made that the 1.2 s target is met.

Resident window restoration measured 13.57/40.50/75.50 ms through layout; two next-render callbacks were 18.76/85.77 ms. The missing next-render observation is retained as missing. This small incomplete sample supports responsive restoration, not a promise or formal improvement claim. Representative isolated status reading in the WPF interaction run was 10.56 ms; it is not a real WLAN/registry benchmark.

## Problems and changes

An earlier cold attempt aborted because metric-file reading contended with atomic replacement, interrupting a diagnostic write before PayloadReady. Metric I/O now cannot throw into cache preparation, and the measurement reader shares deletion. The later warm-3 Access denied is a separate safe cache refusal; resource verification is still required and was not skipped. The helper now saves EXE hash metadata before sampling so a later failure does not lose binary identity. The old aborted run did not save its EXE SHA256; this limitation is explicit, and the old numbers do not certify the final EXE.

After discovering startup regression, the tray icon was changed from Shell extraction of the large single-file EXE to the project's AppIcons geometric drawing. Theme/XAML/page phase instrumentation was added. One diagnostic phase observation showed theme load 37.17 ms, first Window XAML initialization 1041.89 ms and first page creation 26.36 ms. It included fresh binary/native loading and is not a new warm benchmark. Window construction/first WPF styling/font/chrome initialization remain the principal measured UI investigation area. Removing unused styles, font fallback investigation and native-handle/tray phase measurements follow design confirmation.

Noncurrent pages are lazy; state, configuration and cache run off Dispatcher; polling does not parse logs; retained pages are reused; animations only affect opacity and honor reduced motion. No blur shaders, layered glow, continuous glass reflections, trimming or skipped SHA verification are used.

## Release gate

The final preview EXE hash is in release/dist/SHA256.txt. Its current build is not performance-certified by the older observations above. After the approved design and optimization, rerun one cold/three warm samples on this device, preserve metadata/failed rows and record UI interaction latency and idle CPU. The Beta is not performance-certified. Stable release remains gated on resolving startup latency and cache refusal; actual samples and failed rows are preserved.
