# Copilot Credits – macOS Desktop

Kleines verschiebbares Desktop-Widget aus Swift/AppKit, ohne externe Bibliotheken.
Zeigt, ob dein bisheriger Copilot-Verbrauch bei gleichem Tagesdurchschnitt
bis zum Monatsende innerhalb des enthaltenen Credit-Budgets bleibt.
Fragt alle **60 Sekunden** mit `gh api --hostname github.com /copilot_internal/user` die
verbleibenden Copilot-Credits ab. Funktioniert mit Business-/Enterprise-Konten,
sofern GitHub eine begrenzte `premium_interactions`-Quote zurückliefert.
Zeigt Monatsverbrauch, Tagesdurchschnitt, Abweichung von einer Gleichverteilung,
Hochrechnung zum Monatsende und Reset-Zeitpunkt. Die API liefert Credits, keine Tokenzahlen.

## Voraussetzungen

- macOS 13 oder neuer.
- Swift 5.9 oder neuer, z. B. mit Xcode 15+ und ausgewählter Xcode-Toolchain.
- [GitHub CLI](https://cli.github.com/) (`brew install gh`) und Anmeldung bei `github.com`.
- Copilot-Konto mit begrenzter Monatsquote; Business/Enterprise wird über dieselbe API abgefragt.

Die Oberfläche ist deutsch. Der Build erfolgt lokal für die Architektur des Macs.

## Lokal installieren

```sh
git clone https://github.com/ljonka/mac-widget-gh-copilot-credits.git
cd mac-widget-gh-copilot-credits
gh auth login --hostname github.com
bash scripts/install.sh
```

Führt Tests und Live-Abfrage aus, installiert nach `~/Applications/CopilotCredits.app`,
startet das Widget und richtet Autostart bei Anmeldung ein. Erneutes Ausführen aktualisiert es.
Verschieben durch Ziehen an der Kopfzeile **„Copilot · Monat“**;
Menüleistensymbol für Aktualisieren, Position zurücksetzen und Beenden.
Das Desktop-Fenster liegt über nativen Desktop-Widgets und unter normalen App-Fenstern.
Es wird über die App gestartet und erscheint nicht in der macOS-Widget-Auswahl.

## Berechnung

- Monatsverbrauch = Gesamtbudget − verbleibende Credits.
- Große Prozentanzeige = Monatsverbrauch / Gesamtbudget × 100.
- Soll-Tagesverbrauch = Gesamtbudget / Kalendertage des aktuellen Monats.
- Ist-Tagesdurchschnitt = Monatsverbrauch / vergangene Kalendertage **einschließlich heute**.
- Abweichung = (Ist-Tagesdurchschnitt / Soll-Tagesverbrauch − 1) × 100.
  **0 % = Punktlandung**, **−20 % = 20 % unter Soll**, **+20 % = 20 % über Soll**.
- Prognose = Ist-Tagesdurchschnitt × Kalendertage des Monats.
  Grün, wenn das Budget reicht; rot, wenn die Hochrechnung das Gesamtbudget überschreitet.
- Monatsanzeige: **Grün ≤ 50 %**, **Gelb > 50 % und < 80 %**, **Rot ≥ 80 %**.

Alle Tage werden in UTC gerechnet (GitHub setzt am Monatsersten um 00:00 UTC zurück).
Der heutige Tag zählt als ganzer Tag; die Prognose basiert auf gleichbleibendem
bisherigen Tagesdurchschnitt und verändert sich mit dem Verbrauch. Die Monatsrechnung
funktioniert sofort nach dem Start, auch ohne vorherige Messungen.
Bei Fehlern wird die Anzeige grau und zeigt die Fehlermeldung.
Ein nativer WidgetKit-Zeitplan garantiert keinen Minutentakt;
deshalb läuft dies als kleines Desktop-Fenster. Während Mac-Ruhezustand erfolgen keine Abrufe.
Der GitHub-Endpunkt ist intern und kann sich ändern.

## Daten und Grenzen

Die App nutzt die bestehende Anmeldung der GitHub CLI. Sie speichert selbst keine Tokens
und verwendet keine zusätzlichen Dienste oder eigene Telemetrie. Abfragen gehen an GitHub.
Verbrauchsdaten werden nur im Arbeitsspeicher gehalten; die Fensterposition speichert macOS.

Die Anzeige bezieht sich auf die enthaltene Monatsquote `premium_interactions`, bevorzugt
mit dezimalgenauem `quota_remaining`. Zusätzlich abgerechneter Mehrverbrauch wird nicht
ausgewertet. Unterstützt wird der Reset am ersten Tag des nächsten UTC-Monats.

## Entwicklung und Tests

```sh
swift test
swift build -c release
# Optionale Live-Abfrage mit deiner gh-Anmeldung:
swift run CopilotCredits --check
```

Tests decken Dezimal-Credits, Monatsverbrauch, Gleichverteilung, Über-/Unterverbrauch,
Prognose, Farbgrenzen, Tages-/Monatswechsel, Schaltjahr und ungültige Daten ab.
GitHub Actions führt Tests und Release-Build unter macOS aus; dafür sind keine Zugangsdaten nötig.

```text
Sources/CreditsCore/      API-Daten und Monatsberechnung
Sources/CopilotCredits/   gh-Abfrage, Desktop-Fenster und Menüleiste
Tests/CreditsCoreTests/   Berechnung und API-Decodierung
scripts/                 Lokale Installation und Deinstallation
```

## Fehlerbehebung

- **Anmeldung/API-Fehler:** `gh auth status --hostname github.com` und
  `swift run CopilotCredits --check` im Terminal ausführen.
- **Keine begrenzten Credits:** Das Konto muss eine begrenzte `premium_interactions`-Quote liefern.
- **Fenster nicht sichtbar:** Menüleistensymbol → **Widget zurücksetzen**.
- **Nach „Beenden“ erneut starten:** `open ~/Applications/CopilotCredits.app`.
- **Aktualisieren:** Im Projekt `git pull` und `bash scripts/install.sh` ausführen.

## Entfernen

```sh
bash scripts/uninstall.sh
```

Entfernt App und Autostart-Eintrag aus `~/Library/LaunchAgents`.

## Lizenz

[MIT](LICENSE) · Copyright © 2026 Leonid Verhovskij.
