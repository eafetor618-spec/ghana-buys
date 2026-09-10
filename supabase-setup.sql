-- =====================================================================
-- Ghana Buys — full Supabase setup
-- =====================================================================
-- Run this once in Supabase → SQL Editor → New query → paste → Run.
--
-- IMPORTANT — how this file came to be:
-- The repo's README references a supabase-setup.sql that creates the
-- listings table, security rules, and image bucket, but that file wasn't
-- present in the upload I was given. Everything below was reconstructed
-- by reading every .from(...), .storage.from(...), .rpc(...), .select(),
-- .insert(), and .update() call across every page of the actual front-end
-- code, so the table/column names match exactly what the app expects.
-- Two things I could NOT recover from the front-end alone, flagged where
-- they occur below:
--   1) The exact schema of tables written only by your Paystack edge
--      functions (feature-listing, store-subscription, pay-listing,
--      delete-account) — those run server-side with the service role key,
--      which bypasses RLS, so the client code never reveals their full
--      shape. feature_payments/store_payments below are my best
--      reconstruction from what admin.html reads back.
--   2) A couple of judgment calls on access rules (see "SECURITY NOTE"
--      comments) where the original file might have chosen differently.
-- If you still have your real original file (e.g. in git history), diff
-- it against this one before running — this is a rebuild, not a backup.
-- =====================================================================

create extension if not exists pgcrypto;

-- =====================================================================
-- 1. PROFILES — one row per user, auto-created on signup
-- =====================================================================
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text,
  is_admin boolean not null default false,
  -- Set by a Paystack-onboarding edge function (not in this upload) once a
  -- seller connects a payout account for "Verified Instant Payment".
  paystack_subaccount_code text,
  payout_network text,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

-- Helper used throughout this file — SECURITY DEFINER so it can check
-- is_admin without recursing back through profiles' own RLS policies.
create or replace function public.is_admin()
returns boolean
language sql security definer set search_path = public stable
as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;
grant execute on function public.is_admin() to anon, authenticated;

-- SECURITY NOTE: listing.html reads another seller's
-- paystack_subaccount_code/payout_network for ANY visitor (even logged
-- out) to show the "Verified Instant Payment" box. RLS is row-level, not
-- column-level, so the simplest policy that keeps that feature working is
-- "anyone can read any profile" — which also makes the `email` column
-- world-readable to anyone who queries the table directly (not just
-- through the UI). If that's not acceptable, move email out of this
-- table into a separate admin-only table, or drop this public policy and
-- instead expose only the two payment columns through a view/RPC.
create policy "Anyone can view profiles" on public.profiles for select using (true);
create policy "Users can update their own profile" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

create or replace function public.handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  insert into public.profiles (id, email) values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- =====================================================================
-- 2. LISTINGS
-- =====================================================================
create table if not exists public.listings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  seller_name text,
  title text not null,
  description text,
  price numeric,
  negotiable boolean not null default false,
  condition text,
  brand text,
  color text,
  category text not null,
  custom_category text,
  location text,
  whatsapp text not null,
  image_url text,
  image_urls text[] not null default '{}',
  momo_number text,
  momo_name text,
  momo_networks text[] not null default '{}',
  status text not null default 'active'
    check (status in ('active', 'sold', 'expired', 'removed', 'under_review')),
  views integer not null default 0,
  featured boolean not null default false,
  featured_until timestamptz,
  expires_at timestamptz not null default (now() + interval '30 days'),
  created_at timestamptz not null default now()
);

create index if not exists listings_status_idx on public.listings (status, category, created_at desc);
create index if not exists listings_user_idx on public.listings (user_id);

alter table public.listings enable row level security;

create policy "Public can view active listings" on public.listings
  for select using (status = 'active');
create policy "Owners and admins can view their own/all listings" on public.listings
  for select using (auth.uid() = user_id or public.is_admin());
create policy "Owners can create their own listings" on public.listings
  for insert with check (auth.uid() = user_id);
create policy "Owners and admins can update listings" on public.listings
  for update using (auth.uid() = user_id or public.is_admin())
  with check (auth.uid() = user_id or public.is_admin());
create policy "Owners can delete their own listings" on public.listings
  for delete using (auth.uid() = user_id);

-- Stops a seller from featuring their own listing for free, or clearing a
-- moderation hold on their own listing, by editing the row directly.
create or replace function public.protect_listing_admin_fields()
returns trigger language plpgsql security definer as $$
begin
  if not public.is_admin() then
    if new.featured is distinct from old.featured
       or new.featured_until is distinct from old.featured_until then
      raise exception 'Only admins can feature a listing.';
    end if;
    if old.status in ('under_review', 'removed') and new.status not in ('under_review', 'removed') then
      raise exception 'This listing is under moderation.';
    end if;
    if new.status in ('under_review', 'removed') and old.status not in ('under_review', 'removed') then
      raise exception 'Only admins or the report system can set that status.';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists protect_listing_admin_fields_trigger on public.listings;
create trigger protect_listing_admin_fields_trigger
  before update on public.listings
  for each row execute function public.protect_listing_admin_fields();

-- =====================================================================
-- 3. LISTING VIEWS — one row per (listing, visitor), powers the view count
-- =====================================================================
create table if not exists public.listing_views (
  listing_id uuid not null references public.listings(id) on delete cascade,
  visitor_id text not null,
  created_at timestamptz not null default now(),
  primary key (listing_id, visitor_id)
);

alter table public.listing_views enable row level security;

create policy "Anyone can record a view" on public.listing_views
  for insert with check (true);
create policy "Owners and admins can view view logs" on public.listing_views
  for select using (
    public.is_admin() or
    exists (select 1 from public.listings l where l.id = listing_id and l.user_id = auth.uid())
  );

create or replace function public.increment_listing_views()
returns trigger language plpgsql security definer as $$
begin
  update public.listings set views = views + 1 where id = new.listing_id;
  return new;
end;
$$;
drop trigger if exists increment_listing_views_trigger on public.listing_views;
create trigger increment_listing_views_trigger
  after insert on public.listing_views
  for each row execute function public.increment_listing_views();

-- =====================================================================
-- 4. LISTING REPORTS — auto-hides a listing after 3+ reports
-- =====================================================================
create table if not exists public.listing_reports (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  reporter_user_id uuid references auth.users(id) on delete set null,
  reason text not null,
  details text,
  created_at timestamptz not null default now()
);

alter table public.listing_reports enable row level security;

create policy "Anyone can file a report" on public.listing_reports
  for insert with check (true);
create policy "Admins can view all reports" on public.listing_reports
  for select using (public.is_admin());

create or replace function public.check_report_threshold()
returns trigger language plpgsql security definer as $$
declare
  report_count int;
begin
  select count(*) into report_count from public.listing_reports where listing_id = new.listing_id;
  if report_count >= 3 then
    update public.listings set status = 'under_review'
      where id = new.listing_id and status = 'active';
  end if;
  return new;
end;
$$;
drop trigger if exists check_report_threshold_trigger on public.listing_reports;
create trigger check_report_threshold_trigger
  after insert on public.listing_reports
  for each row execute function public.check_report_threshold();

-- =====================================================================
-- 5. SAVED LISTINGS ("Cart") and SAVED SEARCHES ("Alerts")
-- =====================================================================
create table if not exists public.saved_listings (
  user_id uuid not null references auth.users(id) on delete cascade,
  listing_id uuid not null references public.listings(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, listing_id)
);
alter table public.saved_listings enable row level security;
create policy "Users manage their own saved listings" on public.saved_listings
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

create table if not exists public.saved_searches (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  category text,
  keyword text,
  created_at timestamptz not null default now()
);
alter table public.saved_searches enable row level security;
create policy "Users manage their own saved searches" on public.saved_searches
  for all using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- =====================================================================
-- 6. STORES and STORE SUBSCRIPTIONS
-- =====================================================================
create table if not exists public.stores (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null unique references auth.users(id) on delete cascade,
  name text not null,
  description text,
  whatsapp text,
  active boolean not null default false,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.stores enable row level security;

create policy "Anyone can view stores" on public.stores for select using (true);
create policy "Owners can create their store" on public.stores
  for insert with check (auth.uid() = user_id);
create policy "Owners and admins can update stores" on public.stores
  for update using (auth.uid() = user_id or public.is_admin())
  with check (auth.uid() = user_id or public.is_admin());

-- Stops an owner from self-activating their subscription for free.
create or replace function public.protect_store_admin_fields()
returns trigger language plpgsql security definer as $$
begin
  if not public.is_admin() then
    if new.active is distinct from old.active
       or new.expires_at is distinct from old.expires_at then
      raise exception 'Only admins can activate a store subscription.';
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists protect_store_admin_fields_trigger on public.stores;
create trigger protect_store_admin_fields_trigger
  before update on public.stores
  for each row execute function public.protect_store_admin_fields();

create table if not exists public.store_subscription_requests (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz
);
alter table public.store_subscription_requests enable row level security;
create policy "Users can request a store subscription" on public.store_subscription_requests
  for insert with check (auth.uid() = user_id);
create policy "Users and admins can view store subscription requests" on public.store_subscription_requests
  for select using (auth.uid() = user_id or public.is_admin());
create policy "Admins review store subscription requests" on public.store_subscription_requests
  for update using (public.is_admin()) with check (public.is_admin());

-- =====================================================================
-- 7. REVIEWS — store.html displays these; there's no submission UI in
-- this upload yet, so reviewer_id/listing_id are here for when you add
-- one. Adjust the insert policy if you want reviews restricted to buyers
-- who actually completed a purchase.
-- =====================================================================
create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references auth.users(id) on delete cascade,
  reviewer_id uuid not null references auth.users(id) on delete cascade,
  listing_id uuid references public.listings(id) on delete set null,
  rating smallint not null check (rating between 1 and 5),
  comment text,
  created_at timestamptz not null default now(),
  constraint reviews_not_self check (seller_id <> reviewer_id)
);
alter table public.reviews enable row level security;
create policy "Anyone can view reviews" on public.reviews for select using (true);
create policy "Users can leave reviews" on public.reviews
  for insert with check (auth.uid() = reviewer_id);

-- =====================================================================
-- 8. ID VERIFICATIONS
-- =====================================================================
create table if not exists public.id_verifications (
  user_id uuid primary key references auth.users(id) on delete cascade,
  id_type text,
  id_number text,
  document_path text,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  ocr_extracted_text text,
  ocr_match boolean,
  review_note text,
  submitted_at timestamptz not null default now(),
  reviewed_at timestamptz
);
alter table public.id_verifications enable row level security;
create policy "Users and admins can view verifications" on public.id_verifications
  for select using (auth.uid() = user_id or public.is_admin());
create policy "Users can submit their own verification" on public.id_verifications
  for insert with check (auth.uid() = user_id);
create policy "Users and admins can update verifications" on public.id_verifications
  for update using (auth.uid() = user_id or public.is_admin())
  with check (auth.uid() = user_id or public.is_admin());

-- Lets a user resubmit (status resets to 'pending'), but only an admin can
-- actually approve/reject or touch the review/OCR fields.
create or replace function public.protect_id_verification_admin_fields()
returns trigger language plpgsql security definer as $$
begin
  if not public.is_admin() then
    new.status := 'pending';
    new.reviewed_at := null;
    if TG_OP = 'UPDATE' then
      new.review_note := old.review_note;
      new.ocr_extracted_text := old.ocr_extracted_text;
      new.ocr_match := old.ocr_match;
    else
      new.review_note := null;
      new.ocr_extracted_text := null;
      new.ocr_match := null;
    end if;
  end if;
  return new;
end;
$$;
drop trigger if exists protect_id_verification_fields on public.id_verifications;
create trigger protect_id_verification_fields
  before insert or update on public.id_verifications
  for each row execute function public.protect_id_verification_admin_fields();

create or replace function public.is_seller_verified(seller_id uuid)
returns boolean
language sql security definer set search_path = public stable
as $$
  select exists (
    select 1 from public.id_verifications
    where user_id = seller_id and status = 'approved'
  );
$$;
grant execute on function public.is_seller_verified(uuid) to anon, authenticated;

-- =====================================================================
-- 9. FEATURE REQUESTS (₵10 "feature my listing" via Mobile Money)
-- =====================================================================
create table if not exists public.feature_requests (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz
);
alter table public.feature_requests enable row level security;
create policy "Users can request a feature" on public.feature_requests
  for insert with check (auth.uid() = user_id);
create policy "Users and admins can view feature requests" on public.feature_requests
  for select using (auth.uid() = user_id or public.is_admin());
create policy "Admins review feature requests" on public.feature_requests
  for update using (public.is_admin()) with check (public.is_admin());

-- =====================================================================
-- 10. LISTING POST REQUESTS (₵5 posting fee flow used by post-payment.html)
-- NOTE: post.html currently sets status='active' directly on insert and
-- never touches this table — this flow looks unwired between the two
-- pages. Table is here so post-payment.html's existing queries work; you
-- may want to reconcile the two posting flows separately.
-- =====================================================================
create table if not exists public.listing_post_requests (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid not null references public.listings(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_at timestamptz not null default now(),
  reviewed_at timestamptz
);
alter table public.listing_post_requests enable row level security;
create policy "Users can request a listing post" on public.listing_post_requests
  for insert with check (auth.uid() = user_id);
create policy "Users and admins can view listing post requests" on public.listing_post_requests
  for select using (auth.uid() = user_id or public.is_admin());
create policy "Admins review listing post requests" on public.listing_post_requests
  for update using (public.is_admin()) with check (public.is_admin());

-- =====================================================================
-- 11. PAYMENTS — written by your Paystack edge functions using the
-- service role key, which bypasses RLS, so no client insert/update
-- policy is needed or given here. Columns are my best reconstruction
-- from what admin.html reads back (amount_pesewas, status, created_at) —
-- double-check these against your actual edge function code.
-- =====================================================================
create table if not exists public.feature_payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  listing_id uuid references public.listings(id) on delete set null,
  reference text unique,
  amount_pesewas integer not null,
  status text not null default 'pending',
  created_at timestamptz not null default now()
);
alter table public.feature_payments enable row level security;
create policy "Admins can view feature payments" on public.feature_payments
  for select using (public.is_admin());

create table if not exists public.store_payments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  store_id uuid references public.stores(id) on delete set null,
  reference text unique,
  amount_pesewas integer not null,
  status text not null default 'pending',
  created_at timestamptz not null default now()
);
alter table public.store_payments enable row level security;
create policy "Admins can view store payments" on public.store_payments
  for select using (public.is_admin());

-- =====================================================================
-- 12. SITE SETTINGS — Mobile Money details shown on feature/store/ID/post
-- payment screens. Update the three values below with your real details.
-- =====================================================================
create table if not exists public.site_settings (
  key text primary key,
  value text
);
alter table public.site_settings enable row level security;
create policy "Anyone can read site settings" on public.site_settings for select using (true);
create policy "Admins can manage site settings" on public.site_settings
  for all using (public.is_admin()) with check (public.is_admin());

insert into public.site_settings (key, value) values
  ('feature_momo_number', 'REPLACE_ME'),
  ('feature_momo_name', 'REPLACE_ME'),
  ('feature_momo_network', 'MTN MoMo')
on conflict (key) do nothing;

-- =====================================================================
-- 13. MESSAGES — in-app buyer/seller messaging
-- =====================================================================
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  listing_id uuid references public.listings(id) on delete set null,
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_id uuid not null references auth.users(id) on delete cascade,
  sender_name text,
  content text not null check (char_length(content) between 1 and 2000),
  read boolean not null default false,
  created_at timestamptz not null default now(),
  constraint messages_not_to_self check (sender_id <> recipient_id)
);
create index if not exists messages_recipient_unread_idx on public.messages (recipient_id, read);
create index if not exists messages_conversation_idx on public.messages (listing_id, sender_id, recipient_id, created_at);

alter table public.messages enable row level security;
create policy "Users can view their own messages" on public.messages
  for select using (auth.uid() = sender_id or auth.uid() = recipient_id);
create policy "Users can send messages" on public.messages
  for insert with check (auth.uid() = sender_id);
create policy "Recipients can mark messages read" on public.messages
  for update using (auth.uid() = recipient_id) with check (auth.uid() = recipient_id);

alter publication supabase_realtime add table public.messages;

-- =====================================================================
-- 14. STORAGE BUCKETS
-- =====================================================================
insert into storage.buckets (id, name, public)
values ('listing-images', 'listing-images', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('id-documents', 'id-documents', false)
on conflict (id) do nothing;

-- listing-images: public read; owners can only write inside a folder
-- named after their own user id (post.html uploads to `${userId}/...`).
create policy "Public can view listing images" on storage.objects
  for select using (bucket_id = 'listing-images');
create policy "Users can upload their own listing images" on storage.objects
  for insert with check (
    bucket_id = 'listing-images' and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "Users can delete their own listing images" on storage.objects
  for delete using (
    bucket_id = 'listing-images' and (storage.foldername(name))[1] = auth.uid()::text
  );

-- id-documents: private. Owners can upload to their own folder; only
-- admins can read (admin.html uses createSignedUrl, which still needs a
-- SELECT policy on storage.objects to succeed).
create policy "Users can upload their own ID documents" on storage.objects
  for insert with check (
    bucket_id = 'id-documents' and (storage.foldername(name))[1] = auth.uid()::text
  );
create policy "Admins can view ID documents" on storage.objects
  for select using (bucket_id = 'id-documents' and public.is_admin());

-- =====================================================================
-- DONE. Two manual steps left:
--
-- 1. Make yourself an admin (replace with your real email), so /admin works:
--    update public.profiles set is_admin = true
--      where email = 'you@example.com';
--
-- 2. Update the Mobile Money placeholders from step 12 with your real
--    number/name/network:
--    update public.site_settings set value = '024xxxxxxx' where key = 'feature_momo_number';
--    update public.site_settings set value = 'Your Name'  where key = 'feature_momo_name';
--    update public.site_settings set value = 'MTN MoMo'   where key = 'feature_momo_network';
-- =====================================================================
