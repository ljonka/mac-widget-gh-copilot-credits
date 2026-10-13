# Copilot Credits – macOS Desktop

Kleines verschiebbares Desktop-Widget aus Swift/AppKit, ohne externe Bibliotheken.
Fragt alle **60 Sekunden** mit `gh api --hostname github.com /copilot_internal/user` die
verbleibenden Copilot-Credits ab. Funktioniert mit Business-/Enterprise-Konten,
sofern GitHub eine begrenzte `premium_interactions`-Quote zurückliefert.
Unter dem Tagesfortschritt stehen verbrauchte / insgesamt verfügbare Monats-Credits
und der Reset-Zeitpunkt. Die API liefert Credits, keine Tokenzahlen.

## Lokal installieren

Voraussetzungen: macOS 13+, Xcode/Swift und angemeldete GitHub CLI (`gh auth login`).

```sh
bash scripts/install.sh
```

Führt Tests und Live-Abfrage aus, installiert nach `~/Applications/CopilotCredits.app`,
startet das Widget und richtet Autostart bei Anmeldung ein. Erneutes Ausführen aktualisiert es.
Verschieben durch Ziehen; Menüleistensymbol für Aktualisieren, Position zurücksetzen und Beenden.

## Berechnung

- Tage bis zum Reset **einschließlich heute**, gerechnet in UTC (GitHub setzt um 00:00 UTC zurück).
- Tagesbudget = verbleibende Credits **beim ersten Abruf des Tages** / verbleibende Tage.
- Tagesverbrauch = Credits beim ersten Abruf − aktuell verbleibende Credits.
- Anzeige = Tagesverbrauch / festes Tagesbudget × 100; darf über 100 % steigen.
- **Grün ≤ 50 %**, **Gelb > 50 % und < 80 %**, **Rot ≥ 80 %**; aufgebrauchte Quote ist rot.

GitHub liefert keine Tageshistorie über diesen Endpunkt. Beim ersten Start beginnt die
Messung bei 0 %; auch nach einem verpassten Tageswechsel zählt sie ab dem ersten Abruf.
Die Tagesbasis wird lokal gespeichert und überlebt Neustarts. Bei Fehlern wird die Anzeige
grau und zeigt die Fehlermeldung. Ein nativer WidgetKit-Zeitplan garantiert keinen Minutentakt;
deshalb läuft dies als kleines Desktop-Fenster. Während Mac-Ruhezustand erfolgen keine Abrufe.
Der GitHub-Endpunkt ist intern und kann sich ändern.

## Tests / entfernen

```sh
swift test
bash scripts/uninstall.sh
```

Tests decken Dezimal-Credits, Tagesbudget, Farbgrenzen, Tages-/Monatswechsel,
Schaltjahr, leere Quote, ungültige Daten und gespeicherte Tagesbasis ab.
