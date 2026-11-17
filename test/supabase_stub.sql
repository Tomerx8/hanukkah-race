do $$ begin
  if not exists (select 1 from pg_roles where rolname='anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname='authenticated') then create role authenticated nologin; end if;
end $$;
create schema if not exists storage;
create table if not exists storage.buckets (id text primary key, name text, public boolean);
create table if not exists storage.objects (id serial primary key, bucket_id text, name text);
alter table storage.objects enable row level security;
