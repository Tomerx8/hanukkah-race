-- =====================================================================
--  מרוץ חנוכה – Hanukkah QR race
--  Database setup for Supabase. Paste this whole file into
--  Supabase -> SQL Editor -> New query, and press "Run".
--  It is safe to run again: it never deletes your teams or riddles.
-- =====================================================================

create schema if not exists game;
revoke all on schema game from public;

-- ---------- helpers --------------------------------------------------

create or replace function game.new_token() returns text
language sql volatile as $$
  select substr(replace(gen_random_uuid()::text, '-', ''), 1, 16)
$$;

-- Normalise an answer: lower case, no niqqud, final letters -> regular,
-- and drop everything that is not a letter or a digit.
create or replace function game.norm(t text) returns text
language sql immutable as $$
  select regexp_replace(
           translate(lower(regexp_replace(coalesce(t, ''), '[֑-ׇ]', '', 'g')),
                     'ךםןףץ', 'כמנפצ'),
           '[^a-z0-9א-ת]', '', 'g')
$$;

-- An answer is right if it matches one accepted variant after normalising.
-- A variant made only of digits also matches any answer whose digits are
-- exactly that number ("בשנת 63" matches "63").
create or replace function game.answer_ok(p_input text, p_answers text[]) returns boolean
language sql immutable as $$
  select exists (
    select 1 from unnest(coalesce(p_answers, '{}')) a
    where game.norm(a) <> ''
      and (game.norm(a) = game.norm(p_input)
           or (a ~ '^\s*\d+\s*$' and regexp_replace(coalesce(p_input, ''), '\D', '', 'g') = trim(a)))
  )
$$;

-- ---------- tables ---------------------------------------------------

create table if not exists game.settings (
  id               int primary key default 1 check (id = 1),
  game_state       text not null default 'waiting' check (game_state in ('waiting', 'running', 'ended')),
  board_mode       text not null default 'lobby' check (board_mode in ('lobby', 'live', 'blackout', 'results')),
  started_at       timestamptz,
  ended_at         timestamptz,
  admin_hash       text,
  final_riddle     text not null default '',
  finish_token     text not null default game.new_token(),
  lockout_base_sec int not null default 20,
  lockout_max_sec  int not null default 300
);

create table if not exists game.stations (
  id              serial primary key,
  position        int not null default 0,
  name            text not null,
  token           text not null unique default game.new_token(),
  kind            text not null default 'text' check (kind in ('text', 'photo')),
  question        text not null default '',
  answers         text[] not null default '{}',
  location_riddle text not null default '',
  active          boolean not null default true
);

create table if not exists game.teams (
  id           serial primary key,
  name         text not null,
  pin          text not null,
  secret       text not null unique default game.new_token() || game.new_token(),
  start_offset int,
  route        int[],
  step         int not null default 0,
  finished_at  timestamptz,
  penalty_sec  int not null default 0,
  created_at   timestamptz not null default now()
);
create unique index if not exists teams_name_uq on game.teams (lower(name));

create table if not exists game.progress (
  team_id      int references game.teams on delete cascade,
  station_id   int references game.stations on delete cascade,
  wrong_count  int not null default 0,
  locked_until timestamptz,
  solved_at    timestamptz,
  skipped      boolean not null default false,
  primary key (team_id, station_id)
);

create table if not exists game.attempts (
  id         bigserial primary key,
  team_id    int references game.teams on delete cascade,
  station_id int references game.stations on delete cascade,
  answer     text,
  correct    boolean,
  at         timestamptz not null default now()
);

create table if not exists game.photos (
  id          uuid primary key default gen_random_uuid(),
  team_id     int references game.teams on delete cascade,
  station_id  int references game.stations on delete cascade,
  path        text not null,
  uploaded    boolean not null default false,
  verdict     text not null default 'pending' check (verdict in ('pending', 'ok', 'penalty')),
  penalty_sec int not null default 0,
  created_at  timestamptz not null default now()
);

revoke all on all tables in schema game from public;

-- ---------- seed content (placeholders – edit them on the admin page) --

insert into game.settings (id, final_riddle) values (1,
  'כל הכבוד! עברתם את כל התחנות. עכשיו חזרו למקום שבו כל ישיבה מתחילה ונגמרת: הקומה של עופר, החדר עם השולחן הגדול. סרקו שם את קוד הסיום כדי לעצור את השעון!')
on conflict (id) do nothing;

insert into game.stations (position, name, kind, question, answers, location_riddle)
select * from (values
  (1, 'קומה 30 – חדר המדרגות', 'text',
   '[טיוטה] באיזו שנה לפני הספירה הסתיימה שושלת החשמונאים? הוסיפו לשנה את מספר הקומות בבניין, וכתבו את התוצאה.',
   array['100'],
   '[טיוטה] הכי גבוה שאפשר להגיע ברגל: בין המדרגות, שלוש קומות מעל השולחן שלכם.'),
  (2, 'קומה 27 – המשרד של עופר', 'text',
   '[טיוטה] איזה אנטיוכוס נלחם במכבים, אם שמו האמצעי הוא כשם הדוכן שמוכר סלט ראגו בקונטיינרים? כתבו את המספר שלו.',
   array['4', 'הרביעי', 'אנטיוכוס הרביעי', 'iv'],
   '[טיוטה] מי שמחזיק את המפתחות של כולנו יושב כאן. חפשו את הדלת שלו.'),
  (3, 'קומה 27 – חדר הישיבות', 'photo',
   '[טיוטה] צרו יחד חנוכייה אנושית: עמדו בשורה לפי הגובה, כשהגבוה ביותר הוא השמש. צלמו והעלו את התמונה.',
   array[]::text[],
   '[טיוטה] כאן מקבלים את ההחלטות הגדולות, סביב השולחן הכי ארוך בקומה.'),
  (4, 'קומה 25 – חלל הקפסולה', 'text',
   '[טיוטה] איזו פעילות עשינו בחנוכה בשנה שעברה?',
   array['לעדכן'],
   '[טיוטה] כמו בחללית: מקום קטן וסגור לשיחה אחת. שתי קומות מתחת לחדר הישיבות.'),
  (5, 'קומה 25 – חלל הממ"ד', 'text',
   '[טיוטה] מה פירוש האות ג׳ על הסביבון?',
   array['גדול'],
   '[טיוטה] כשיש אזעקה, כולם רצים לכאן.'),
  (6, 'קומה 22 – חדר המדרגות', 'text',
   '[טיוטה] כמה נרות מדליקים בסך הכול בכל שמונת ימי חנוכה, כולל השמש? הוסיפו את מספר הקומה שבה אתם עומדים.',
   array['66'],
   '[טיוטה] 22 מדרגות של אור: חפשו בין הקומות, שלוש קומות מתחת לממ"ד.'),
  (7, 'קומה 0 – עמדת השומר', 'text',
   '[טיוטה] על הסביבון בארץ כתוב "נס גדול היה פה". מה המילה האחרונה בחוץ לארץ?',
   array['שם'],
   '[טיוטה] כמו המכבים ששמרו על המקדש, מישהו שומר עלינו בכניסה.'),
  (8, 'קומה ‎-1 – המקלחות בחניון', 'text',
   '[טיוטה] כמה ימים דלק פך השמן לפי הסיפור? כפלו במספר הצוותים במשחק.',
   array['88'],
   '[טיוטה] אחרי ריצה טובה צריך להתרענן. רדו מתחת לקרקע, איפה שהמכוניות ישנות.')
) v(position, name, kind, question, answers, location_riddle)
where not exists (select 1 from game.stations);

-- ---------- internal game logic ----------------------------------------

create or replace function game.team_for(p_secret text, p_lock boolean default false)
returns game.teams language plpgsql as $$
declare t game.teams;
begin
  if p_lock then
    select * into t from game.teams where secret = p_secret for update;
  else
    select * into t from game.teams where secret = p_secret;
  end if;
  if t.id is null then raise exception 'BAD_TEAM'; end if;
  return t;
end $$;

create or replace function game.penalty_total(p_team int) returns int
language sql stable as $$
  select coalesce((select penalty_sec from game.teams where id = p_team), 0)
       + coalesce((select sum(penalty_sec) from game.photos where team_id = p_team), 0)::int
$$;

create or replace function game.stage(t game.teams) returns text
language plpgsql stable as $$
declare s game.settings; n int;
begin
  select * into s from game.settings where id = 1;
  n := coalesce(array_length(t.route, 1), 0);
  if s.game_state = 'waiting' or t.route is null then return 'waiting'; end if;
  if t.finished_at is not null then return 'finished'; end if;
  if s.game_state = 'ended' then return 'ended'; end if;
  if t.step >= n then return 'final'; end if;
  return 'riddle';
end $$;

create or replace function game.team_json(p_team_id int) returns jsonb
language plpgsql stable as $$
declare
  t game.teams; s game.settings; n int; st text; riddle text; stations jsonb;
begin
  select * into t from game.teams where id = p_team_id;
  select * into s from game.settings where id = 1;
  n := coalesce(array_length(t.route, 1), 0);
  st := game.stage(t);
  if st = 'riddle' then
    select location_riddle into riddle from game.stations where id = t.route[t.step + 1];
  elsif st = 'final' then
    riddle := s.final_riddle;
  end if;
  return jsonb_build_object(
    'team', t.name,
    'game_state', s.game_state,
    'started_at', s.started_at,
    'ended_at', s.ended_at,
    'now', now(),
    'total', n,
    'done', least(t.step, n),
    'stage', st,
    'riddle', riddle,
    'finished_at', t.finished_at,
    'penalty_sec', game.penalty_total(t.id)
  );
end $$;

-- Where does this team stand relative to a scanned QR token?
create or replace function game.scan_json(t game.teams, p_token text) returns jsonb
language plpgsql stable as $$
declare
  s game.settings; st text; stn game.stations; p game.progress; lock_left int;
begin
  if p_token is null or p_token = '' then return null; end if;
  select * into s from game.settings where id = 1;
  st := game.stage(t);

  if p_token = s.finish_token then
    if st = 'finished' then return jsonb_build_object('status', 'finished'); end if;
    if st = 'waiting' then return jsonb_build_object('status', 'not_started'); end if;
    if st = 'ended' then return jsonb_build_object('status', 'ended'); end if;
    if st = 'final' then return jsonb_build_object('status', 'finish_ready'); end if;
    return jsonb_build_object('status', 'finish_early');
  end if;

  select * into stn from game.stations where token = p_token;
  if stn.id is null then return jsonb_build_object('status', 'unknown'); end if;
  if st = 'waiting' then return jsonb_build_object('status', 'not_started'); end if;
  if st in ('ended', 'finished') then return jsonb_build_object('status', st); end if;

  if st = 'riddle' and stn.id = t.route[t.step + 1] then
    select * into p from game.progress where team_id = t.id and station_id = stn.id;
    lock_left := greatest(0, ceil(extract(epoch from (coalesce(p.locked_until, now()) - now()))))::int;
    return jsonb_build_object(
      'status', 'question',
      'kind', stn.kind,
      'question', stn.question,
      'number', t.step + 1,
      'wrong_count', coalesce(p.wrong_count, 0),
      'lock_left', lock_left);
  end if;

  if stn.id = any (t.route[1:t.step]) then
    return jsonb_build_object('status', 'done');
  end if;
  return jsonb_build_object('status', 'not_yours');
end $$;

-- ---------- player API -------------------------------------------------

create or replace function public.list_teams() returns jsonb
language sql stable security definer set search_path = game, public as $$
  select coalesce(jsonb_agg(name order by name), '[]'::jsonb) from game.teams
$$;

create or replace function public.join_team(p_name text, p_pin text, p_create boolean)
returns jsonb language plpgsql security definer set search_path = game, public as $$
declare t game.teams; v_name text := btrim(coalesce(p_name, ''));
begin
  if p_pin is null or p_pin !~ '^\d{4}$' then raise exception 'BAD_PIN_FORMAT'; end if;
  if p_create then
    if length(v_name) < 2 or length(v_name) > 30 then raise exception 'BAD_NAME'; end if;
    if (select game_state from game.settings where id = 1) <> 'waiting' then
      raise exception 'REGISTRATION_CLOSED';
    end if;
    if exists (select 1 from game.teams where lower(name) = lower(v_name)) then
      raise exception 'NAME_TAKEN';
    end if;
    insert into game.teams (name, pin) values (v_name, p_pin) returning * into t;
  else
    select * into t from game.teams where lower(name) = lower(v_name);
    if t.id is null then raise exception 'NO_SUCH_TEAM'; end if;
    if t.pin <> p_pin then raise exception 'BAD_PIN'; end if;
  end if;
  return jsonb_build_object('secret', t.secret, 'name', t.name);
end $$;

-- The phone's main call: team state, plus what a scanned QR means for this team.
-- Scanning the finish QR while on the final riddle stops the team's clock.
create or replace function public.scan(p_secret text, p_token text default null)
returns jsonb language plpgsql security definer set search_path = game, public as $$
declare t game.teams; sc jsonb;
begin
  t := game.team_for(p_secret, true);
  sc := game.scan_json(t, p_token);
  if sc->>'status' = 'finish_ready' then
    update game.teams set finished_at = now() where id = t.id;
    sc := jsonb_build_object('status', 'just_finished');
  end if;
  return game.team_json(t.id) || jsonb_build_object('scan', sc);
end $$;

create or replace function public.submit_answer(p_secret text, p_token text, p_answer text)
returns jsonb language plpgsql security definer set search_path = game, public as $$
declare
  t game.teams; s game.settings; sc jsonb; stn game.stations; p game.progress;
  ok boolean; lock_sec int;
begin
  t := game.team_for(p_secret, true);
  sc := game.scan_json(t, p_token);
  if sc->>'status' is distinct from 'question' or sc->>'kind' <> 'text' then
    return game.team_json(t.id) || jsonb_build_object('result', 'stale', 'scan', sc);
  end if;
  select * into s from game.settings where id = 1;
  select * into stn from game.stations where token = p_token;
  insert into game.progress (team_id, station_id) values (t.id, stn.id) on conflict do nothing;
  select * into p from game.progress where team_id = t.id and station_id = stn.id for update;

  if p.locked_until is not null and p.locked_until > now() then
    return game.team_json(t.id) || jsonb_build_object('result', 'locked', 'scan', sc);
  end if;

  ok := game.answer_ok(p_answer, stn.answers);
  insert into game.attempts (team_id, station_id, answer, correct)
  values (t.id, stn.id, left(p_answer, 200), ok);

  if ok then
    update game.progress set solved_at = now(), locked_until = null
     where team_id = t.id and station_id = stn.id;
    update game.teams set step = step + 1 where id = t.id;
    return game.team_json(t.id) || jsonb_build_object('result', 'correct');
  end if;

  -- First miss is free (typos happen); after that the wait doubles each time.
  lock_sec := case when p.wrong_count = 0 then 0
                   else least(s.lockout_max_sec, s.lockout_base_sec * power(2, p.wrong_count - 1)::int) end;
  update game.progress
     set wrong_count = wrong_count + 1,
         locked_until = case when lock_sec > 0 then now() + make_interval(secs => lock_sec) end
   where team_id = t.id and station_id = stn.id;
  t := game.team_for(p_secret);
  return game.team_json(t.id) || jsonb_build_object('result', 'wrong', 'scan', game.scan_json(t, p_token));
end $$;

-- Photo tasks unlock at once; the photo uploads in the background and is judged later.
create or replace function public.submit_photo(p_secret text, p_token text)
returns jsonb language plpgsql security definer set search_path = game, public as $$
declare t game.teams; sc jsonb; stn game.stations; ph game.photos;
begin
  t := game.team_for(p_secret, true);
  sc := game.scan_json(t, p_token);
  if sc->>'status' is distinct from 'question' or sc->>'kind' <> 'photo' then
    return game.team_json(t.id) || jsonb_build_object('result', 'stale', 'scan', sc);
  end if;
  select * into stn from game.stations where token = p_token;
  insert into game.photos (team_id, station_id, path)
  values (t.id, stn.id, 'team' || t.id || '/' || stn.id || '-' || game.new_token() || '.jpg')
  returning * into ph;
  insert into game.progress (team_id, station_id, solved_at) values (t.id, stn.id, now())
  on conflict (team_id, station_id) do update set solved_at = now();
  update game.teams set step = step + 1 where id = t.id;
  return game.team_json(t.id)
    || jsonb_build_object('result', 'correct', 'photo_id', ph.id, 'photo_path', ph.path);
end $$;

create or replace function public.photo_uploaded(p_secret text, p_photo_id uuid)
returns jsonb language plpgsql security definer set search_path = game, public as $$
declare t game.teams;
begin
  t := game.team_for(p_secret);
  update game.photos set uploaded = true where id = p_photo_id and team_id = t.id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- TV board ---------------------------------------------------

create or replace function public.board() returns jsonb
language plpgsql stable security definer set search_path = game, public as $$
declare s game.settings; teams jsonb;
begin
  select * into s from game.settings where id = 1;
  if s.board_mode = 'blackout' then
    teams := '[]'::jsonb;
  elsif s.board_mode = 'results' then
    select coalesce(jsonb_agg(r order by r.rk), '[]') into teams from (
      select row_number() over (order by (finished_at is null), total_sec, step desc) rk,
             name, total_sec, penalty_sec, finished_at is not null as finished
      from (
        select t.name, t.step, t.finished_at, game.penalty_total(t.id) penalty_sec,
               extract(epoch from (t.finished_at - s.started_at))::int + game.penalty_total(t.id) total_sec
        from game.teams t
      ) x
    ) r;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
             'name', t.name,
             'finished', s.board_mode = 'live' and t.finished_at is not null,
             'pct', case when s.board_mode <> 'live' or t.route is null then 0
                         when t.finished_at is not null then 100
                         else round(100.0 * t.step / (array_length(t.route, 1) + 1)) end
           ) order by t.id), '[]') into teams
    from game.teams t;
  end if;
  return jsonb_build_object('mode', s.board_mode, 'game_state', s.game_state,
                            'started_at', s.started_at, 'now', now(),
                            'team_count', (select count(*) from game.teams), 'teams', teams);
end $$;

-- ---------- admin API (every call needs the admin password) ------------

create or replace function game.hash_pw(p text) returns text
language sql immutable as $$ select encode(sha256(convert_to('hanukkah-race:' || p, 'UTF8')), 'hex') $$;

create or replace function game.assert_admin(p_pw text) returns void
language plpgsql as $$
begin
  if p_pw is null or (select admin_hash from game.settings where id = 1) is distinct from game.hash_pw(p_pw) then
    raise exception 'BAD_PASSWORD';
  end if;
end $$;

-- The first password ever used becomes the admin password.
create or replace function public.admin_login(p_pw text) returns jsonb
language plpgsql security definer set search_path = game, public as $$
begin
  if (select admin_hash from game.settings where id = 1) is null then
    if length(coalesce(p_pw, '')) < 6 then raise exception 'PASSWORD_TOO_SHORT'; end if;
    update game.settings set admin_hash = game.hash_pw(p_pw) where id = 1;
    return jsonb_build_object('ok', true, 'created', true);
  end if;
  perform game.assert_admin(p_pw);
  return jsonb_build_object('ok', true, 'created', false);
end $$;

create or replace function public.admin_overview(p_pw text) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare s game.settings;
begin
  perform game.assert_admin(p_pw);
  select * into s from game.settings where id = 1;
  return jsonb_build_object(
    'now', now(),
    'settings', to_jsonb(s) - 'admin_hash',
    'stations', (select coalesce(jsonb_agg(to_jsonb(x) order by x.position, x.id), '[]') from game.stations x),
    'teams', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', t.id, 'name', t.name, 'pin', t.pin, 'start_offset', t.start_offset,
        'route', t.route, 'step', t.step, 'total', coalesce(array_length(t.route, 1), 0),
        'stage', game.stage(t),
        'current_station', t.route[t.step + 1],
        'finished_at', t.finished_at,
        'elapsed_sec', case when t.finished_at is not null then extract(epoch from (t.finished_at - s.started_at))::int end,
        'penalty_sec', t.penalty_sec,
        'penalty_total', game.penalty_total(t.id),
        'wrong_total', (select coalesce(sum(wrong_count), 0) from game.progress p where p.team_id = t.id),
        'locked_until', (select max(locked_until) from game.progress p where p.team_id = t.id and locked_until > now())
      ) order by t.id), '[]') from game.teams t),
    'photos', (select coalesce(jsonb_agg(jsonb_build_object(
        'id', ph.id, 'team', t.name, 'station', st.name, 'path', ph.path, 'uploaded', ph.uploaded,
        'verdict', ph.verdict, 'penalty_sec', ph.penalty_sec, 'created_at', ph.created_at
      ) order by ph.created_at desc), '[]')
      from game.photos ph join game.teams t on t.id = ph.team_id join game.stations st on st.id = ph.station_id),
    'attempts', (select coalesce(jsonb_agg(a order by a.at desc), '[]') from (
        select at.at, t.name team, st.name station, at.answer, at.correct
        from game.attempts at join game.teams t on t.id = at.team_id join game.stations st on st.id = at.station_id
        order by at.at desc limit 40) a)
  );
end $$;

create or replace function public.admin_set_mode(p_pw text, p_mode text) returns jsonb
language plpgsql security definer set search_path = game, public as $$
begin
  perform game.assert_admin(p_pw);
  update game.settings set board_mode = p_mode where id = 1;
  return jsonb_build_object('ok', true);
end $$;

-- Ready, set, go: give every team its rotated route and start the clock.
create or replace function public.admin_start(p_pw text) returns jsonb
language plpgsql security definer set search_path = game, public as $$
declare ids int[]; n int; t record; off int;
begin
  perform game.assert_admin(p_pw);
  if (select game_state from game.settings where id = 1) <> 'waiting' then raise exception 'ALREADY_STARTED'; end if;
  select array_agg(id order by position, id) into ids from game.stations where active;
  n := coalesce(array_length(ids, 1), 0);
  if n = 0 then raise exception 'NO_STATIONS'; end if;
  if not exists (select 1 from game.teams) then raise exception 'NO_TEAMS'; end if;
  for t in select id, start_offset, (row_number() over (order by id) - 1)::int rn from game.teams loop
    off := ((coalesce(t.start_offset - 1, t.rn) % n) + n) % n;
    update game.teams set route = ids[off + 1:n] || ids[1:off], step = 0, finished_at = null where id = t.id;
  end loop;
  update game.settings set game_state = 'running', started_at = now(), ended_at = null,
                           board_mode = 'live' where id = 1;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_end(p_pw text) returns jsonb
language plpgsql security definer set search_path = game, public as $$
begin
  perform game.assert_admin(p_pw);
  update game.settings set game_state = 'ended', ended_at = now() where id = 1 and game_state = 'running';
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_reset(p_pw text, p_delete_teams boolean) returns jsonb
language plpgsql security definer set search_path = game, public as $$
begin
  perform game.assert_admin(p_pw);
  delete from game.attempts where true;
  delete from game.photos where true;
  delete from game.progress where true;
  if p_delete_teams then
    delete from game.teams where true;
  else
    update game.teams set route = null, step = 0, finished_at = null, penalty_sec = 0 where true;
  end if;
  update game.settings set game_state = 'waiting', board_mode = 'lobby', started_at = null, ended_at = null where id = 1;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_save_settings(p_pw text, p_final_riddle text, p_lockout_base int, p_lockout_max int)
returns jsonb language plpgsql security definer set search_path = game, public as $$
begin
  perform game.assert_admin(p_pw);
  update game.settings set final_riddle = coalesce(p_final_riddle, ''),
         lockout_base_sec = greatest(0, p_lockout_base), lockout_max_sec = greatest(0, p_lockout_max)
   where id = 1;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_save_station(
  p_pw text, p_id int, p_position int, p_name text, p_kind text, p_question text,
  p_answers text[], p_location_riddle text, p_active boolean)
returns jsonb language plpgsql security definer set search_path = game, public as $$
declare v_id int;
begin
  perform game.assert_admin(p_pw);
  if p_id is null then
    insert into game.stations (position, name, kind, question, answers, location_riddle, active)
    values (coalesce(p_position, 0), p_name, p_kind, coalesce(p_question, ''),
            coalesce(p_answers, '{}'), coalesce(p_location_riddle, ''), coalesce(p_active, true))
    returning id into v_id;
  else
    update game.stations set position = coalesce(p_position, position), name = p_name, kind = p_kind,
           question = coalesce(p_question, ''), answers = coalesce(p_answers, '{}'),
           location_riddle = coalesce(p_location_riddle, ''), active = coalesce(p_active, active)
     where id = p_id returning id into v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

create or replace function public.admin_delete_station(p_pw text, p_id int) returns jsonb
language plpgsql security definer set search_path = game, public as $$
begin
  perform game.assert_admin(p_pw);
  if (select game_state from game.settings where id = 1) = 'running' then raise exception 'GAME_RUNNING'; end if;
  delete from game.stations where id = p_id;
  return jsonb_build_object('ok', true);
end $$;

-- Fixes during the game: skip a station whose QR went missing, step back,
-- clear a lockout, set the start station, add a penalty, mark finished, delete.
create or replace function public.admin_team(p_pw text, p_team_id int, p_action text, p_value int default null)
returns jsonb language plpgsql security definer set search_path = game, public as $$
declare t game.teams;
begin
  perform game.assert_admin(p_pw);
  select * into t from game.teams where id = p_team_id for update;
  if t.id is null then raise exception 'NO_SUCH_TEAM'; end if;
  case p_action
    when 'skip' then
      if t.route is not null and t.step < array_length(t.route, 1) then
        insert into game.progress (team_id, station_id, solved_at, skipped)
        values (t.id, t.route[t.step + 1], now(), true)
        on conflict (team_id, station_id) do update set solved_at = now(), skipped = true;
        update game.teams set step = step + 1 where id = t.id;
      end if;
    when 'back' then
      update game.teams set step = greatest(0, step - 1), finished_at = null where id = t.id;
    when 'unlock' then
      update game.progress set locked_until = null where team_id = t.id;
    when 'offset' then
      update game.teams set start_offset = p_value where id = t.id;
    when 'penalty' then
      update game.teams set penalty_sec = coalesce(p_value, 0) where id = t.id;
    when 'finish' then
      update game.teams set finished_at = now() where id = t.id;
    when 'unfinish' then
      update game.teams set finished_at = null where id = t.id;
    when 'delete' then
      delete from game.teams where id = t.id;
    else
      raise exception 'BAD_ACTION';
  end case;
  return jsonb_build_object('ok', true);
end $$;

create or replace function public.admin_judge(p_pw text, p_photo_id uuid, p_verdict text, p_penalty_sec int)
returns jsonb language plpgsql security definer set search_path = game, public as $$
begin
  perform game.assert_admin(p_pw);
  update game.photos set verdict = p_verdict,
         penalty_sec = case when p_verdict = 'penalty' then coalesce(p_penalty_sec, 0) else 0 end
   where id = p_photo_id;
  return jsonb_build_object('ok', true);
end $$;

-- ---------- permissions ------------------------------------------------

revoke execute on all functions in schema game from public;
do $$
declare f text;
begin
  foreach f in array array[
    'list_teams()', 'join_team(text,text,boolean)', 'scan(text,text)',
    'submit_answer(text,text,text)', 'submit_photo(text,text)', 'photo_uploaded(text,uuid)', 'board()',
    'admin_login(text)', 'admin_overview(text)', 'admin_set_mode(text,text)', 'admin_start(text)',
    'admin_end(text)', 'admin_reset(text,boolean)', 'admin_save_settings(text,text,int,int)',
    'admin_save_station(text,int,int,text,text,text,text[],text,boolean)', 'admin_delete_station(text,int)',
    'admin_team(text,int,text,int)', 'admin_judge(text,uuid,text,int)']
  loop
    execute format('revoke all on function public.%s from public', f);
    execute format('grant execute on function public.%s to anon, authenticated', f);
  end loop;
end $$;

-- ---------- photo storage ----------------------------------------------
-- A public bucket: file names are random, and players can only add files.

insert into storage.buckets (id, name, public) values ('photos', 'photos', true)
on conflict (id) do nothing;

drop policy if exists "race photos upload" on storage.objects;
create policy "race photos upload" on storage.objects
  for insert to anon, authenticated with check (bucket_id = 'photos');

notify pgrst, 'reload schema';
