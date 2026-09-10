-- Ghana Buys — in-app messaging
-- Run this once in Supabase (SQL Editor → New query → paste → Run).
-- This is additive: it only creates the new `messages` table and does not
-- touch your existing listings/reviews/stores tables. If you keep a master
-- supabase-setup.sql, feel free to append this to it.

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

-- Users can see a message only if they sent it or received it.
create policy "Users can view their own messages"
  on public.messages for select
  using (auth.uid() = sender_id or auth.uid() = recipient_id);

-- Users can only insert messages as themselves (sender_id must match their
-- own auth id — this is what stops anyone from spoofing another sender).
create policy "Users can send messages"
  on public.messages for insert
  with check (auth.uid() = sender_id);

-- Only the recipient can update a message, and only to mark it read.
create policy "Recipients can mark messages read"
  on public.messages for update
  using (auth.uid() = recipient_id)
  with check (auth.uid() = recipient_id);

-- Powers the live unread badge and inbox refresh.
alter publication supabase_realtime add table public.messages;
