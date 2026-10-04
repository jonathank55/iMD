# iText

Schlanker, minimalistischer und hochstabiler Text- & Markdown-Editor für macOS mit puristischem, leistenlosem Fensterdesign, nativer Menüleistensteuerung, anpassbarem Zeilenabstand und nativer Typst-PDF-Druckanbindung.

---

## Funktionen

- **Puristisches Fensterdesign:** Vollständiger Verzicht auf störende Fensterleisten. Der Schreibraum steht uneingeschränkt im Zentrum. Sämtliche Befehle sind über die native macOS-Menüleiste erreichbar.
- **Sicherheitsabfrage bei ungesicherten Änderungen:** Beim Schließen eines bearbeiteten Dokuments oder ungesicherten Entwurfs fragt iText verlässlich, ob die Änderungen gesichert oder verworfen werden sollen.
- **Eigene native Typst-Druckfunktion (⌘P):** Druckt das Dokument verlustfrei über die integrierte Typst-Engine. Berücksichtigt sämtliche Benutzereinstellungen wie Schriftart, Schriftgröße, Zeilenabstand, Blocksatz und Silbentrennung mit großzügigen, buchgleichen Rändern.
- **Anpassbarer Zeilenabstand:** Stufenlose und menügeführte Justierung des Zeilenabstands für ein ermüdungsfreies Schriftbild (Kompakt bis Doppelt, Standard: 3 pt).
- **Markdown als Standardformat (.md):** Neu erstellte Dokumente werden standardmäßig mit der Dateiendung `.md` vorgeschlagen. Reiner Text (`.txt`) steht im Speicherndialog jederzeit als alternative Option zur Wahl.
- **Markdown-Live-Vorschau:** In `.md`-Dokumenten werden Steuerzeichen (`#`, `**`, `*`, `~~`, `` ` ``) im Lesemodus unsichtbar ausgeblendet und typografisch veredelt dargestellt. Direkt beim Hineinsetzen des Cursors treten die Steuerzeichen zur präzisen Bearbeitung hervor.
- **Echte Plain-Text-Disziplin:** `.txt`-Dateien werden ohne jegliche Interpretation oder Formatierungsballast als unverfälschter Text verarbeitet.
- **Typografischer Feinschliff:** Blocksatz mit homogenem Randausgleich und Apples nativer Silbentrennungs-Engine garantieren ein sauberes Schriftbild nach Typst-Vorbild.
- **Persistente JSON-Konfiguration:** Sämtliche Typografie-, Layout- und Formateinstellungen werden automatisch und atomar in `~/.config/iText/config.json` gesichert.
- **Optimierte Stabilität & Undo-Integrität:** Zeilengenaues Syntax-Caching verhindert unnötige Neuberechnungen bei Cursorbewegungen. Formatierungsänderungen beeinflussen den systemweiten Undo-Verlauf (⌘Z / ⇧⌘Z) nicht.
- **Kompakte Standarddimensionen:** Jedes Dokumentfenster öffnet im optimierten Format von 375 × 664 Bildpunkten.
- **Automatisches Systemdesign:** Vollständige und dynamische Anpassung an den Hell- und Dunkelmodus von macOS.

---

## Tastaturkürzel

- `⌘P`: Dokument drucken (via native Typst-Engine)
- `⌘,`: Typografie- und Anwendungseinstellungen öffnen
- `⌥⌘I`: Dokument-Statistik einblenden (Wörter, Zeichen, Zeilen, Lesezeit)
- `⌘T`: Natives macOS-Schriftenfenster öffnen
- `⌘+`: Schrift vergrößern
- `⌘-`: Schrift verkleinern
- `⌘0`: Standard-Schriftgröße wiederherstellen

---

## Voraussetzungen

- macOS 14.0 (Sonoma) oder neuer
- [Typst](https://typst.app) (`brew install typst`)

---

## Installation

```bash
git clone https://github.com/jonathank55/iText.git
cd iText
./install.sh
```

Das Skript überprüft das Vorhandensein von Typst, kompiliert die Anwendung im Release-Modus, signiert das App-Bundle, kopiert es in Ihren Programme-Ordner und registriert `iText` als Standard-App für `.txt` und `.md`.

---

## Konfiguration

Die Einstellungen können direkt über die grafische Oberfläche (`⌘,`) oder manuell in der Konfigurationsdatei angepasst werden:

```bash
cat ~/.config/iText/config.json
```

---

## Lizenz

MIT License
