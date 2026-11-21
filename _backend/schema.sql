-- Come Home to Each Other - two-phone sync + push notifications
-- Run once in the Supabase project that hosts the app (SQL editor or management API).
-- Tables are locked down with RLS and no policies: the app only talks to the
-- security-definer functions below, and every call needs the pair's secret token.

create table if not exists public.chte_pairs (
  id uuid primary key default gen_random_uuid(),
  token text unique not null default replace(gen_random_uuid()::text, '-', ''),
  mum_name text not null,
  daughter_name text not null,
  created_at timestamptz not null default now()
);

create table if not exists public.chte_entries (
  pair_id uuid not null references public.chte_pairs(id) on delete cascade,
  day text not null check (day ~ '^\d{4}-\d{2}-\d{2}$'),
  part text not null check (part in ('morning','evening')),
  role text not null check (role in ('mum','daughter')),
  words text not null check (char_length(words) between 1 and 2000),
  updated_at timestamptz not null default now(),
  primary key (pair_id, day, part, role)
);

create table if not exists public.chte_push_subs (
  endpoint text primary key,
  pair_id uuid not null references public.chte_pairs(id) on delete cascade,
  role text not null check (role in ('mum','daughter')),
  p256dh text not null,
  auth text not null,
  created_at timestamptz not null default now()
);

alter table public.chte_pairs enable row level security;
alter table public.chte_entries enable row level security;
alter table public.chte_push_subs enable row level security;

create or replace function public.chte_pair_id(p_token text) returns uuid
language sql stable security definer set search_path = public as $$
  select id from chte_pairs where token = p_token
$$;
revoke all on function public.chte_pair_id(text) from public, anon, authenticated;

create or replace function public.chte_create_pair(p_mum text, p_daughter text) returns text
language plpgsql security definer set search_path = public as $$
declare t text;
begin
  if coalesce(btrim(p_mum),'') = '' or coalesce(btrim(p_daughter),'') = '' then
    raise exception 'names required';
  end if;
  insert into chte_pairs (mum_name, daughter_name)
  values (left(btrim(p_mum), 40), left(btrim(p_daughter), 40))
  returning token into t;
  return t;
end $$;

create or replace function public.chte_get(p_token text) returns json
language plpgsql stable security definer set search_path = public as $$
declare pid uuid := chte_pair_id(p_token); r json;
begin
  if pid is null then return null; end if;
  select json_build_object(
    'mumName', p.mum_name,
    'daughterName', p.daughter_name,
    'entries', coalesce((select json_agg(json_build_object('day', e.day, 'part', e.part, 'role', e.role, 'words', e.words))
                         from chte_entries e where e.pair_id = pid), '[]'::json)
  ) into r from chte_pairs p where p.id = pid;
  return r;
end $$;

create or replace function public.chte_save_entry(p_token text, p_day text, p_part text, p_role text, p_words text) returns boolean
language plpgsql security definer set search_path = public as $$
declare pid uuid := chte_pair_id(p_token);
begin
  if pid is null then return false; end if;
  insert into chte_entries (pair_id, day, part, role, words)
  values (pid, p_day, p_part, p_role, left(btrim(p_words), 2000))
  on conflict (pair_id, day, part, role) do update set words = excluded.words, updated_at = now();
  return true;
end $$;

create or replace function public.chte_set_names(p_token text, p_mum text, p_daughter text) returns boolean
language plpgsql security definer set search_path = public as $$
declare pid uuid := chte_pair_id(p_token);
begin
  if pid is null or coalesce(btrim(p_mum),'') = '' or coalesce(btrim(p_daughter),'') = '' then return false; end if;
  update chte_pairs set mum_name = left(btrim(p_mum), 40), daughter_name = left(btrim(p_daughter), 40) where id = pid;
  return true;
end $$;

create or replace function public.chte_save_sub(p_token text, p_role text, p_endpoint text, p_p256dh text, p_auth text) returns boolean
language plpgsql security definer set search_path = public as $$
declare pid uuid := chte_pair_id(p_token);
begin
  if pid is null then return false; end if;
  if p_role is null or p_role not in ('mum','daughter') then return false; end if;
  -- Only the real browser notification services are accepted, so a saved address can never
  -- point the notification function at some other website.
  if p_endpoint is null or char_length(p_endpoint) > 1000 or p_endpoint !~
     '^https://(fcm\.googleapis\.com|android\.googleapis\.com|([a-z0-9-]+\.)+google\.com|([a-z0-9-]+\.)*push\.services\.mozilla\.com|([a-z0-9-]+\.)*notify\.windows\.com|([a-z0-9-]+\.)*push\.apple\.com)/'
  then return false; end if;
  if coalesce(p_p256dh,'') = '' or coalesce(p_auth,'') = '' or char_length(p_p256dh) > 200 or char_length(p_auth) > 100 then
    return false;
  end if;
  -- A phone's subscription can move to another pair only if the caller proves it is the same
  -- phone (same subscription keys). Knowing the address alone is not enough.
  insert into chte_push_subs (endpoint, pair_id, role, p256dh, auth)
  values (p_endpoint, pid, p_role, p_p256dh, p_auth)
  on conflict (endpoint) do update
    set pair_id = excluded.pair_id, role = excluded.role, p256dh = excluded.p256dh, auth = excluded.auth
    where chte_push_subs.pair_id = excluded.pair_id
       or (chte_push_subs.p256dh = excluded.p256dh and chte_push_subs.auth = excluded.auth);
  return found;
end $$;

-- "Start over": removes the pair, every word and every notification subscription, for both phones.
create or replace function public.chte_delete_pair(p_token text) returns boolean
language plpgsql security definer set search_path = public as $$
begin
  delete from chte_pairs where token = p_token;
  return found;
end $$;

grant execute on function public.chte_create_pair(text, text) to anon;
grant execute on function public.chte_get(text) to anon;
grant execute on function public.chte_save_entry(text, text, text, text, text) to anon;
grant execute on function public.chte_set_names(text, text, text) to anon;
grant execute on function public.chte_save_sub(text, text, text, text, text) to anon;
grant execute on function public.chte_delete_pair(text) to anon;
