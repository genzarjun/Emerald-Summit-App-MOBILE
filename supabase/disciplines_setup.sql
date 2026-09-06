-- Emerald Summit — disciplines catalog
-- Run this in the Supabase dashboard: SQL Editor → New query → paste → Run.
--
-- The six STEAM disciplines (spec section 04). Previously hard-coded in the app
-- (lib/data/sample_data.dart); now the source of truth so admins can add/edit
-- disciplines in-app. `icon` is a STRING KEY the app maps to a Material IconData
-- (see disciplineIcon() in lib/models/models.dart) — we don't store Flutter
-- objects in the database.

-- 1. Table -------------------------------------------------------------------
create table if not exists public.disciplines (
  id          text primary key,           -- stable slug, e.g. 'techverse'
  name        text not null,
  tagline     text not null default '',
  icon        text not null default 'category',  -- key → IconData in the app
  sort_order  int  not null default 0,
  created_by  uuid references auth.users (id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- 2. Row Level Security ------------------------------------------------------
-- Everyone (even signed-out) may READ the catalog. Only admins may write; that
-- policy is added in role_allowlist_setup.sql (Phase 2), which defines the
-- public.is_admin() helper. Until then, writes happen in the dashboard.
alter table public.disciplines enable row level security;

drop policy if exists "Public read disciplines" on public.disciplines;
create policy "Public read disciplines"
  on public.disciplines for select
  to anon, authenticated
  using (true);

-- 3. Expose to the Data API (project auto-expose is OFF) ---------------------
grant select on public.disciplines to anon, authenticated;

-- 4. Keep updated_at fresh (reuses touch_updated_at from profiles_setup.sql) --
drop trigger if exists disciplines_touch_updated_at on public.disciplines;
create trigger disciplines_touch_updated_at
  before update on public.disciplines
  for each row execute function public.touch_updated_at();
