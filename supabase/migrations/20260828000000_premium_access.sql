create table if not exists public.premium_subscriptions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null unique references auth.users(id) on delete cascade,
  status text not null default 'inactive'
    check (status in ('inactive', 'active', 'expired', 'cancelled')),
  current_period_start timestamptz,
  current_period_end timestamptz,
  paymongo_customer_id text,
  paymongo_subscription_id text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.premium_checkout_sessions (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  paymongo_checkout_session_id text not null unique,
  reference_number text not null unique,
  amount integer not null default 5000 check (amount > 0),
  currency text not null default 'PHP' check (currency = 'PHP'),
  status text not null default 'pending'
    check (status in ('pending', 'paid', 'expired', 'failed')),
  created_at timestamptz not null default now(),
  paid_at timestamptz
);

create table if not exists public.paymongo_webhook_events (
  event_id text primary key,
  event_type text not null,
  livemode boolean not null default false,
  received_at timestamptz not null default now()
);

create index if not exists premium_checkout_owner_idx
  on public.premium_checkout_sessions(owner_id, created_at desc);

alter table public.premium_subscriptions enable row level security;
alter table public.premium_checkout_sessions enable row level security;
alter table public.paymongo_webhook_events enable row level security;

revoke all on public.premium_subscriptions, public.premium_checkout_sessions, public.paymongo_webhook_events from anon;
revoke all on public.premium_subscriptions, public.premium_checkout_sessions, public.paymongo_webhook_events from authenticated;
grant select on public.premium_subscriptions, public.premium_checkout_sessions to authenticated;

create policy "Owners can read premium access" on public.premium_subscriptions for select to authenticated
  using ((select auth.uid()) = owner_id);

create policy "Owners can read premium checkouts" on public.premium_checkout_sessions for select to authenticated
  using ((select auth.uid()) = owner_id);

-- Inserts and updates intentionally have no authenticated-user policies.
-- Only server code using Supabase's service-role key may create checkout rows
-- or activate premium after it verifies a PayMongo webhook.
