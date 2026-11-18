-- Ghana Buys — Flutterwave payments table
-- Run once in Supabase -> SQL Editor -> New query -> paste -> Run.
-- Safe to run more than once.

create table if not exists public.flutterwave_payments (
  id                  uuid primary key default gen_random_uuid(),
  tx_ref              text not null unique,
  user_id             uuid not null references auth.users(id) on delete cascade,
  kind                text not null check (kind in ('feature', 'store', 'verification')),
  target_id           uuid,            -- listing id (feature) or store id (store)
  amount_ghs          numeric(10, 2) not null,
  status              text not null default 'pending' check (status in ('pending', 'success', 'failed')),
  flw_transaction_id  bigint,
  created_at          timestamptz not null default now(),
  paid_at             timestamptz
);

create index if not exists flutterwave_payments_user_idx on public.flutterwave_payments (user_id, kind, status);

alter table public.flutterwave_payments enable row level security;

-- Sellers can see their own payments. Nobody can insert/update from the
-- browser: only the flutterwave-pay function (service role) writes here.
drop policy if exists "Users read own Flutterwave payments" on public.flutterwave_payments;
create policy "Users read own Flutterwave payments"
  on public.flutterwave_payments for select
  using (auth.uid() = user_id);

-- Admins (profiles.is_admin = true) can see every payment, for the
-- revenue figures and the "Paid" badge on ID verifications.
drop policy if exists "Admins read all Flutterwave payments" on public.flutterwave_payments;
create policy "Admins read all Flutterwave payments"
  on public.flutterwave_payments for select
  using (exists (select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));
