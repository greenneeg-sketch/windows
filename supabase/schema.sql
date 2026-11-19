-- 유리창 (yurichang) Supabase schema — applied as migration "yurichang_core"
create extension if not exists pgcrypto with schema extensions;

create table public.notes (
  id uuid primary key default gen_random_uuid(),
  region text not null check (region in ('mapo','busan','gangneung','jeju')),
  x real not null check (x between -2 and 2),
  y real not null check (y between 0.5 and 3),
  r real not null default 0 check (r between -0.5 and 0.5),
  c text not null check (c in ('y','p','m','b','o')),
  strokes jsonb not null default '[]'::jsonb,
  texts jsonb not null default '[]'::jsonb,
  hearts int not null default 0,
  reports int not null default 0,
  hidden boolean not null default false,
  device text not null,
  token_hash text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index notes_region_created on public.notes (region, created_at desc) where not hidden;
create index notes_device_created on public.notes (device, created_at desc);

create table public.note_reports (
  note_id uuid references public.notes(id) on delete cascade,
  device text not null,
  reason text not null check (reason in ('abuse','spam','privacy','sexual')),
  created_at timestamptz not null default now(),
  primary key (note_id, device)
);
create table public.note_hearts (
  note_id uuid references public.notes(id) on delete cascade,
  device text not null,
  created_at timestamptz not null default now(),
  primary key (note_id, device)
);

alter table public.notes enable row level security;
alter table public.note_reports enable row level security;
alter table public.note_hearts enable row level security;

-- everyone can read visible notes, but never the device id or token hash
revoke all on public.notes from anon, authenticated;
grant select (id, region, x, y, r, c, strokes, texts, hearts, created_at, updated_at) on public.notes to anon, authenticated;
create policy "visible notes are public" on public.notes for select to anon, authenticated using (not hidden);
revoke all on public.note_reports from anon, authenticated;
revoke all on public.note_hearts from anon, authenticated;

-- word filter (mirrors the one in the page; the server is the one that counts)
create or replace function public.yc_bad_text(t text) returns text
language plpgsql immutable set search_path = public as $$
declare
  n text;
  w text;
  bad text[] := array['시발','씨발','씨바','씨빨','시빨','씌발','씨팔','시팔','ㅅㅂ','ㅆㅂ','병신','븅신','빙신','ㅂㅅ','좆','존나','졸라','ㅈㄴ','개새','개색','개세끼','개쉐','쌔끼','새끼야',
    '미친놈','미친년','미친새','지랄','ㅈㄹ','엿먹','닥쳐','꺼져','니애미','니미럴','느금','애미뒤','애비뒤','섹스','보지','자지','썅','쌍년','창녀','걸레년','등신','뒤져','디져라',
    '한남충','김치녀','틀딱','급식충','짱깨','쪽바리','fuck','shit','bitch','asshole','sex'];
  allow text[] := array['시바견','시바이누','강아지새끼','고양이새끼'];
begin
  if t is null then return null; end if;
  n := lower(regexp_replace(t, '[\s0-9_.,!?~^*+=/\\|''"`:;()\[\]{}<>@#$%&♥♡★☆-]', '', 'g'));
  foreach w in array allow loop n := replace(n, w, ''); end loop;
  foreach w in array bad loop
    if position(w in n) > 0 then return 'abuse'; end if;
  end loop;
  if t ~* '(https?://|www\.|\.com\M|\.kr\M|\.net\M|open\.kakao|오픈채팅|오픈톡|카톡\s*(아이디|id)|텔레그램|t\.me/|인스타\s*@)' then return 'link'; end if;
  if t ~ '01[016789][\s.-]?[0-9]{3,4}[\s.-]?[0-9]{4}' or regexp_replace(t, '[\s.-]', '', 'g') ~ '[0-9]{9,}' then return 'phone'; end if;
  return null;
end $$;

-- validate the drawing payload: size, shape, and every text item
create or replace function public.yc_check_payload(p_strokes jsonb, p_texts jsonb) returns void
language plpgsql set search_path = public as $$
declare item jsonb; why text;
begin
  if jsonb_typeof(p_strokes) <> 'array' or jsonb_typeof(p_texts) <> 'array' then raise exception 'bad_payload'; end if;
  if jsonb_array_length(p_strokes) = 0 and jsonb_array_length(p_texts) = 0 then raise exception 'empty'; end if;
  if jsonb_array_length(p_strokes) > 300 or jsonb_array_length(p_texts) > 15 then raise exception 'too_big'; end if;
  if length(p_strokes::text) > 120000 then raise exception 'too_big'; end if;
  for item in select * from jsonb_array_elements(p_texts) loop
    if jsonb_typeof(item->'t') <> 'string' or char_length(item->>'t') > 20 then raise exception 'bad_payload'; end if;
    why := public.yc_bad_text(item->>'t');
    if why is not null then raise exception 'filtered_%', why; end if;
  end loop;
end $$;

create or replace function public.post_note(p_device text, p_region text, p_x real, p_y real, p_r real, p_c text, p_strokes jsonb, p_texts jsonb)
returns json language plpgsql security definer set search_path = public, extensions as $$
declare
  day_start timestamptz := date_trunc('day', now() at time zone 'Asia/Seoul') at time zone 'Asia/Seoul';
  used int; tok text; new_id uuid;
begin
  if p_device is null or char_length(p_device) < 16 or char_length(p_device) > 64 then raise exception 'bad_device'; end if;
  perform public.yc_check_payload(p_strokes, p_texts);
  select count(*) into used from public.notes where device = p_device and created_at >= day_start;
  if used >= 3 then raise exception 'daily_limit'; end if;
  if (select count(*) from public.notes where created_at > now() - interval '1 minute') > 60 then raise exception 'busy'; end if;
  tok := encode(gen_random_bytes(18), 'hex');
  insert into public.notes(region, x, y, r, c, strokes, texts, device, token_hash)
  values (p_region, p_x, p_y, greatest(-0.5, least(0.5, coalesce(p_r,0))), p_c, p_strokes, p_texts, p_device, encode(digest(tok, 'sha256'), 'hex'))
  returning id into new_id;
  return json_build_object('id', new_id, 'token', tok, 'left', 2 - used);
end $$;

create or replace function public.edit_note(p_id uuid, p_token text, p_c text, p_strokes jsonb, p_texts jsonb)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  perform public.yc_check_payload(p_strokes, p_texts);
  update public.notes set c = p_c, strokes = p_strokes, texts = p_texts, updated_at = now()
   where id = p_id and token_hash = encode(digest(coalesce(p_token,''), 'sha256'), 'hex');
  if not found then raise exception 'not_owner'; end if;
end $$;

create or replace function public.delete_note(p_id uuid, p_token text)
returns void language plpgsql security definer set search_path = public, extensions as $$
begin
  delete from public.notes where id = p_id and token_hash = encode(digest(coalesce(p_token,''), 'sha256'), 'hex');
  if not found then raise exception 'not_owner'; end if;
end $$;

-- three different reporters take a note down for everyone
create or replace function public.report_note(p_id uuid, p_device text, p_reason text)
returns void language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_device is null or char_length(p_device) < 16 then raise exception 'bad_device'; end if;
  insert into public.note_reports(note_id, device, reason) values (p_id, p_device, p_reason) on conflict do nothing;
  select count(*) into n from public.note_reports where note_id = p_id;
  update public.notes set reports = n, hidden = (n >= 3) or hidden where id = p_id;
end $$;

create or replace function public.heart_note(p_id uuid, p_device text)
returns int language plpgsql security definer set search_path = public as $$
declare n int;
begin
  if p_device is null or char_length(p_device) < 16 then raise exception 'bad_device'; end if;
  insert into public.note_hearts(note_id, device) values (p_id, p_device) on conflict do nothing;
  select count(*) into n from public.note_hearts where note_id = p_id;
  update public.notes set hearts = n where id = p_id;
  return n;
end $$;

revoke all on function public.post_note, public.edit_note, public.delete_note, public.report_note, public.heart_note, public.yc_bad_text, public.yc_check_payload from public;
grant execute on function public.post_note, public.edit_note, public.delete_note, public.report_note, public.heart_note to anon, authenticated;

-- migration "yurichang_place_tag": province tag (시·도 only) on each note
alter table public.notes add column place text check (place in ('서울','부산','대구','인천','광주','대전','울산','세종','경기','강원','충북','충남','전북','전남','경북','경남','제주'));
grant select (place) on public.notes to anon, authenticated;
drop function public.post_note(text, text, real, real, real, text, jsonb, jsonb);
-- post_note is recreated with one more argument, p_place text default null, inserted into notes.place (same body otherwise)

-- migration "yurichang_admin": operator tools behind a secret key (only its SHA-256 is stored)
-- tables: admin_keys(key_hash)  — no grants to anon/authenticated
-- functions (each checks the key first, waits 0.5s on a wrong key):
--   admin_stats(p_key)                      -> totals, today, reported, hidden, per window
--   admin_list(p_key, p_filter)             -> 'reported' | 'hidden' | 'recent', with report reasons
--   admin_set_hidden(p_key, p_id, p_hidden) -> restoring also clears that note's reports
--   admin_delete(p_key, p_id)
-- To rotate the key: insert the new sha256 hex into admin_keys and delete the old row (SQL editor).

-- migration "yurichang_note_lifespan": a note stays up 30 days, +2 days per heart, at most 180 days
drop policy "visible notes are public" on public.notes;
create policy "visible notes are public" on public.notes for select to anon, authenticated
  using (not hidden and created_at > now() - make_interval(days => least(180, 30 + hearts * 2)));

-- migration "yurichang_launch_reset_ip_limit": launch reset + per-network daily limit
-- delete from public.notes;   (all test notes removed before launch)
-- notes.ip_day = sha256('yurichang|' || client_ip || '|' || seoul_date) — a per-day hash, never the raw address
-- yc_client_ip() reads cf-connecting-ip / x-forwarded-for / x-real-ip from request.headers
-- post_note: at most 3 per device and 10 per network per Seoul day
