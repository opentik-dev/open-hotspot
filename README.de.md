# Open-HotSpot

[English](README.md) · [العربية](README.ar.md) · [简体中文](README.zh-CN.md) · [한국어](README.ko.md) · [Deutsch](README.de.md) · [日本語](README.ja.md)

Open-HotSpot ist ein lokales Captive-Portal- und Hotspot-Managementsystem für OpenWrt. Es basiert auf [openNDS](https://opennds.readthedocs.io/) als Portal- und Traffic-Engine und wird über LuCI verwaltet.

> **Status: Kandidat vor der Produktionsabnahme.** Die Implementierung und die automatisierten Tests sind weit fortgeschritten, aber die Gates für den echten Router sind noch nicht vollständig geschlossen. `1.2.0-r112` ist bis zum Abschluss der Feldergebnisse keine Produktionsbasis.

## Idee

Open-HotSpot hält Identität, Richtlinien, Abrechnung und Verwaltung lokal auf dem OpenWrt-Router. openNDS übernimmt Captive Portal und Traffic-Durchsetzung. RADIUS, Cloud-Dienste und eine externe Datenbank sind nicht erforderlich.

## Funktionen

| Funktion | Beschreibung |
|---|---|
| Konten | Lokale Benutzernamen und PINs |
| Geräte | Mehrere Geräte pro Konto, Lebenszyklus und sichere Neuzuordnung |
| Gutscheine | Einmalige, transaktionale Einlösung |
| Profile | Zeit-, Zeitraum-, Daten-, Raten- und Geräte-Limits |
| Quoten | Periodische kumulative Nutzung; neue Zugriffe werden bei Erschöpfung abgelehnt |
| Dashboard | Live-openNDS-Status zusammen mit SQLite-Historie |
| Verwaltung | Native LuCI- und RPC-Oberfläche |
| Portal | Lokal installierte arabische RTL- und englische Templates |

## Ablauf

```text
Client → openNDS-Portal → lokales FAS → Konto/PIN-Prüfung → SQLite
                         ↓
                 openNDS-Autorisierung und Traffic-Durchsetzung
                         ↓
                 BinAuth-Ereignis → SQLite-Abrechnung
                         ↓
                      LuCI / RPC
```

Die Grenze ist absichtlich: openNDS bleibt die Policy-Engine, Open-HotSpot besitzt Identität, Richtlinien, Abrechnung und Verwaltung. BinAuth ist ereignisgesteuert und ruft `ndsctl` nicht auf.

## Repository-Struktur

```text
starter-kit/   LuCI- und Laufzeitdateien für den Router
tools/         Build, Prüfung, Einrichtung, Diagnose und kontrollierte Bereitstellung
tests/         Python-Tests, Shell-Verträge und Integrationstests
docs/          Wahrheitsquelle, Architektur, Abnahme, Betrieb und Archiv
specs/         Anforderungen, Entscheidungen, Plan und Aufgaben
```

## Aktueller Kandidat

```text
Router:       Linksys EA8300
OpenWrt:      25.12.5
Target:       ipq40xx/generic
openNDS:      11.0.0
Open-HotSpot: 1.2.0-r112 — installierter Kandidat; Hardwareabnahme ausstehend
```

Die aktuelle Build- und Statusquelle ist [`docs/source-of-truth.md`](docs/source-of-truth.md). r60 mit openNDS 10.3.1-r3 bleibt die geschützte Rollback-Basis.

## Produktoberfläche

Die folgenden Bilder zeigen ausschließlich die Verwaltung und sind kein Nachweis für Feldabnahme oder Produktionsfreigabe.

| Dashboard | Profile |
|---|---|
| ![Open-HotSpot Dashboard](docs/screenshots/dashboard.png) | ![Open-HotSpot Profile](docs/screenshots/profiles.png) |
| Konten, Sitzungen, Quoten und Raten. | Zeit-, Daten-, Raten-, Zeitraum- und Geräte-Limits. |

| Konten | Geräte |
|---|---|
| ![Open-HotSpot Konten](docs/screenshots/accounts.png) | ![Open-HotSpot Geräte](docs/screenshots/devices.png) |
| Identität, Profil, Status und Ablauf. | Eigentümer, Lebenszyklus, Sitzungen und Neuzuordnung. |

| Portal-Templates |
|---|
| ![Open-HotSpot Portal-Templates](docs/screenshots/portal-templates.png) |
| Auswahl einer lokal installierten Sprache ohne Download von einer URL. |

## Erreicht und offen

| Bereich | Status |
|---|---|
| Datenbank, Quoten, Gutscheine und Domänenverträge | Lokal Tested |
| Portal → FAS → openNDS → BinAuth | Auf dem Zielpfad Verified |
| Zählerrichtung und native Quotenabschaltung | Pending Hardware Validation — T006 |
| Neustart, Wiederherstellung und Fehlerisolierung | Teilweise — T011/T086 |
| Wiederholbare Wiederherstellung nach unterbrochener Einrichtung | Offen — T052/T087 |
| Produktionsbasis | Bis T090 blockiert |

## Wo Beiträge gebraucht werden

- T006: Upload/Download-Richtung und native Quotenabschaltung mit einem echten Client messen.
- T011/T086: Neustart, Wiederherstellung, doppelte Callbacks und Fehlerisolierung auf dem Zielrouter prüfen.
- T052/T087: Unterbrochene Einrichtung und Wiederherstellung auf einem sauberen Ziel testen.
- T088/T090 und die Release-Abnahmematrix abschließen.
- Family Captive Boundary 1/2 implementieren und im Feld prüfen. Der aktuelle OP-203-Vertrag beweist nur kollisionsfreie Kennungen, nicht die Isolation von Daemon, FAS, Abrechnung oder nftables.

Bitte zuerst [`CONTRIBUTING.md`](CONTRIBUTING.md), [`Projektstatus`](docs/project-status.md) und [`Release-Gates`](docs/release-gates.md) lesen. Mock, Screenshot oder lokaler Vertragstest ist keine Hardwareabnahme.

## Lizenz

[GPL-2.0-or-later](LICENSE).
