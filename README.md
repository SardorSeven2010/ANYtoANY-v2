# CORE 2.0

Video, audio va PDF uchun hammasi bir joyda: konvertor, pleyer va video yuklagich.
Android, iPhone, Windows va Linux uchun.

## Imkoniyatlar

- **Konvertor**: video / audio / rasm / PDF; PDF dan Word, PowerPoint, Excel; hujjatdan PDF; PDF birlashtirish.
- **Pleyer** (libmpv): avtomatik keyingi video yoki musiqa, takrorlash (ro'yxat / bitta), aralashtirish,
  oxirigacha ijro etib to'xtash; chap / o'rta / o'ng tomonni 2 marta bosish (10 s orqaga / pauza / 10 s oldinga);
  tezlik 0.25x-4x; apparat va dasturiy dekoder; 16:9, 19.5:9, 21:9, 4:3 va boshqa video o'lchamlari;
  skrinshot; ekranni burish; qalqib chiquvchi oyna (Android); fonda ijro va bildirishnoma tugmalari.
- **Video yuklagich**: mini-brauzer, sahifadagi videoni o'zi topadi ("Yuklash" tugmasi paydo bo'ladi),
  `.mp4`, HLS (`.m3u8`, AES-128), DASH (`.mpd`); 6 dan 18 gacha parallel bo'lakka bo'lib yuklash;
  hamma narsa qurilmaning o'zida (serverga hech narsa yuborilmaydi).
- **Tarif**: yangi foydalanuvchiga 1 oy tekin PRO (bir qurilmaga bir marta), keyin 1 / 3 / 6 / 9 / 12 oylik.
  PRO: cheksiz yuklash, 18 bo'lak, H.264 / H.265 tanlash, barcha kodeklar, PDF konvertatsiyalari,
  ilova nomini o'zgartirish. Bepul: haftasiga 10 ta yuklash, 6 bo'lak.
- **Ko'rinish**: oddiy Android (Material) yoki Liquid Glass; 10 ta mavzu.

## Qanday yig'iladi

Platforma papkalari repozitoriyada saqlanmaydi: GitHub Actions (`.github/workflows/build.yml`)
`flutter create` bilan yaratib, `installer/` ichidagi skriptlar bilan sozlaydi.

| Ish | Natija |
|---|---|
| `build` | Android APK (`CORE-arm64-v8a.apk` - ko'pchilik telefonlar uchun) |
| `windows` | `CORE-Setup.exe` va o'rnatmasdan ishlaydigan papka |
| `linux` | `.deb` va `.tar.gz` |
| `ios` | imzosiz `.ipa` (o'rnatish uchun o'zingizning Apple akkauntingiz bilan imzolash kerak) |
| `admin` | alohida CORE Admin ilovasi (APK) |

## Backend (Supabase)

`supabase/SOZLASH.md` ichida: jadvallar (`schema.sql`), admin tayinlash, to'lovni tasdiqlash va
hujjat konvertatsiyasi (Edge Function).

## Papkalar

- `lib/` - ilova: `player/` (dvigatel, navbat, boshqaruv), `downloader/` (yuklagich, HLS, menejer, detektor),
  `browser/`, `screens/`, `services/`, `widgets/`
- `installer/android/` - Android sozlamalari va Kotlin native qatlam (fon xizmati, bildirishnoma, PiP)
- `packages/anytoany_core/` - asosiy va admin ilova uchun umumiy sozlamalar, tariflar, limitlar
- `admin_app/` - admin ilovasi
- `test/` - testlar (mahalliy HTTP server, haqiqiy ffmpeg va libmpv, jsdom bilan sahifa skripti)

## Cheklovlar

- DRM bilan himoyalangan videolar (Netflix va shu kabi), YouTube kabi imzo bilan yashirilgan oqimlar va jonli efirlar yuklanmaydi.
- `blob:` oqimlar to'g'ridan-to'g'ri yuklanmaydi; ba'zi saytlarda video bir necha soniya ijro etilgach manzil topiladi.
- iPhone: qalqib chiquvchi oyna, bildirishnoma va fon yuklash hozircha yo'q.
- Ilova nomini o'zgartirish: ilova ichida va (Android) yangi nomli yorliq sifatida; tizim belgisining nomini ilova o'zgartira olmaydi.
