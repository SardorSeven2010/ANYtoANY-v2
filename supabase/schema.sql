-- =====================================================================
-- CORE: Supabase bazasi
--
-- Qanday ishlatiladi: Supabase -> SQL Editor -> shu faylning hammasini
-- nusxalab qo'ying -> "Run". Qayta ishga tushirsangiz ham zarari yo'q.
--
-- Admin bo'lish: ilovaga bir marta kiring, keyin Table Editor ->
-- user_profiles -> o'z qatoringizda is_admin ni true qiling.
-- =====================================================================

-- ---------- Foydalanuvchi profillari ----------
-- Yangi foydalanuvchiga 1 oy tekin PRO (bepul sinov) beriladi: bir qurilmaga bir marta.
create table if not exists public.user_profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text,
  android_id text,
  total_seconds bigint not null default 0,
  is_pro boolean not null default false,
  pro_until timestamptz,
  payment_requested boolean not null default false,
  payment_info text,
  payment_plan text,
  is_admin boolean not null default false,
  trial_started_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Jadval avvaldan bor bo'lsa, yetishmayotgan ustunlar qo'shiladi
alter table public.user_profiles add column if not exists email text;
alter table public.user_profiles add column if not exists android_id text;
alter table public.user_profiles add column if not exists total_seconds bigint not null default 0;
alter table public.user_profiles add column if not exists is_pro boolean not null default false;
alter table public.user_profiles add column if not exists pro_until timestamptz;
alter table public.user_profiles add column if not exists payment_requested boolean not null default false;
alter table public.user_profiles add column if not exists payment_info text;
alter table public.user_profiles add column if not exists payment_plan text;
alter table public.user_profiles add column if not exists is_admin boolean not null default false;
alter table public.user_profiles add column if not exists trial_started_at timestamptz;
alter table public.user_profiles add column if not exists created_at timestamptz not null default now();
alter table public.user_profiles add column if not exists updated_at timestamptz not null default now();

alter table public.user_profiles enable row level security;
grant select, insert, update on public.user_profiles to authenticated;

-- Joriy foydalanuvchi adminmi?
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.user_profiles where id = auth.uid() and is_admin
  );
$$;

-- Eski qoidalar olib tashlanadi va yangilari qo'yiladi
do $$
declare
  p record;
begin
  for p in
    select policyname from pg_policies
    where schemaname = 'public' and tablename = 'user_profiles'
  loop
    execute format('drop policy %I on public.user_profiles', p.policyname);
  end loop;
end $$;

-- Har kim faqat o'z qatorini ko'radi va o'zgartiradi; admin hammasini
create policy "profile_select" on public.user_profiles
  for select to authenticated
  using (id = auth.uid() or public.is_admin());

create policy "profile_insert" on public.user_profiles
  for insert to authenticated
  with check (id = auth.uid());

create policy "profile_update" on public.user_profiles
  for update to authenticated
  using (id = auth.uid() or public.is_admin())
  with check (id = auth.uid() or public.is_admin());

-- Bepul sinov berilgan qurilmalar. Faqat trigger (security definer) yozadi va o'qiydi:
-- jadvalda siyosat yo'q, shuning uchun ilovalar unga bevosita tegolmaydi.
create table if not exists public.trial_devices (
  device_id text primary key,
  user_id uuid references auth.users (id) on delete set null,
  granted_at timestamptz not null default now()
);
alter table public.trial_devices enable row level security;

-- Oddiy foydalanuvchi o'ziga PRO yoki admin huquqini yoza olmaydi:
-- is_pro, pro_until va is_admin ni faqat admin (yoki Supabase paneli) o'zgartiradi.
-- Yagona istisno: yangi profil yaratilganda qurilma birinchi marta ko'rilsa, 1 oylik sinov beriladi.
create or replace function public.protect_profile_columns()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_role text := coalesce(
    nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', ''
  );
begin
  if caller_role in ('authenticated', 'anon') and not public.is_admin() then
    if tg_op = 'INSERT' then
      new.is_pro := false;
      new.pro_until := null;
      new.is_admin := false;
      new.trial_started_at := null;
      -- Aniq bo'lmagan qurilma nomlariga sinov berilmaydi
      if coalesce(new.android_id, '') <> ''
         and new.android_id not in ('unknown_device', 'iPhone', 'PC')
         and not exists (select 1 from public.trial_devices d where d.device_id = new.android_id) then
        insert into public.trial_devices (device_id, user_id) values (new.android_id, new.id);
        new.is_pro := true;
        new.pro_until := now() + make_interval(months => 1);
        new.trial_started_at := now();
      end if;
    else
      new.is_pro := old.is_pro;
      new.pro_until := old.pro_until;
      new.is_admin := old.is_admin;
      new.trial_started_at := old.trial_started_at;
    end if;
  end if;
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists protect_profile_columns on public.user_profiles;
create trigger protect_profile_columns
  before insert or update on public.user_profiles
  for each row execute function public.protect_profile_columns();

-- ---------- Onlayn PDF konvertatsiyalar jurnali (kunlik limit uchun) ----------
create table if not exists public.conversion_log (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  target_format text not null,
  created_at timestamptz not null default now()
);

create index if not exists conversion_log_user_day
  on public.conversion_log (user_id, created_at desc);

alter table public.conversion_log enable row level security;
grant select, insert on public.conversion_log to authenticated;

drop policy if exists "log_select" on public.conversion_log;
drop policy if exists "log_insert" on public.conversion_log;

create policy "log_select" on public.conversion_log
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

create policy "log_insert" on public.conversion_log
  for insert to authenticated
  with check (user_id = auth.uid());

-- ---------- Video yuklash jurnali (haftalik limit uchun) ----------
create table if not exists public.download_log (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid() references auth.users (id) on delete cascade,
  host text,
  kind text,
  created_at timestamptz not null default now()
);

create index if not exists download_log_user_time
  on public.download_log (user_id, created_at desc);

alter table public.download_log enable row level security;
grant select, insert on public.download_log to authenticated;

drop policy if exists "dl_select" on public.download_log;
drop policy if exists "dl_insert" on public.download_log;

create policy "dl_select" on public.download_log
  for select to authenticated
  using (user_id = auth.uid() or public.is_admin());

create policy "dl_insert" on public.download_log
  for insert to authenticated
  with check (user_id = auth.uid());
