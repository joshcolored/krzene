-- Upgrade projects that already applied the earlier email-auth migration.
-- This trigger runs for email/password, Google, Apple, and future providers.
create or replace function public.create_initial_viewer_profile()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  profile_name text;
  profile_avatar text;
begin
  profile_name := trim(coalesce(
    new.raw_user_meta_data ->> 'full_name',
    new.raw_user_meta_data ->> 'name',
    new.raw_user_meta_data ->> 'user_name',
    new.raw_user_meta_data ->> 'preferred_username',
    concat_ws(
      ' ',
      nullif(trim(new.raw_user_meta_data ->> 'given_name'), ''),
      nullif(trim(new.raw_user_meta_data ->> 'family_name'), '')
    ),
    ''
  ));
  if profile_name = '' then
    profile_name := split_part(coalesce(new.email, 'Viewer'), '@', 1);
  end if;
  profile_name := left(profile_name, 32);
  if profile_name = '' then
    profile_name := 'Viewer';
  end if;

  profile_avatar := nullif(trim(coalesce(
    new.raw_user_meta_data ->> 'avatar_url',
    new.raw_user_meta_data ->> 'picture',
    ''
  )), '');

  insert into public.viewer_profiles (owner_id, name, avatar_url, is_kids)
  select new.id, profile_name, profile_avatar, false
  where not exists (
    select 1 from public.viewer_profiles where owner_id = new.id
  );
  return new;
end;
$$;

drop trigger if exists create_initial_viewer_profile on auth.users;
create trigger create_initial_viewer_profile
  after insert on auth.users
  for each row execute function public.create_initial_viewer_profile();

-- Backfill accounts created before the trigger, including social accounts.
insert into public.viewer_profiles (owner_id, name, avatar_url, is_kids)
select
  users.id,
  left(
    coalesce(
      nullif(trim(users.raw_user_meta_data ->> 'full_name'), ''),
      nullif(trim(users.raw_user_meta_data ->> 'name'), ''),
      nullif(trim(users.raw_user_meta_data ->> 'user_name'), ''),
      nullif(trim(users.raw_user_meta_data ->> 'preferred_username'), ''),
      nullif(trim(concat_ws(
        ' ',
        nullif(trim(users.raw_user_meta_data ->> 'given_name'), ''),
        nullif(trim(users.raw_user_meta_data ->> 'family_name'), '')
      )), ''),
      nullif(split_part(coalesce(users.email, ''), '@', 1), ''),
      'Viewer'
    ),
    32
  ),
  nullif(trim(coalesce(
    users.raw_user_meta_data ->> 'avatar_url',
    users.raw_user_meta_data ->> 'picture',
    ''
  )), ''),
  false
from auth.users as users
where not exists (
  select 1
  from public.viewer_profiles as profiles
  where profiles.owner_id = users.id
);
