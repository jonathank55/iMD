# iText

Schlanker, minimalistischer und hochstabiler Text- & Markdown-Editor für macOS mit puristischem, leistenlosem Fensterdesign, nativer Menüleistensteuerung und Typst-PDF-Druckanbindung via [txt2pdf](https://github.com/jonathank55/txt2pdf).

---

## Funktionen

- **Puristisches Fensterdesign:** Vollständiger Verzicht auf Fensterleisten oder störende Schaltflächen. Der Text steht uneingeschränkt im Mittelpunkt. Alle Funktionen werden ausschließlich über die native macOS-Menüleiste und Tastaturkürzel gesteuert.
- **Markdown als Standardformat (.md):** Neu erstellte Dokumente werden standardmäßig im Markdown-Format gespeichert. Reiner Text (`.txt`) steht im Speicherndialog jederzeit als alternative Option zur Verfügung.
- **Obsidian-Live-Vorschau:** In `.md`-Dokumenten werden Steuerzeichen (`#`, `**`, `*`, `~~`, `` ` ``) im Lesemodus unsichtbar ausgeblendet und typografisch veredelt dargestellt. Sobald der Cursor in eine Zeile gesetzt wird, treten die Steuerzeichen zur präzisen Bearbeitung hervor.
- **Echte Plain-Text-Disziplin:** `.txt`-Dateien werden ohne jegliche Interpretation oder Formatierungsballast als unverfälschter Text verarbeitet.
- **Typografischer Feinschliff:** Blocksatz mit homogenem Randausgleich und Apples nativer Silbentrennungs-Engine garantieren ein harmonisches Schriftbild nach Typst-Vorbild.
- **Druckfunktion via txt2pdf (⌘P):** Drucken kompiliert das Dokument verlustfrei über `txt2pdf` unter Berücksichtigung aller Markdown-Elemente (Überschriftenhierarchien, Codeblöcke, Tabellen, Zitate, Aufgabenlisten) und öffnet direkt das native macOS-Druckmenü.
- **Persistente JSON-Konfiguration:** Sämtliche Typografie-, Layout- und Formateinstellungen werden automatisch und atomar in `~/.config/iText/config.json` gesichert.
- **Optimierte Stabilität & Undo-Integrität:** Zeilengenaues Syntax-Caching verhindert unnötige Neuberechnungen bei Cursorbewegungen. Formatierungsänderungen beeinflussen den systemweiten Undo-Verlauf (⌘Z / ⇧⌘Z) nicht.
- **Kompakte Standarddimensionen:** Jedes Dokumentfenster öffnet im optimierten Format von 375 × 664 Bildpunkten.
- **Automatisches Systemdesign:** Vollständige, nahtlose Anpassung an den Hell- und Dunkelmodus von macOS.

---

## Tastaturkürzel

- `⌘P`: Dokument drucken (via txt2pdf & Typst)
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
- [txt2pdf](https://github.com/jonathank55/txt2pdf) (wird bei Bedarf automatisch installiert)

---

## Installation

```bash
git clone https://github.com/jonathank55/iText.git
cd iText
./install.sh
```

Das Skript überprüft alle Abhängigkeiten, kompiliert die Anwendung im Release-Modus, signiert das App-Bundle, kopiert es in Ihren Programme-Ordner und registriert `iText` als Standard-App für `.txt` und `.md`.

---

## Konfiguration

Die Einstellungen können direkt über die grafische Oberfläche (`⌘,`) oder manuell in der Konfigurationsdatei angepasst werden:

```bash
cat ~/.config/iText/config.json
```

---

## Lizenz

MIT License
