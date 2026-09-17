#!/bin/sh
# Compila Trayecto.app (macOS 12 o más reciente). Requiere las herramientas de
# línea de comandos de Xcode:  xcode-select --install
#
#   mac/construir.sh            compila en mac/build/Trayecto.app
#   mac/construir.sh --abrir    compila y la abre
#
# La app recuerda dónde está este repositorio. Si mueves la carpeta, vuelve a compilar.
set -eu

AQUI="$(cd "$(dirname "$0")" && pwd)"
RAIZ="$(dirname "$AQUI")"
APP="$AQUI/build/Trayecto.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -swift-version 5 -target "$(uname -m)-apple-macos12.0" \
  -framework Cocoa -framework WebKit \
  -o "$APP/Contents/MacOS/Trayecto" "$AQUI/Trayecto.swift"

# Ícono a partir del PNG de la web.
CONJUNTO="$AQUI/build/Trayecto.iconset"
rm -rf "$CONJUNTO" && mkdir -p "$CONJUNTO"
for n in 16 32 128 256; do
  sips -z $n $n "$RAIZ/web/iconos/icono-512.png" --out "$CONJUNTO/icon_${n}x${n}.png" >/dev/null
  d=$((n * 2))
  sips -z $d $d "$RAIZ/web/iconos/icono-512.png" --out "$CONJUNTO/icon_${n}x${n}@2x.png" >/dev/null
done
iconutil -c icns "$CONJUNTO" -o "$APP/Contents/Resources/Trayecto.icns" 2>/dev/null || true
rm -rf "$CONJUNTO"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Trayecto</string>
  <key>CFBundleDisplayName</key><string>Trayecto</string>
  <key>CFBundleIdentifier</key><string>io.github.trayecto</string>
  <key>CFBundleExecutable</key><string>Trayecto</string>
  <key>CFBundleIconFile</key><string>Trayecto</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>12.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsLocalNetworking</key><true/></dict>
  <key>TrayectoRaiz</key><string>$RAIZ</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "Lista: $APP"

if [ "${1:-}" = "--abrir" ]; then open "$APP"; fi
