create table if not exists public.watch_progress (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  profile_id uuid not null references public.viewer_profiles(id) on delete cascade,
  media_key text not null,
  media jsonb not null,
  position double precision not null default 0 check (position >= 0),
  duration double precision not null default 0 check (duration >= 0),
  season integer,
  episode integer,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (profile_id, media_key)
);

create index if not exists watch_progress_profile_idx
  on public.watch_progress(profile_id, updated_at desc);

alter table public.watch_progress enable row level security;

revoke all on public.watch_progress from anon;
grant select, insert, update, delete on public.watch_progress to authenticated;

create policy "Owners can read watch progress" on public.watch_progress for select to authenticated
  using ((select auth.uid()) = owner_id);

create policy "Owners can create watch progress" on public.watch_progress for insert to authenticated
  with check (
    (select auth.uid()) = owner_id and exists (
      select 1 from public.viewer_profiles p
      where p.id = profile_id and p.owner_id = (select auth.uid())
    )
  );

create policy "Owners can update watch progress" on public.watch_progress for update to authenticated
  using ((select auth.uid()) = owner_id)
  with check (
    (select auth.uid()) = owner_id and exists (
      select 1 from public.viewer_profiles p
      where p.id = profile_id and p.owner_id = (select auth.uid())
    )
  );

create policy "Owners can delete watch progress" on public.watch_progress for delete to authenticated
  using ((select auth.uid()) = owner_id);
