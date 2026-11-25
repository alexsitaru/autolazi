-- =====================================================================
-- AutoLaZi – etapa 1: baza de date
-- Se rulează O SINGURĂ DATĂ în Supabase → SQL Editor → New query → Run
-- Se poate rula din nou fără probleme (nu șterge date).
-- =====================================================================

-- 1) Abonamente – un tabel comun pentru TOATE aplicațiile aplicatii-utile.ro
--    Clientul își poate CITI abonamentul, dar NU îl poate modifica.
--    Doar serverul (plățile Netopia, mai târziu) scrie aici.
create table if not exists public.app_subscriptions (
  user_id     uuid not null references auth.users(id) on delete cascade,
  app         text not null,                 -- ex: 'autolazi', 'caietul'
  plan        text not null default 'free',  -- free / family / small / business
  valid_until timestamptz,                   -- până când e plătit
  updated_at  timestamptz not null default now(),
  primary key (user_id, app)
);
alter table public.app_subscriptions enable row level security;

drop policy if exists "abonament - citeste doar al tau" on public.app_subscriptions;
create policy "abonament - citeste doar al tau"
  on public.app_subscriptions for select
  using (auth.uid() = user_id);
-- Fără reguli de adăugare / modificare → clientul nu își poate schimba singur planul.


-- 2) Datele AutoLaZi – câte un rând pentru fiecare cont
--    (mașini, documente, setări de alertă, totul într-un singur pachet)
create table if not exists public.autolazi_data (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);
alter table public.autolazi_data enable row level security;

drop policy if exists "autolazi - citeste datele tale"  on public.autolazi_data;
drop policy if exists "autolazi - adauga datele tale"   on public.autolazi_data;
drop policy if exists "autolazi - modifica datele tale" on public.autolazi_data;
drop policy if exists "autolazi - sterge datele tale"   on public.autolazi_data;

create policy "autolazi - citeste datele tale"  on public.autolazi_data for select using (auth.uid() = user_id);
create policy "autolazi - adauga datele tale"   on public.autolazi_data for insert with check (auth.uid() = user_id);
create policy "autolazi - modifica datele tale" on public.autolazi_data for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "autolazi - sterge datele tale"   on public.autolazi_data for delete using (auth.uid() = user_id);


-- 3) Planul curent al unui cont (folosit doar de server, nu de clienți)
--    PERIOADA DE TEST: cine nu are abonament plătit primește 'business',
--    ca să poată încerca tot. La lansarea oficială se schimbă 'business'
--    de mai jos în 'free' și se rulează din nou doar această funcție.
create or replace function public._autolazi_plan(uid uuid)
returns text
language sql stable security definer
set search_path = public
as $$
  select coalesce(
    (select plan from app_subscriptions
      where user_id = uid and app = 'autolazi'
        and (valid_until is null or valid_until > now())),
    'business'   -- ← perioada de test; la lansare devine 'free'
  );
$$;
revoke all on function public._autolazi_plan(uuid) from public, anon, authenticated;


-- 4) Protecție: nimeni nu poate salva mai multe mașini decât îi permite planul,
--    chiar dacă ar umbla la aplicație.
create or replace function public._autolazi_verifica()
returns trigger
language plpgsql security definer
set search_path = public
as $$
declare
  p    text;
  maxv int;
  n    int;
begin
  new.updated_at := now();
  p := _autolazi_plan(new.user_id);
  maxv := case p
            when 'family'   then 4
            when 'small'    then 10
            when 'business' then 100000
            else 1
          end;
  n := coalesce(jsonb_array_length(new.data -> 'vehicles'), 0);
  if n > maxv then
    raise exception 'PLAN_LIMIT:% permite % vehicule', p, maxv using errcode = 'P0001';
  end if;
  if pg_column_size(new.data) > 2000000 then
    raise exception 'Prea multe date într-un singur cont' using errcode = 'P0001';
  end if;
  return new;
end;
$$;

drop trigger if exists autolazi_verifica on public.autolazi_data;
create trigger autolazi_verifica
  before insert or update on public.autolazi_data
  for each row execute function public._autolazi_verifica();


-- 5) Planul meu (aplicația îl citește pentru contul logat)
create or replace function public.autolazi_planul_meu()
returns text
language sql stable security definer
set search_path = public
as $$
  select _autolazi_plan(auth.uid());
$$;
revoke all on function public.autolazi_planul_meu() from public, anon;
grant execute on function public.autolazi_planul_meu() to authenticated;

-- Gata. Dacă vezi „Success. No rows returned”, totul e în regulă.
