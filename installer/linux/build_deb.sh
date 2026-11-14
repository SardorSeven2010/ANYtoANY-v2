#!/usr/bin/env bash
# Linux bundle'dan .deb paket yasaydi (Ubuntu, Debian, Linux Mint va boshqalar uchun).
# Foydalanish: build_deb.sh <bundle papkasi> <versiya> <natija papkasi>
set -euo pipefail

BUNDLE="$1"
VERSION="$2"
OUT="$3"
HERE="$(cd "$(dirname "$0")" && pwd)"

WORK="$(mktemp -d)"
PKG="$WORK/anytoany"
mkdir -p "$PKG/DEBIAN" "$PKG/opt/anytoany" "$PKG/usr/bin" \
  "$PKG/usr/share/applications" "$PKG/usr/share/icons/hicolor/512x512/apps"

cp -a "$BUNDLE"/. "$PKG/opt/anytoany/"
ln -s /opt/anytoany/anytoany "$PKG/usr/bin/anytoany"
cp "$HERE/anytoany.desktop" "$PKG/usr/share/applications/anytoany.desktop"
cp "$HERE/../anytoany.png" "$PKG/usr/share/icons/hicolor/512x512/apps/anytoany.png"

SIZE_KB="$(du -sk "$PKG" | cut -f1)"
cat > "$PKG/DEBIAN/control" <<CONTROL
Package: anytoany
Version: $VERSION
Section: video
Priority: optional
Architecture: amd64
Maintainer: ANYtoANY <noreply@anytoany.invalid>
Installed-Size: $SIZE_KB
Depends: libgtk-3-0t64 | libgtk-3-0, libjson-glib-1.0-0, xdg-utils
Description: ANYtoANY - video, audio va PDF konverter
 Video, audio va rasmlarni boshqa formatlarga aylantiradi, PDF fayllarni
 birlashtiradi va o'qiydi. Internetsiz ishlaydi; PDF va Word konvertatsiyasi
 hamda kirish uchun internet kerak.
CONTROL

mkdir -p "$OUT"
DEB="$OUT/anytoany_${VERSION}_amd64.deb"
dpkg-deb --build --root-owner-group "$PKG" "$DEB"
rm -rf "$WORK"
dpkg-deb --info "$DEB"
echo "Tayyor: $DEB"
