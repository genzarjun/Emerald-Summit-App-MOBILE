-- Emerald Summit — Archie saved chat history
--
-- Each user's Archie conversations are saved to their account so they can come
-- back to them, and so organizers can see (anonymously) what people ask and
-- how Archie answers. Run after role_allowlist_setup.sql (uses is_admin()).
-- Safe to re-run.
--
-- Limits (enforced here, not just in the app):
--   * 10 chats per user — starting an 11th deletes the user's least-recently
--     used chat (the app tells users this).
--   * 15 questions per chat — a chat that full rejects more questions; the app
--     asks the user to start a new chat.
-- The app saves through archie_save_exchange() (one atomic call per question +
-- answer). Users can read and delete only their own chats. Admins never read chats
-- directly; they get question/answer pairs WITHOUT any user identity through
-- archie_recent_exchanges().

-- 1. Tables -------------------------------------------------------------------
create table if not exists public.archie_chats (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid()
                references auth.users (id) on delete cascade,
  title       text not null default '' check (char_length(title) <= 120),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create index if not exists archie_chats_user_recent_idx
  on public.archie_chats (user_id, updated_at desc);

create table if not exists public.archie_messages (
  id          bigint generated always as identity primary key, -- = order
  chat_id     uuid not null references public.archie_chats (id) on delete cascade,
  user_id     uuid not null default auth.uid()
                references auth.users (id) on delete cascade,
  role        text not null check (role in ('user', 'assistant')),
  content     text not null check (char_length(content) <= 20000),
  sources     jsonb not null default '[]'::jsonb,  -- [{title, url}]
  steps       jsonb not null default '[]'::jsonb,  -- ["Searching the web for …"]
  created_at  timestamptz not null default now()
);

create index if not exists archie_messages_chat_idx
  on public.archie_messages (chat_id, id);

-- 2. Row Level Security ----------------------------------------------------------
alter table public.archie_chats enable row level security;
alter table public.archie_messages enable row level security;

drop policy if exists "Own archie chats" on public.archie_chats;
create policy "Own archie chats"
  on public.archie_chats
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

drop policy if exists "Read own archie messages" on public.archie_messages;
create policy "Read own archie messages"
  on public.archie_messages
  for select
  to authenticated
  using (user_id = auth.uid());

-- Insert only into a chat you own. Messages are never edited; they go away
-- with their chat (cascade).
drop policy if exists "Add to own archie chats" on public.archie_messages;
create policy "Add to own archie chats"
  on public.archie_messages
  for insert
  to authenticated
  with check (
    user_id = auth.uid()
    and exists (
      select 1 from public.archie_chats c
      where c.id = chat_id and c.user_id = auth.uid()
    )
  );

grant select, insert, update, delete on public.archie_chats to authenticated;
grant select, insert on public.archie_messages to authenticated;

-- 3. Limits ---------------------------------------------------------------------
-- 15 questions per chat. Raised as a recognizable error the app maps to the
-- "conversation is too long" state.
create or replace function public.archie_enforce_chat_length()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  if new.role = 'user' and (
    select count(*) from public.archie_messages
    where chat_id = new.chat_id and role = 'user'
  ) >= 15 then
    raise exception 'archie_chat_full' using errcode = 'P0001';
  end if;
  -- Keep the chat's "last used" time current for ordering + pruning.
  update public.archie_chats set updated_at = now() where id = new.chat_id;
  return new;
end;
$$;

drop trigger if exists archie_messages_limit on public.archie_messages;
create trigger archie_messages_limit
  before insert on public.archie_messages
  for each row execute function public.archie_enforce_chat_length();

-- 10 chats per user: after a new chat is created, delete that user's chats
-- beyond the 10 most recently used (their messages cascade).
create or replace function public.archie_prune_chats()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  delete from public.archie_chats
  where user_id = new.user_id
    and id not in (
      select id from public.archie_chats
      where user_id = new.user_id
      order by updated_at desc, created_at desc
      limit 10
    );
  return null;
end;
$$;

drop trigger if exists archie_chats_prune on public.archie_chats;
create trigger archie_chats_prune
  after insert on public.archie_chats
  for each row execute function public.archie_prune_chats();

-- 4. Saving an exchange (the app's only write path) -------------------------
-- Saves one question + answer atomically: creates the chat when p_chat_id is
-- null, then both messages, in a single transaction — so a failure (e.g. the
-- 15-question limit) never leaves an empty chat behind. SECURITY INVOKER, so
-- the RLS policies above still decide what the caller may write.
-- Returns the chat id.
create or replace function public.archie_save_exchange(
  p_chat_id  uuid,
  p_title    text,
  p_question text,
  p_answer   text,
  p_sources  jsonb default '[]'::jsonb,
  p_steps    jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security invoker set search_path = public
as $$
declare
  v_chat uuid := p_chat_id;
begin
  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;
  if v_chat is null then
    insert into public.archie_chats (title)
    values (left(coalesce(p_title, ''), 120))
    returning id into v_chat;
  end if;
  insert into public.archie_messages (chat_id, role, content)
  values (v_chat, 'user', p_question);
  insert into public.archie_messages (chat_id, role, content, sources, steps)
  values (v_chat, 'assistant', p_answer,
          coalesce(p_sources, '[]'::jsonb), coalesce(p_steps, '[]'::jsonb));
  return v_chat;
end;
$$;

revoke all on function public.archie_save_exchange(uuid, text, text, text, jsonb, jsonb)
  from public, anon;
grant execute on function public.archie_save_exchange(uuid, text, text, text, jsonb, jsonb)
  to authenticated;

-- One-time cleanup: an earlier app build could create a chat whose messages
-- then failed to save, leaving empty chats in the history list.
delete from public.archie_chats c
where not exists (select 1 from public.archie_messages m where m.chat_id = c.id)
  and c.created_at < now() - interval '1 minute';

-- 5. Anonymous insights for organizers ---------------------------------------
-- Recent question → answer pairs across all users, newest first, with NO user
-- id, name, or chat id. Admin-only. Reflects deletions (a deleted chat is gone
-- from here too).
create or replace function public.archie_recent_exchanges(p_limit int default 100)
returns table (
  question     text,
  answer       text,
  source_count int,
  asked_at     timestamptz
)
language plpgsql
security definer set search_path = public
as $$
begin
  if not public.is_admin() then
    raise exception 'Admins only';
  end if;
  return query
    select q.content,
           a.content,
           jsonb_array_length(a.sources),
           a.created_at
    from public.archie_messages a
    join lateral (
      select u.content from public.archie_messages u
      where u.chat_id = a.chat_id and u.role = 'user' and u.id < a.id
      order by u.id desc
      limit 1
    ) q on true
    where a.role = 'assistant'
    order by a.id desc
    limit least(greatest(p_limit, 1), 500);
end;
$$;

revoke all on function public.archie_recent_exchanges(int) from public, anon;
grant execute on function public.archie_recent_exchanges(int) to authenticated;
