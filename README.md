# Copilot Credits – macOS Desktop

Kleines verschiebbares Desktop-Widget aus Swift/AppKit, ohne externe Bibliotheken.
Fragt alle **60 Sekunden** mit `gh api --hostname github.com /copilot_internal/user` die
verbleibenden Copilot-Credits ab. Funktioniert mit Business-/Enterprise-Konten,
sofern GitHub eine begrenzte `premium_interactions`-Quote zurückliefert.
Zeigt Monatsverbrauch, Tagesdurchschnitt, Abweichung von einer Gleichverteilung,
Hochrechnung zum Monatsende und Reset-Zeitpunkt. Die API liefert Credits, keine Tokenzahlen.

## Lokal installieren

Voraussetzungen: macOS 13+, Xcode/Swift und angemeldete GitHub CLI (`gh auth login`).

```sh
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

## Tests / entfernen

```sh
swift test
bash scripts/uninstall.sh
```

Tests decken Dezimal-Credits, Monatsverbrauch, Gleichverteilung, Über-/Unterverbrauch,
Prognose, Farbgrenzen, Tages-/Monatswechsel, Schaltjahr und ungültige Daten ab.
