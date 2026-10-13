> **Documentation version: v3.2.0-beta.1.** This translated guide describes the older release. Current UI and installer documentation: [English](README.md), [简体中文](README.zh-CN.md), [v3.3 Setup EXE](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.3.0-beta.1/WiFiProxyPilot-Setup-x64.exe). The application UI supports en-US and zh-CN; README translation does not imply another UI language.

<div align="center">
  <h1>WiFi Proxy Pilot</h1>
  <h3>Intelligenter WLAN-Proxywechsel für Windows</h3>
  <p>Ein leichtes, modernes Windows-Werkzeug, das den Systemproxy anhand von WLAN-SSIDs, Gateway-Adressen und eigenen Regeln automatisch umschaltet.</p>

  ![Windows 11](https://img.shields.io/badge/Windows-11-0078D4)
  ![.NET 8](https://img.shields.io/badge/.NET-8-512BD4)
  ![WPF](https://img.shields.io/badge/UI-WPF-6557E8)
  [![Release](https://img.shields.io/github/v/release/jeffxuu/WiFiProxyPilot?include_prereleases)](https://github.com/jeffxuu/WiFiProxyPilot/releases)
  [![MIT-Lizenz](https://img.shields.io/badge/License-MIT-green)](LICENSE)
  [![GitHub Stars](https://img.shields.io/github/stars/jeffxuu/WiFiProxyPilot?style=flat)](https://github.com/jeffxuu/WiFiProxyPilot/stargazers)
</div>

**[English](README.md) · [简体中文](README.zh-CN.md) · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md) · [Español](README.es.md) · [Français](README.fr.md) · [Deutsch](README.de.md) · [Português (Brasil)](README.pt-BR.md) · [Русский](README.ru.md) · [Tiếng Việt](README.vi.md)**

**Ihr WLAN wechselt. Ihr Proxy folgt.** Nutzen Sie in gewöhnlichen WLANs einen Proxy auf dem Gateway und verbinden Sie sich in ausgewählten Netzwerken direkt. Die Verwaltung erfolgt über eine moderne WPF-Oberfläche oder das Infobereichsymbol.

> **v3.2.0-beta.1 ist eine Beta/Prerelease.** Die Aufnahmen zeigen die tatsächliche WPF-Anwendung mit simulierten Netzwerkdaten. Tests mit echten Netzwerken, Anmeldung/Ruhezustand, Installation und Deinstallation stehen getrennt von isolierten Regressionstests. Die Oberfläche ist derzeit ausschließlich auf vereinfachtem Chinesisch verfügbar; übersetzte READMEs bedeuten keine lokalisierte Oberfläche. Das Repository ist Public.

## Screenshots

![Übersicht — echte WPF-Anwendung, simuliertes Netzwerk](docs/images/dashboard.png)

| WLAN-Regeln | Einstellungen |
| --- | --- |
| ![Vorschau der WLAN-Regeln](docs/images/rules.png) | ![Vorschau der Einstellungen](docs/images/settings.png) |

![Infobereichmenü — echte App, simuliertes Netzwerk](docs/images/tray.png)

<details>
<summary>Vorschau des dunklen Designs</summary>

![Dunkles Design — früheres WPF-Übersichtslayout](docs/images/dashboard-dark.png)

</details>

Alle Bilder stammen aus der realen Anwendung in einer isolierten Testumgebung und **belegen keine aktive Proxyverbindung**. Die dunkle Aufnahme zeigt ein älteres Übersichtslayout. Auch das gezeigte Infobereichmenü wurde mit der isolierten App-Testumgebung und simulierten Netzwerkdaten aufgenommen.

## Funktionen

- Ermittelt das verbundene WLAN und gleicht vollständige SSIDs ohne Beachtung der Groß-/Kleinschreibung ab.
- Liest das **IPv4-Standardgateway** der aktuellen physischen WLAN-Schnittstelle und verwendet den konfigurierten Proxyport, standardmäßig `7890`.
- Schaltet für ausgewählte WLANs auf Direktverbindung. Neue Installationen enthalten **keine vorgegebenen WLAN-Regeln**; alle Regeln lassen sich bearbeiten und löschen.
- Bietet eine von macOS inspirierte WPF-Oberfläche, helle/dunkle Designs und ein Infobereichsymbol mit unabhängigem Hintergrund-Watcher.
- Unterscheidet automatische Verwaltung, den manuellen Windows-Proxy und optionale TCP-/HTTP-Diagnose. Ein aktivierter Proxy beweist keinen Internetzugang.
- Speichert atomar und unterscheidet „gespeichert“ von „durch den Watcher angewendet“.
- Bewahrt die ursprüngliche Proxysicherung und schützt spätere Änderungen durch Sie oder andere Programme.
- Stellt den Quellcode unter MIT zur Prüfung und Mitarbeit bereit.

## Download und Installation

**[v3.2.0-beta.1 herunterladen — Beta/Prerelease](https://github.com/jeffxuu/WiFiProxyPilot/releases/tag/v3.2.0-beta.1)** · **[EXE](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/WiFiProxySwitcher.exe)** · **[ZIP](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/WiFiProxySwitcher.zip)** · **[SHA256](https://github.com/jeffxuu/WiFiProxyPilot/releases/download/v3.2.0-beta.1/SHA256.txt)** · **[Buildartefakte](https://github.com/jeffxuu/WiFiProxyPilot/actions/workflows/build.yml)**

v3.2.0-beta.1 wird als **Beta/Prerelease** angeboten und ist noch keine vollständig stabile finale Version. Prüfen Sie vor der Installation Version, Versionshinweise und die Prüfsummen in `SHA256.txt`. Das Release-Badge berücksichtigt auch Prereleases. GitHub-Buildartefakte laufen ab; nutzen Sie für diese Version die oben verlinkten Release-Dateien.

Zielplattform ist **Windows 11 x64** mit Windows PowerShell 5.1, WLAN-Dienst und Windows Script Host. Die eigenständige EXE benötigt keine zusätzliche Installation von .NET, Python, Node.js oder WebView2. Eine weitergehende Windows-Kompatibilität wird nicht behauptet. Organisationsrichtlinien können WLAN-Daten, Proxyeinstellungen oder geplante Aufgaben einschränken. Die aktuellen Builds sind unsigniert; lassen Sie Windows-Schutzfunktionen aktiviert.

Laden Sie die EXE herunter oder entpacken Sie das ZIP und vergleichen Sie den Hash mit `SHA256.txt`:

```powershell
Get-FileHash .\WiFiProxySwitcher.exe -Algorithm SHA256
```

Aus Kompatibilitätsgründen heißt die Datei weiterhin `WiFiProxySwitcher.exe`. Starten Sie sie mit Ihrem gewöhnlichen interaktiven Windows-Benutzerkonto. Das Öffnen des v3.2-Fensters aktiviert die Proxyverwaltung noch nicht. Installieren Sie für Ihr Alltagskonto nicht über das Konto eines anderen Administrators.

## Schnellstart und Erstkonfiguration

1. **Herunterladen:** Version und Hash prüfen.
2. **Konfigurieren:** Den Port eines vorhandenen Proxys auf Ihrem WLAN-Gateway eintragen und WLAN-Namen für Direktverbindungen hinzufügen.
3. **Automatischen Wechsel aktivieren:** Zuvor die Einstellungen prüfen, die die Anwendung verwalten soll.

**Auf dem Gateway muss tatsächlich ein Proxydienst laufen. WiFi Proxy Pilot liefert weder Proxyserver noch VPN-Knoten.** Bei einem Android-Hotspot wird das aktuelle IPv4-Gateway ermittelt. Tragen Sie den Port Ihrer Proxy-App ein und erlauben Sie Verbindungen vom verbundenen Windows-Gerät. Ein Hotspot allein ist kein Proxy.

## Funktionsablauf

```text
WLAN verbunden → Stabile SSID-/Schnittstellendaten lesen → Eigene Regeln prüfen
  ├─ Direktregel passt → Manuellen Windows-Proxy deaktivieren
  └─ Keine Direktregel → IPv4-Gateway des aktuellen WLANs ermitteln
                        → Gateway + konfigurierten Port anwenden
```

Vor jeder Änderung überprüft der Watcher das aktuelle Netzwerk, damit nach einem WLAN-Wechsel kein altes Gateway übernommen wird. Bei unbekannter SSID, fehlenden Routen oder mehrdeutigen Schnittstellen bleiben bestehende Einstellungen erhalten; der Grund wird angezeigt und die Prüfung wiederholt. Eine bestätigte Trennung deaktiviert den manuellen Proxy. PAC und automatische Erkennung behalten ihre Werte und können weiterhin das Routing beeinflussen.

## WLAN-Regeln verwalten

Unter **Wi-Fi Rules** können Sie Regeln hinzufügen, umbenennen und löschen oder das zuverlässig erkannte aktuelle Netzwerk übernehmen. Leere Listen sind erlaubt. Es gilt der vollständige Name mit `OrdinalIgnoreCase`, keine Präfix- oder Teilzeichenfolgensuche. Zulässige Leerzeichen bleiben erhalten. Namen müssen 1–32 UTF-8-Bytes lang sein und dürfen keine Steuerzeichen enthalten.

**Save and Apply** prüft gleichzeitige Änderungen und speichert atomar. „Gespeichert“ bestätigt den Dateischreibvorgang. „Angewendet“ setzt einen aktuellen, kompatiblen Watcher-Heartbeat derselben Revision und ein stabiles Netzwerk voraus. Andernfalls zeigt die Anwendung die ausstehende Hintergrundanwendung an. Abbrechen verwirft ungespeicherte Änderungen; gelöschte Regeln kehren nicht automatisch zurück.

## Infobereich und Proxymodi

| Aktion | Wirkung |
| --- | --- |
| Automatischen Wechsel aktivieren | Netzwerk erneut erfassen und manuellen Proxy anhand der Regeln verwalten |
| Pause | Automatische Proxyänderungen stoppen; die aktuelle Einstellung bleibt bestehen |
| Direktverbindung | Verwaltung pausieren und nur den manuellen Windows-Proxy deaktivieren |
| Jetzt prüfen | Neue Netzwerkerfassung und stabile Auswertung anfordern |
| Fenster schließen | Standardmäßig in den Infobereich ausblenden; der Watcher läuft weiter |
| Oberfläche beenden | GUI und Infobereichsymbol schließen; der unabhängige Watcher läuft weiter |
| Ursprüngliche Konfiguration wiederherstellen | Verwaltung stoppen und Sicherung unter Konfliktprüfung wiederherstellen |

Pause und Direktmodus bleiben über GUI-Neustarts und Anmeldungen hinweg erhalten. Der Start des Watchers bei Anmeldung und der Start des Infobereichsymbols sind getrennte Einstellungen.

**Strict** wendet die ausgewählte Regel an und meldet Diagnosefehler, ohne den Proxy stillschweigend zu deaktivieren. **Safe** kann nach der festgelegten Anzahl aufeinanderfolgender Diagnosefehler zur Direktverbindung wechseln; dabei kann Verkehr den Proxy umgehen. Unbekannte Diagnoseergebnisse gelten nicht als Erholung. TCP prüft nur, ob ein Port erreichbar ist. HTTP sendet eine echte Proxyanfrage an die eingestellte HTTP-Test-URL. Beides garantiert nicht die Funktion jeder Website oder Anwendung.

## Wiederherstellung und Deinstallation

Die ursprüngliche Sicherung des manuellen Proxys liegt unter `state/proxy-before-install.json` im Installationsverzeichnis. Upgrades erhalten diese Sicherung und Ihre Regeln; sie erzeugen keine neue „ursprüngliche“ Sicherung. Bei Konfigurationsänderungen bleibt die vorherige gültige Datei erhalten. Behandeln Sie diese lokalen Dateien vertraulich.

Bei vorhandener Installation öffnen Sie die neue EXE und wählen **Settings → Advanced operations → Repair installation / Upgrade**. Deinstallieren Sie nicht zuerst und überschreiben Sie Ihre Konfiguration nicht mit Repository-Standardwerten. Siehe [Konfigurationsmigration](docs/CONFIG_MIGRATION.md).

Nutzen Sie **Restore original configuration**, **Settings → Advanced operations → Uninstall** oder die installierten Apps von Windows. Wiederherstellung und Deinstallation vergleichen aktuelle Werte mit der ursprünglichen Sicherung und den zuletzt durch das Werkzeug gesetzten Werten. Spätere externe Änderungen lösen einen Konflikt aus und werden nicht überschrieben. Eine erzwungene Wiederherstellung ist eine ausdrückliche Entscheidung; bei der Deinstallation können Sie den aktuellen Proxy auch behalten. Entfernt werden nur eigene Aufgaben/Autostarteinträge und überprüfte Produktdateien; fremde oder vom Benutzer geänderte Dateien bleiben geschützt. Der Direktmodus erhält die ursprüngliche Sicherung.

## Sicherheit und Datenschutz

- SSIDs, Konfiguration, Zustand und Protokolle werden lokal verarbeitet; weder Cloudkonto noch Analysedienst sind erforderlich.
- Die Anwendung erfasst keine WLAN-Passwörter. Optionale Diagnosen verbinden sich mit dem ausgewählten Proxy und im HTTP-Modus mit Ihrer Test-URL.
- Die ursprüngliche Proxysicherung bleibt erhalten. Installation und Aufgabenverwaltung beachten Benutzeridentität und Berechtigungen.
- Verwaltet wird der **manuelle Proxy** des aktuellen Windows-Benutzers. DNS, Routen und Firewallregeln werden nicht geändert.
- Protokolle und Diagnosen können Netzwerkkennungen enthalten. Prüfen und anonymisieren Sie sie vor dem Teilen.

Sicherheitsprobleme bitte gemäß [SECURITY.md](SECURITY.md) melden.

## Häufige Fragen

**Wie schalte ich unter Windows 11 den Proxy automatisch nach WLAN um?** Stellen Sie den Gateway-Proxyport ein, ergänzen Sie SSIDs für Direktverbindungen und aktivieren Sie den automatischen Wechsel. Der Watcher wertet stabile WLAN-Wechsel aus und setzt den manuellen Proxy für den aktuellen Benutzer.

**Wie verwende ich einen Android-Hotspot als Windows-Proxy?** Betreiben Sie auf dem Telefon einen separaten Proxydienst, erlauben Sie den Zugriff verbundener Geräte und tragen Sie dessen Port ein. Das Gateway wird aus der aktuellen WLAN-Schnittstelle ermittelt. Prüfen Sie bei Nichterreichbarkeit Dienst und Firewall auf dem Telefon.

**Enthält WiFi Proxy Pilot ein VPN?** Nein. Sie stellen den Proxydienst bereit. Anwendungen mit eigener Proxykonfiguration oder ohne Beachtung der Windows-Einstellungen können anders reagieren.

**Warum ist der Proxy aktiv, aber das Internet nicht erreichbar?** Auf dem Gateway läuft möglicherweise kein Proxy, Port oder Dienst ist falsch beziehungsweise gestoppt, oder das Ziel schlägt fehl. Prüfen Sie TCP-/HTTP-Diagnosen getrennt. Pause erhält die Einstellung; Direkt deaktiviert den manuellen Proxy. PAC kann weiterhin Verkehr beeinflussen.

**Wie umgehe ich den Proxy in bestimmten WLANs?** Fügen Sie deren vollständige SSIDs unter Wi-Fi Rules hinzu und speichern/wenden Sie an. Alle Regeln sind bearbeitbar und löschbar; eine leere Liste ist gültig.

**Wie stelle ich Windows-Proxyeinstellungen wieder her?** Wählen Sie die Wiederherstellung und prüfen Sie mögliche Konflikte mit externen Änderungen. Direkt deaktiviert nur den manuellen Proxy und stellt weder den ursprünglichen Server noch die Umgehungsliste wieder her.

**Läuft die Anwendung nach dem Schließen weiter?** Ja. X blendet sie normalerweise in den Infobereich aus. Auch das Beenden der GUI lässt den unabhängigen Watcher laufen. Verwenden Sie Pause oder Wiederherstellung, um die Hintergrundverwaltung zu ändern.

**Warum wird das aktuelle Netzwerk nicht erkannt?** WLAN-/Standortberechtigungen, Organisationsrichtlinien, fehlende Routen, ein gestoppter Watcher oder ein alter Heartbeat können zuverlässige Daten verhindern. Die Oberfläche zeigt Ursache und letzte gültige Beobachtung, statt alte Daten als aktuell auszugeben.

**Was wurde getestet?** Siehe [v3.2-Testergebnisse](docs/TEST_RESULTS_V3_2.md), [Leistungsnachweise](docs/PERFORMANCE_V3_2.md) und [Release-Checkliste](docs/RELEASE_CHECKLIST.md). Isolierte Tests ersetzen keine Abnahme mit echtem Netzwerk oder Installation; Leistungsziele sind keine Messwerte.

## Star History

Wenn WiFi Proxy Pilot Ihren Arbeitsalltag erleichtert, unterstützen Sie das Projekt gerne mit einem Stern.

<a href="https://star-history.com/#jeffxuu/WiFiProxyPilot&Date">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date&theme=dark" />
    <source media="(prefers-color-scheme: light)" srcset="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
    <img alt="WiFi Proxy Pilot Star History" src="https://api.star-history.com/svg?repos=jeffxuu/WiFiProxyPilot&type=Date" />
  </picture>
</a>

Das offizielle Live-SVG verwendet die tatsächlichen GitHub-Daten dieses öffentlichen Repositorys. Am 2026-10-14 wurden 0 Sterne bestätigt; ein leerer Verlauf ist daher zu erwarten. Beide Bild-URLs für das helle und dunkle Design antworteten bei der Prüfung mit HTTP 200. Sterne und Wachstum werden nicht erfunden. Siehe [offizielle Einbettungsanleitung](https://www.star-history.com/blog/how-to-use-github-star-history/).

## Mitarbeit und Planung

Issues und Pull Requests von Personen mit Repositoryzugriff sind willkommen. Beschreiben Sie Build, erwartetes/tatsächliches Verhalten und bereinigte Nachweise. [CONTRIBUTING.md](CONTRIBUTING.md) erläutert Windows-Build und Review. Teilen Sie keine persönlichen Konfigurationen, Proxysicherungen, Zugangsdaten oder unbearbeiteten Protokolle.

Geplant sind echte Upgrade-/Anmelde-/Ruhezustands-/Deinstallationsabnahmen, weitere WPF-Prüfungen zu Barrierefreiheit und Layout, schnellerer Start und UI-Lokalisierung. Dies sind Vorhaben, keine ausgelieferten Funktionen. Automatische Updates sind nicht implementiert.

Bauen Sie mit dem SDK aus `global.json` und Windows PowerShell:

```powershell
powershell.exe -NoProfile -File tests\Run-Tests.ps1 -ResultPath artifacts\engine-results.json
powershell.exe -NoProfile -File release\Build.ps1
```

Der Build erzeugt eine eigenständige `win-x64`-EXE, ohne sie zu installieren oder den Proxy des Rechners zu verändern. Die bestehenden Installations-, Registry-, Mutex- und Aufgabenkennungen `WiFiProxySwitcher` bleiben aus Kompatibilitätsgründen erhalten.

## Lizenz

Der Projektquellcode steht unter [MIT](LICENSE). Drittmaterial behält seine eigenen Bedingungen; siehe [Hinweise zu Drittmaterial](docs/THIRD_PARTY_NOTICES.md). Windows-Systemschriften werden genutzt, aber nicht mitgeliefert.
