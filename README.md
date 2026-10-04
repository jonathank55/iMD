# iText

Schlanker, minimalistischer und hochstabiler Text- & Markdown-Editor für macOS mit nativer Typst-PDF-Druckanbindung via [txt2pdf](https://github.com/jonathank55/txt2pdf).

---

## Funktionen

- **Echte Plain-Text-Disziplin:** `.txt`-Dateien werden ohne jegliche Interpretation oder Formatierungsballast als reiner Text verarbeitet.
- **Obsidian-Live-Vorschau:** In `.md`-Dokumenten werden Steuerzeichen (`#`, `**`, `*`, `~~`, `` ` ``) im Lesemodus unsichtbar ausgeblendet und typografisch veredelt dargestellt. Direkt beim Hineinsetzen des Cursors treten die rohen Steuerzeichen zur exakten Bearbeitung hervor.
- **Typografischer Feinschliff:** Blocksatz mit homogenem Randausgleich und Apples nativer Silbentrennungs-Engine garantieren ein sauberes Schriftbild nach Typst-Vorbild.
- **Druckfunktion via txt2pdf (⌘P):** Drucken kompiliert das aktuelle Dokument verlustfrei über `txt2pdf` unter Berücksichtigung aller Markdown-Elemente (Überschriftenhierarchien, Codeblöcke, Tabellen, Zitate, Listen) und öffnet direkt das native macOS-Druckmenü.
- **Kompakte Standarddimensionen:** Jedes Fenster startet im schlanken, optimierten Format von 375 × 664 Bildpunkten.
- **Automatisches Systemdesign:** Vollständige und dynamische Anpassung an den Hell- und Dunkelmodus von macOS.
- **Typografie-Steuerung:** Stufenlose Skalierung der Schriftgröße via Tastaturkürzel (⌘+, ⌘-, ⌘0) sowie Schriftauswahl über das integrierte Menü.

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

## Lizenz

MIT License
