-- Freshdesk Desk. Lives in the "Moose Management - Maintenance" project (Free plan allows 2 projects;
-- Maintenance + Rates already use them). Admin only. Nothing is deleted: gone items get active = false.
-- Relies on app_role(), forbid_delete(), forbid_change() from the maintenance schema.

create table if not exists fd_items (
  uid        text primary key,            -- "<kind>:<source id>"
  kind       text not null,               -- ticket | sent | watching | spam | calendar | brief-freshdesk | brief-slack | brief-asana
  source     text not null,               -- freshdesk | slack | asana | outlook
  section    text,
  title      text not null,
  why        text,
  who        text,
  at         timestamptz,
  due_at     timestamptz,
  url        text,                        -- every item links back to where it came from
  urgency    int not null default 1,
  meta       jsonb not null default '{}'::jsonb,
  active     boolean not null default true,
  first_seen timestamptz not null default now(),
  last_seen  timestamptz not null default now()
);
create index if not exists fd_items_kind_active on fd_items (kind, active);

create table if not exists fd_drafts (
  ticket_id         bigint primary key,
  ticket_updated_at timestamptz,          -- null = stale, redraft next run
  status_update     text,
  recommendation    text,                 -- reply | close | wait | escalate
  suggested_reply   text,
  suggested_close   text,
  model             text,
  made_at           timestamptz not null default now()
);
alter table fd_drafts add column if not exists summary text;   -- two-sentence summary of the ticket

create table if not exists fd_actions (     -- append-only record of everything sent from the site
  id bigserial primary key, at timestamptz not null default now(),
  actor text, action text, ticket_id bigint, body text, ok boolean, note text
);

create table if not exists fd_runs (
  id bigserial primary key, at timestamptz not null default now(), ok boolean, detail jsonb
);

do $$ declare t text; begin
  foreach t in array array['fd_items','fd_drafts','fd_runs'] loop
    execute format('drop trigger if exists %I on %I', t || '_no_delete', t);
    execute format('create trigger %I before delete on %I for each row execute function forbid_delete()', t || '_no_delete', t);
  end loop;
end $$;
drop trigger if exists fd_actions_no_change on fd_actions;
create trigger fd_actions_no_change before update or delete on fd_actions for each row execute function forbid_change();

alter table fd_items   enable row level security;
alter table fd_drafts  enable row level security;
alter table fd_actions enable row level security;
alter table fd_runs    enable row level security;
drop policy if exists fd_admin_read on fd_items;
drop policy if exists fd_admin_read on fd_drafts;
drop policy if exists fd_admin_read on fd_actions;
drop policy if exists fd_admin_read on fd_runs;
create policy fd_admin_read on fd_items   for select to authenticated using (app_role() = 'admin');
create policy fd_admin_read on fd_drafts  for select to authenticated using (app_role() = 'admin');
create policy fd_admin_read on fd_actions for select to authenticated using (app_role() = 'admin');
create policy fd_admin_read on fd_runs    for select to authenticated using (app_role() = 'admin');

-- Upsert one kind's rows; anything of that kind not in the batch goes inactive (never deleted).
create or replace function fd_sync(p_kind text, p_rows jsonb) returns int
language plpgsql security definer set search_path = public as $$
declare n int;
begin
  insert into fd_items as f (uid, kind, source, section, title, why, who, at, due_at, url, urgency, meta, active, last_seen)
  select r->>'uid', p_kind, coalesce(r->>'source','freshdesk'), r->>'section', coalesce(nullif(r->>'title',''), '(no title)'),
         r->>'why', r->>'who', nullif(r->>'at','')::timestamptz, nullif(r->>'due_at','')::timestamptz, r->>'url',
         coalesce((r->>'urgency')::int, 1), coalesce(r->'meta', '{}'::jsonb), true, now()
  from jsonb_array_elements(p_rows) r
  on conflict (uid) do update set kind = excluded.kind, source = excluded.source, section = excluded.section,
    title = excluded.title, why = excluded.why, who = excluded.who, at = excluded.at, due_at = excluded.due_at,
    url = excluded.url, urgency = excluded.urgency, meta = excluded.meta, active = true, last_seen = now();
  get diagnostics n = row_count;
  update fd_items set active = false
   where kind = p_kind and active and uid not in (select r->>'uid' from jsonb_array_elements(p_rows) r);
  return n;
end $$;
revoke all on function fd_sync(text, jsonb) from public, anon, authenticated;
