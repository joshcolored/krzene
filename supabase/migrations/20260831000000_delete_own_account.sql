create or replace function public.delete_own_account()
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
declare
  deleted_user_id uuid;
begin
  if (select auth.uid()) is null then
    raise exception 'Authentication required';
  end if;

  delete from auth.users
  where id = (select auth.uid())
  returning id into deleted_user_id;

  return deleted_user_id is not null;
end;
$$;

revoke all on function public.delete_own_account() from public, anon;
grant execute on function public.delete_own_account() to authenticated;

comment on function public.delete_own_account() is
  'Permanently deletes only the authenticated user and cascades their app data.';
