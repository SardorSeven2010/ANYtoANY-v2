# CORE: Supabase sozlamalari

Ilova to'liq ishlashi uchun Supabase'da quyidagilarni bir marta bajarish kerak.

## 1. Jadvallarni yaratish (majburiy)

PRO obuna, to'lov so'rovi va admin panel shu jadvallar bilan ishlaydi.

1. Supabase → **SQL Editor** → **New query**.
2. [`schema.sql`](schema.sql) faylining hammasini nusxalab qo'ying.
3. **Run** ni bosing.

Skriptni qayta ishga tushirsangiz ham zarari yo'q. **CORE 2.0** yangilanishida
(bepul sinov va yuklash jurnali jadvallari qo'shildi) uni bir marta qayta ishga tushirish shart.

### Bepul sinov (1 oy)

Yangi akkaunt birinchi marta kirganda server unga **1 oylik PRO** beradi. Sinov
**bir qurilmaga bir marta** beriladi: shu qurilmadan keyin ochilgan boshqa
akkauntlarga sinov berilmaydi (qurilmalar `trial_devices` jadvalida saqlanadi,
ilova unga bevosita tegolmaydi). Sinov muddati ilovadan o'zgartirib bo'lmaydi.
Qurilmasi noaniq akkauntlarga sinov berilmaydi.

PRO **akkauntga** (emailga) bog'liq: boshqa telefon yoki kompyuterda shu email
bilan kirilsa, o'sha yerda ham PRO ishlaydi.

## 2. O'zingizni admin qilish

1. Ilovaga o'z emailingiz bilan kiring (shunda profilingiz yaratiladi).
2. Supabase → **Table Editor** → `user_profiles` → o'z qatoringizni toping.
3. `is_admin` ustunini `true` qiling va saqlang.
4. Ilovada asosiy oynadagi yangilash tugmasini bosing — chap menyuda **Admin panel** paydo bo'ladi.

Admin panel faqat `is_admin = true` bo'lgan akkauntga ko'rinadi. Boshqa
foydalanuvchilar o'ziga PRO yoza olmaydi — buni server qoidalari (RLS) to'sadi.

## 3. PRO berish

PRO'ni ikki joydan berish mumkin:

- **CORE Admin** ilovasi (alohida APK, `admin_app/`) — tavsiya etiladi. Admin
  akkauntingiz emaili bilan kod orqali kirasiz. Yangi to'lov so'rovlari
  "So'rovlar" bo'limida chiqadi va bir tugma bilan tasdiqlanadi; xato bosilsa,
  xabardagi **Qaytarish** bilan bekor qilinadi. Ilova faqat `is_admin = true`
  akkauntni kiritadi.
- Asosiy ilovadagi menyu → **Admin panel**.

Mijoz ilovada tarifni tanlab, kartaga pul o'tkazadi va **To'lov qildim** ni bosadi.
Admin panelda u ro'yxatning tepasida, sariq hoshiyada chiqadi:

- **+1 / +3 / +6 / +9 oylik va +1 yillik** — PRO'ni shu muddatga yoqadi. Obuna hali
  tugamagan bo'lsa, muddat ustiga qo'shiladi.
- **PRO o'chirish** — obunani bekor qiladi.

Muddat tugagach PRO o'zi o'chadi.

Tariflar: 1 oy 12 000, 3 oy 32 000, 6 oy 50 000, 9 oy 72 000, 1 yil 100 000 so'm
(`packages/anytoany_core/lib/anytoany_core.dart` ichidagi `proPlans`).

PRO nima beradi: barcha video kodeklar (bepul tarifda faqat H.264), PDF ni
Word / PowerPoint / Excel ga va hujjatlarni PDF ga aylantirish, cheklanmagan
sondagi fayl (bepul tarifda bir martada 3 ta), haftasiga cheklanmagan video
yuklash va 18 tagacha bo'lakka bo'lib yuklash, yuklanayotgan videoni H.264 yoki
H.265 tanlab saqlash, ilova nomini o'zgartirish.

Bepul tarifda: haftasiga 10 ta video yuklash, 6 tagacha bo'lak. Hisob `download_log`
jadvalida yuritiladi.

## 4. Hujjatlarni internet orqali aylantirish (ixtiyoriy)

Ilovadagi ikki satr shu funksiya orqali ishlaydi:

- **PDF dan Word** — PDF ni Word, PowerPoint yoki Excel ga;
- **Hujjatdan PDF** — Word, PowerPoint, Excel, RTF va TXT ni PDF ga.

Ular Adobe PDF Services'dan foydalanadi: oyiga 500 ta hujjat bepul, karta
talab qilinmaydi. Sozlanmaguncha ilovada "Konvertatsiya xizmati hali
sozlanmagan" degan xabar chiqadi, qolgan hamma narsa ishlayveradi.

**Muhim:** `index.ts` fayli yangilanganda (masalan "Hujjatdan PDF" qo'shilganda)
funksiyani qayta joylash kerak: Supabase'da funksiyani ochib, ichidagi kodni
yangi `index.ts` bilan to'liq almashtiring va **Deploy** ni bosing. Kalitlarni
(Secrets) qayta kiritish shart emas.

### 4.1. Adobe kalitlarini olish

1. <https://developer.adobe.com/document-services/apis/pdf-services/> sahifasini oching.
2. **Get credentials** (yoki **Start free**) ni bosing, Adobe akkaunt oching.
3. Loyihaga nom bering va kalitlarni yarating.
4. **Client ID** va **Client Secret** ni saqlab qo'ying.

### 4.2. Funksiyani joylash

1. Supabase → **Edge Functions** → **Deploy a new function** → **Via Editor**.
2. Funksiya nomi ilovadagi `convertFunctionName` (`lib/config.dart`) bilan bir xil
   bo'lishi kerak. Hozir u `quick-worker`, ya'ni funksiya manzili
   `https://<loyiha>.supabase.co/functions/v1/quick-worker` bo'lishi kerak.
3. [`functions/convert-document/index.ts`](functions/convert-document/index.ts)
   faylining hammasini nusxalab qo'ying.
4. **Deploy** ni bosing.

### 4.3. Kalitlarni kiritish

Supabase → **Edge Functions** → **Secrets**:

| Nomi | Qiymati |
|---|---|
| `ADOBE_CLIENT_ID` | Adobe'dan olingan Client ID |
| `ADOBE_CLIENT_SECRET` | Adobe'dan olingan Client Secret |

Ixtiyoriy sozlamalar:

| Nomi | Ma'nosi | Standart |
|---|---|---|
| `DAILY_LIMIT` | Bir foydalanuvchiga kuniga nechta konvertatsiya | `15` |
| `PRO_ONLY` | `false` qilsangiz, bepul foydalanuvchilar ham ishlata oladi | `true` |

Client Secret'ni hech kimga yubormang va GitHub'ga yozmang.

### 4.4. Xato chiqsa

| Ilovadagi xabar | Sababi |
|---|---|
| Konvertatsiya xizmati hali sozlanmagan | Funksiya joylanmagan, kalitlar kiritilmagan yoki noto'g'ri, yoki 1-bo'limdagi SQL ishga tushirilmagan |
| Avval ilovaga qaytadan kiring | Sessiya tugagan. Qayta kirgandan keyin ham chiqsa, funksiya sozlamalarida **Verify JWT** ni o'chiring (funksiya foydalanuvchini o'zi tekshiradi) |
| Bu imkoniyat faqat PRO obunachilar uchun | Akkauntda faol PRO yo'q |
| Bugungi limit tugadi | Foydalanuvchi `DAILY_LIMIT` ga yetdi |
| Konvertatsiya xizmatining limiti tugagan | Adobe'ning oylik 500 talik limiti tugagan |
