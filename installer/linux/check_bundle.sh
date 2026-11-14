#!/usr/bin/env bash
# Linux bundle'ni tekshiradi va tuzatadi:
#  - pdf_combiner o'zining libpdfium.so faylini bundle'ga qo'shmaydi -> qo'lda qo'shiladi
#  - bundle/lib dagi kutubxonalar (plaginlar, FFmpeg, PDFium) bog'liqliklarini o'z papkasidan
#    ($ORIGIN) qidiradigan qilinadi. Aks holda FFmpeg dlopen paytida libavdevice va boshqalarni
#    topa olmaydi va konvertatsiya ishlamaydi.
#  - ishga tushirish fayli va hamma kutubxonalarning bog'liqliklari topilishi tekshiriladi
# Foydalanish: check_bundle.sh <bundle papkasi> <libpdfium.so manzili>
set -euo pipefail

BUNDLE="$1"
PDFIUM="$2"
LIB="$BUNDLE/lib"
EXE="$BUNDLE/anytoany"

[ -x "$EXE" ] || { echo "Topilmadi: $EXE"; exit 1; }
[ -f "$PDFIUM" ] || { echo "Topilmadi: $PDFIUM"; exit 1; }

# Linux'da tizimning ffmpeg dasturi ishlatiladi: FFmpegKit kutubxonalari eski distributivlarning
# kodek kutubxonalariga (libvpx.so.7, libx265.so.199 ...) bog'liq va yangi tizimlarda yuklanmaydi.
rm -f "$LIB"/libffmpegkit.so* "$LIB"/libavcodec.so* "$LIB"/libavdevice.so* "$LIB"/libavfilter.so* \
  "$LIB"/libavformat.so* "$LIB"/libavutil.so* "$LIB"/libswresample.so* "$LIB"/libswscale.so*
echo "FFmpegKit kutubxonalari olib tashlandi (Linux'da tizim ffmpeg'i ishlatiladi)"

if [ ! -f "$LIB/libpdfium.so" ]; then
  cp "$PDFIUM" "$LIB/libpdfium.so"
  echo "libpdfium.so bundle/lib ga qo'shildi"
fi

# Tekshiriladigan va tuzatiladigan kutubxonalar: haqiqiy fayllar (symlink emas).
# libapp.so (Dart kodi) va libflutter_linux_gtk.so ga tegilmaydi.
libs=()
for file in "$LIB"/*.so "$LIB"/*.so.*; do
  [ -e "$file" ] || continue
  [ -L "$file" ] && continue
  case "$(basename "$file")" in
    libapp.so|libflutter_linux_gtk.so) continue ;;
  esac
  libs+=("$file")
done

for file in "${libs[@]}"; do
  patchelf --set-rpath '$ORIGIN' "$file"
done
echo "RUNPATH=\$ORIGIN qo'yildi: ${#libs[@]} ta kutubxona"

missing=0
for file in "$EXE" "${libs[@]}"; do
  if ldd "$file" | grep -q "not found"; then
    echo "XATO: $(basename "$file") uchun topilmagan kutubxonalar:"
    ldd "$file" | grep "not found"
    missing=1
  fi
done
[ "$missing" -eq 0 ] || exit 1

echo "Hamma kutubxonalar topildi. Bundle ichidagilar:"
ls -1 "$LIB"
echo "Tizimdan olinadigan kutubxonalar:"
for file in "$EXE" "${libs[@]}"; do ldd "$file"; done \
  | awk '/=> \// {print $3}' | grep -v "^$(cd "$LIB" && pwd)/" | xargs -r -n1 basename | sort -u
