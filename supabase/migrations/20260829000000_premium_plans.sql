create table if not exists public.premium_plans (
  id text primary key,
  name text not null,
  price_centavos integer not null check (price_centavos > 0),
  currency text not null default 'PHP' check (currency = 'PHP'),
  access_days integer not null check (access_days > 0),
  active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

insert into public.premium_plans (id, name, price_centavos, currency, access_days, active)
values ('standard', 'Krzene Premium', 5000, 'PHP', 30, true)
on conflict (id) do nothing;

alter table public.premium_plans enable row level security;
revoke all on public.premium_plans from anon, authenticated;
grant select on public.premium_plans to anon, authenticated;

create policy "Anyone can read active premium plans"
  on public.premium_plans for select
  to anon, authenticated
  using (active = true);

alter table public.premium_checkout_sessions
  add column if not exists plan_id text references public.premium_plans(id),
  add column if not exists access_days integer check (access_days > 0);

alter table public.premium_checkout_sessions
  alter column amount drop default;

update public.premium_checkout_sessions
set plan_id = coalesce(plan_id, 'standard'),
    access_days = coalesce(access_days, 30)
where plan_id is null or access_days is null;

alter table public.premium_checkout_sessions
  alter column plan_id set not null,
  alter column access_days set not null;
