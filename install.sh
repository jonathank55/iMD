#!/usr/bin/env bash
set -e

# Farben für formatierte Terminal-Ausgabe
BLUE='\033[1m\033[0;34m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "\n${BLUE}=== iText — Installations- & Bereitstellungsskript ===${RESET}"
echo -e "${BLUE}───────────────────────────────────────────────────────────────────────────${RESET}"

# 1. Typst-Prüfung
echo -e "${BLUE}▸${RESET} ${BOLD}Schritt 1:${RESET} Typst-Compiler überprüfen..."
if ! command -v typst &>/dev/null; then
    echo -e "${YELLOW}⚠ Typst nicht gefunden. Installation via Homebrew...${RESET}"
    if command -v brew &>/dev/null; then
        brew install typst
    else
        echo -e "${RED}✗ Fehler: Homebrew wird zur automatischen Installation von Typst benötigt.${RESET}"
        exit 1
    fi
else
    echo -e "${GREEN}✓ OK${RESET} Typst ist installiert: $(typst --version)"
fi

# 2. txt2pdf-Prüfung
echo -e "\n${BLUE}▸${RESET} ${BOLD}Schritt 2:${RESET} txt2pdf-PDF-Engine überprüfen..."
if ! command -v txt2pdf &>/dev/null && [ ! -x "$HOME/.local/bin/txt2pdf" ]; then
    echo -e "${YELLOW}⚠ txt2pdf nicht gefunden. Installation via GitHub...${RESET}"
    TMP_DIR=$(mktemp -d)
    git clone https://github.com/jonathank55/txt2pdf.git "$TMP_DIR/txt2pdf"
    mkdir -p "$HOME/.local/bin"
    cp "$TMP_DIR/txt2pdf/txt2pdf" "$HOME/.local/bin/txt2pdf"
    chmod +x "$HOME/.local/bin/txt2pdf"
    rm -rf "$TMP_DIR"
    echo -e "${GREEN}✓ OK${RESET} txt2pdf erfolgreich in ~/.local/bin/ installiert."
else
    echo -e "${GREEN}✓ OK${RESET} txt2pdf ist verfügbar."
fi

# 3. iText kompilieren
echo -e "\n${BLUE}▸${RESET} ${BOLD}Schritt 3:${RESET} iText kompilieren (Release-Modus)..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

swift build -c release
echo -e "${GREEN}✓ OK${RESET} Kompilierung erfolgreich abgeschlossen."

# 4. App-Bundle schnüren
echo -e "\n${BLUE}▸${RESET} ${BOLD}Schritt 4:${RESET} macOS-App-Bundle vorbereiten und signieren..."
APP_DIR="$SCRIPT_DIR/iText.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$SCRIPT_DIR/.build/release/iText" "$APP_DIR/Contents/MacOS/iText"
cp "$SCRIPT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns" 2>/dev/null || true
cp "$SCRIPT_DIR/Configuration/Info-macOS.plist" "$APP_DIR/Contents/Info.plist"

sed -i '' 's/\$(EXECUTABLE_NAME)/iText/g; s/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.jonathan.iText/g; s/\$(PRODUCT_NAME)/iText/g' "$APP_DIR/Contents/Info.plist"
echo "APPL????" > "$APP_DIR/Contents/PkgInfo"

codesign --force --deep --sign - "$APP_DIR"
echo -e "${GREEN}✓ OK${RESET} App-Bundle erfolgreich signiert."

# 5. App installieren
echo -e "\n${BLUE}▸${RESET} ${BOLD}Schritt 5:${RESET} App im Benutzer-Programme-Ordner installieren..."
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/iText.app"
cp -R "$APP_DIR" "$HOME/Applications/iText.app"
echo -e "${GREEN}✓ OK${RESET} iText.app nach ~/Applications/ kopiert."

# 6. Registrierung und Standard-App setzen
echo -e "\n${BLUE}▸${RESET} ${BOLD}Schritt 6:${RESET} Dateizuordnungen für .txt und .md registrieren..."
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/iText.app"

if command -v duti &>/dev/null; then
    duti -s com.jonathan.iText public.plain-text all
    duti -s com.jonathan.iText net.daringfireball.markdown all
    duti -s com.jonathan.iText txt all
    duti -s com.jonathan.iText md all
    echo -e "${GREEN}✓ OK${RESET} iText als Standard-App für .txt und .md gesetzt."
fi

echo -e "\n${BLUE}───────────────────────────────────────────────────────────────────────────${RESET}"
echo -e "${GREEN}✓ ERFOLG:${RESET} ${BOLD}iText ist startbereit und im Dock / Launchpad verfügbar!${RESET}\n"
