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

# 1. Typst-Prüfung und -Installation
echo -e "${BLUE}▸${RESET} ${BOLD}Schritt 1:${RESET} Typst-Compiler überprüfen und sicherstellen..."

resolve_typst_binary() {
    if command -v typst &>/dev/null; then
        command -v typst
    elif [ -x "/opt/homebrew/bin/typst" ]; then
        echo "/opt/homebrew/bin/typst"
    elif [ -x "/usr/local/bin/typst" ]; then
        echo "/usr/local/bin/typst"
    elif [ -x "$HOME/.local/bin/typst" ]; then
        echo "$HOME/.local/bin/typst"
    elif [ -x "$HOME/.cargo/bin/typst" ]; then
        echo "$HOME/.cargo/bin/typst"
    else
        echo ""
    fi
}

TYPST_BIN="$(resolve_typst_binary)"

if [ -z "$TYPST_BIN" ]; then
    echo -e "${YELLOW}⚠ Typst nicht gefunden. Automatische Installation wird eingeleitet...${RESET}"
    
    BREW_BIN=""
    if command -v brew &>/dev/null; then
        BREW_BIN="brew"
    elif [ -x "/opt/homebrew/bin/brew" ]; then
        BREW_BIN="/opt/homebrew/bin/brew"
    elif [ -x "/usr/local/bin/brew" ]; then
        BREW_BIN="/usr/local/bin/brew"
    fi

    if [ -n "$BREW_BIN" ]; then
        echo -e "${BLUE}▸${RESET} Installiere Typst via Homebrew ($BREW_BIN install typst)..."
        "$BREW_BIN" install typst || true
        TYPST_BIN="$(resolve_typst_binary)"
    fi

    if [ -z "$TYPST_BIN" ]; then
        echo -e "${YELLOW}⚠ Homebrew nicht verfügbar oder Installation fehlgeschlagen. Lade statisches Typst-Binary herunter...${RESET}"
        mkdir -p "$HOME/.local/bin"
        ARCH="$(uname -m)"
        if [ "$ARCH" = "arm64" ]; then
            TAR_NAME="typst-aarch64-apple-darwin.tar.xz"
        else
            TAR_NAME="typst-x86_64-apple-darwin.tar.xz"
        fi
        TMP_DIR="$(mktemp -d)"
        CURL_URL="https://github.com/typst/typst/releases/latest/download/$TAR_NAME"
        if curl -sSL -f "$CURL_URL" -o "$TMP_DIR/$TAR_NAME"; then
            tar -xf "$TMP_DIR/$TAR_NAME" -C "$TMP_DIR"
            EXTRACTED_BIN="$(find "$TMP_DIR" -name typst -type f | head -n 1)"
            if [ -n "$EXTRACTED_BIN" ]; then
                cp -f "$EXTRACTED_BIN" "$HOME/.local/bin/typst"
                chmod +x "$HOME/.local/bin/typst"
                TYPST_BIN="$HOME/.local/bin/typst"
                echo -e "${GREEN}✓ OK${RESET} Typst nach ~/.local/bin/typst installiert."
            fi
        fi
        rm -rf "$TMP_DIR"
    fi
fi

TYPST_BIN="$(resolve_typst_binary)"
if [ -n "$TYPST_BIN" ] && [ -x "$TYPST_BIN" ]; then
    echo -e "${GREEN}✓ OK${RESET} Typst ist einsatzbereit: $($TYPST_BIN --version) [${TYPST_BIN}]"
else
    echo -e "${RED}✗ Fehler: Typst konnte nicht automatisch installiert werden.${RESET}"
    exit 1
fi

# 2. iText kompilieren
echo -e "\n${BLUE}▸${RESET} ${BOLD}Schritt 2:${RESET} iText kompilieren (Release-Modus)..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

swift build -c release
echo -e "${GREEN}✓ OK${RESET} Kompilierung erfolgreich abgeschlossen."

# 3. App-Bundle schnüren
echo -e "\n${BLUE}▸${RESET} ${BOLD}Schritt 3:${RESET} macOS-App-Bundle vorbereiten und signieren..."
APP_DIR="$SCRIPT_DIR/iText.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$SCRIPT_DIR/.build/release/iText" "$APP_DIR/Contents/MacOS/iText"
cp "$SCRIPT_DIR/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns" 2>/dev/null || true
cp "$SCRIPT_DIR/Configuration/Info-macOS.plist" "$APP_DIR/Contents/Info.plist"

# Schriften im Bundle einbinden
if [ -d "$SCRIPT_DIR/Fonts" ]; then
    rm -rf "$APP_DIR/Contents/Resources/Fonts"
    cp -R "$SCRIPT_DIR/Fonts" "$APP_DIR/Contents/Resources/Fonts"
fi

# Typst-Binary direkt in das App-Bundle einbetten (autarker Druck-Support)
if [ -n "$TYPST_BIN" ] && [ -x "$TYPST_BIN" ]; then
    cp -f "$TYPST_BIN" "$APP_DIR/Contents/MacOS/typst"
    chmod +x "$APP_DIR/Contents/MacOS/typst"
    echo -e "${GREEN}✓ OK${RESET} Typst-Compiler autark im App-Bundle integriert."
fi

sed -i '' 's/\$(EXECUTABLE_NAME)/iText/g; s/\$(PRODUCT_BUNDLE_IDENTIFIER)/com.jonathan.iText/g; s/\$(PRODUCT_NAME)/iText/g' "$APP_DIR/Contents/Info.plist"
echo "APPL????" > "$APP_DIR/Contents/PkgInfo"

codesign --force --deep --sign - "$APP_DIR"
echo -e "${GREEN}✓ OK${RESET} App-Bundle erfolgreich signiert."

# 4. Schriftarten auf dem System installieren
echo -e "\n${BLUE}▸${RESET} ${BOLD}Schritt 4:${RESET} Schriftarten im System installieren..."
mkdir -p "$HOME/Library/Fonts"
if [ -d "$SCRIPT_DIR/Fonts" ]; then
    cp -f "$SCRIPT_DIR/Fonts/"*.ttf "$HOME/Library/Fonts/" 2>/dev/null || true
    echo -e "${GREEN}✓ OK${RESET} Sämtliche Schriftarten (Bookerly, Faustina, PT Serif) nach ~/Library/Fonts/ installiert."
fi

# 5. App installieren
echo -e "\n${BLUE}▸${RESET} ${BOLD}Schritt 5:${RESET} App im Benutzer-Programme-Ordner installieren..."
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/iText.app"
cp -R "$APP_DIR" "$HOME/Applications/"
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
