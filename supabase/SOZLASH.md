# ANYtoANY: Supabase sozlamalari

Ilova to'liq ishlashi uchun Supabase'da quyidagilarni bir marta bajarish kerak.

## 1. Jadvallarni yaratish (majburiy)

PRO obuna, to'lov so'rovi va admin panel shu jadvallar bilan ishlaydi.

1. Supabase → **SQL Editor** → **New query**.
2. [`schema.sql`](schema.sql) faylining hammasini nusxalab qo'ying.
3. **Run** ni bosing.

Skriptni qayta ishga tushirsangiz ham zarari yo'q.

## 2. O'zingizni admin qilish

1. Ilovaga o'z emailingiz bilan kiring (shunda profilingiz yaratiladi).
2. Supabase → **Table Editor** → `user_profiles` → o'z qatoringizni toping.
3. `is_admin` ustunini `true` qiling va saqlang.
4. Ilovada asosiy oynadagi yangilash tugmasini bosing — chap menyuda **Admin panel** paydo bo'ladi.

Admin panel faqat `is_admin = true` bo'lgan akkauntga ko'rinadi. Boshqa
foydalanuvchilar o'ziga PRO yoza olmaydi — buni server qoidalari (RLS) to'sadi.

## 3. PRO berish

Mijoz ilovada tarifni tanlab, kartaga pul o'tkazadi va **To'lov qildim** ni bosadi.
Admin panelda u ro'yxatning tepasida, sariq hoshiyada chiqadi:

- **+1 oylik / +6 oylik / +1 yillik** — PRO'ni shu muddatga yoqadi. Obuna hali
  tugamagan bo'lsa, muddat ustiga qo'shiladi.
- **PRO o'chirish** — obunani bekor qiladi.

Muddat tugagach PRO o'zi o'chadi.

PRO nima beradi: barcha video kodeklar (bepul tarifda faqat H.264), PDF ni
Word / PowerPoint / Excel ga aylantirish va cheklanmagan sondagi fayl
(bepul tarifda bir martada 3 ta).

## 4. PDF ni Word / PowerPoint / Excel ga aylantirish (ixtiyoriy)

Bu imkoniyat Adobe PDF Services orqali ishlaydi: oyiga 500 ta hujjat bepul,
karta talab qilinmaydi. Sozlanmaguncha ilovada "Konvertatsiya xizmati hali
sozlanmagan" degan xabar chiqadi, qolgan hamma narsa ishlayveradi.

### 4.1. Adobe kalitlarini olish

1. <https://developer.adobe.com/document-services/apis/pdf-services/> sahifasini oching.
2. **Get credentials** (yoki **Start free**) ni bosing, Adobe akkaunt oching.
3. Loyihaga nom bering va kalitlarni yarating.
4. **Client ID** va **Client Secret** ni saqlab qo'ying.

### 4.2. Funksiyani joylash

1. Supabase → **Edge Functions** → **Deploy a new function** → **Via Editor**.
2. Nomi aynan shunday bo'lsin: `convert-document`.
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
