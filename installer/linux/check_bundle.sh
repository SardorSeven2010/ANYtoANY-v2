#!/usr/bin/env bash
# Linux bundle'ni tekshiradi va tuzatadi:
#  - pdf_combiner o'zining libpdfium.so faylini bundle'ga qo'shmaydi -> qo'lda qo'shiladi
#  - plagin kutubxonalari bog'liqliklarini o'z papkasidan ($ORIGIN) qidiradigan qilinadi
#  - ishga tushirish fayli va plaginlarning hamma bog'liqliklari topilishi tekshiriladi
# Foydalanish: check_bundle.sh <bundle papkasi> <libpdfium.so manzili>
set -euo pipefail

BUNDLE="$1"
PDFIUM="$2"
LIB="$BUNDLE/lib"
EXE="$BUNDLE/anytoany"

[ -x "$EXE" ] || { echo "Topilmadi: $EXE"; exit 1; }
[ -f "$PDFIUM" ] || { echo "Topilmadi: $PDFIUM"; exit 1; }

if [ ! -f "$LIB/libpdfium.so" ]; then
  cp "$PDFIUM" "$LIB/libpdfium.so"
  echo "libpdfium.so bundle/lib ga qo'shildi"
fi

for plugin in "$LIB"/*_plugin.so; do
  patchelf --set-rpath '$ORIGIN' "$plugin"
done
echo "Plaginlar RUNPATH: \$ORIGIN"

missing=0
for file in "$EXE" "$LIB"/*_plugin.so "$LIB/libpdfium.so"; do
  if ldd "$file" | grep -q "not found"; then
    echo "XATO: $(basename "$file") uchun topilmagan kutubxonalar:"
    ldd "$file" | grep "not found"
    missing=1
  fi
done
[ "$missing" -eq 0 ] || exit 1
echo "Hamma kutubxonalar topildi:"
ls -1 "$LIB"
