create extension if not exists pgcrypto;

create table if not exists public.viewer_profiles (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check (char_length(name) between 1 and 32),
  avatar_url text,
  avatar_color text not null default '#e21927',
  is_kids boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.library_items (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  profile_id uuid not null references public.viewer_profiles(id) on delete cascade,
  media_key text not null,
  media jsonb not null,
  created_at timestamptz not null default now(),
  unique (profile_id, media_key)
);

create index if not exists viewer_profiles_owner_idx on public.viewer_profiles(owner_id);
create index if not exists library_items_profile_idx on public.library_items(profile_id, created_at desc);

alter table public.viewer_profiles enable row level security;
alter table public.library_items enable row level security;

revoke all on public.viewer_profiles, public.library_items from anon;
grant select, insert, update, delete on public.viewer_profiles, public.library_items to authenticated;

create policy "Owners can read viewer profiles" on public.viewer_profiles for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy "Owners can create viewer profiles" on public.viewer_profiles for insert to authenticated
  with check ((select auth.uid()) = owner_id);
create policy "Owners can update viewer profiles" on public.viewer_profiles for update to authenticated
  using ((select auth.uid()) = owner_id) with check ((select auth.uid()) = owner_id);
create policy "Owners can delete viewer profiles" on public.viewer_profiles for delete to authenticated
  using ((select auth.uid()) = owner_id);

create policy "Owners can read library items" on public.library_items for select to authenticated
  using ((select auth.uid()) = owner_id);
create policy "Owners can create library items" on public.library_items for insert to authenticated
  with check (
    (select auth.uid()) = owner_id and exists (
      select 1 from public.viewer_profiles p where p.id = profile_id and p.owner_id = (select auth.uid())
    )
  );
create policy "Owners can update library items" on public.library_items for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check (
    (select auth.uid()) = owner_id and exists (
      select 1 from public.viewer_profiles p where p.id = profile_id and p.owner_id = (select auth.uid())
    )
  );
create policy "Owners can delete library items" on public.library_items for delete to authenticated
  using ((select auth.uid()) = owner_id);
