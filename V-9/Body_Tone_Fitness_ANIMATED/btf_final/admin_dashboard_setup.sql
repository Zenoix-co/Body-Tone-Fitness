-- BODY TONE FITNESS — Admin dashboard + realtime notifications
-- Run this once in Supabase SQL Editor.

create extension if not exists pgcrypto;

-- Contact form submissions
create table if not exists public.contact_messages (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  phone text not null,
  message text not null,
  status text not null default 'new',
  created_at timestamptz not null default now()
);

-- Membership enquiries/requests. This is NOT a payment record.
create table if not exists public.membership_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  name text not null,
  phone text,
  email text,
  plan_name text not null,
  term text,
  sessions integer,
  price numeric,
  status text not null default 'new',
  created_at timestamptz not null default now()
);

-- Persistent admin notifications.
create table if not exists public.admin_notifications (
  id uuid primary key default gen_random_uuid(),
  event_type text not null,
  title text not null,
  body text not null,
  reference_id uuid,
  created_at timestamptz not null default now(),
  read_at timestamptz
);

-- Helper used by RLS policies. SECURITY DEFINER prevents the admin check
-- from recursively depending on the profiles RLS policy.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to anon, authenticated;

-- RLS
alter table public.contact_messages enable row level security;
alter table public.membership_requests enable row level security;
alter table public.admin_notifications enable row level security;

-- Anyone can submit a contact message; only admins can read/manage them.
drop policy if exists "contact public insert" on public.contact_messages;
create policy "contact public insert"
on public.contact_messages for insert to anon, authenticated
with check (true);

drop policy if exists "contact admin read" on public.contact_messages;
create policy "contact admin read"
on public.contact_messages for select to authenticated
using (public.is_admin());

drop policy if exists "contact admin update" on public.contact_messages;
create policy "contact admin update"
on public.contact_messages for update to authenticated
using (public.is_admin()) with check (public.is_admin());

-- Membership requests can be submitted by signed-in members; admins can read/update.
drop policy if exists "membership request member insert" on public.membership_requests;
create policy "membership request member insert"
on public.membership_requests for insert to authenticated
with check (user_id = auth.uid() or user_id is null);

drop policy if exists "membership request admin read" on public.membership_requests;
create policy "membership request admin read"
on public.membership_requests for select to authenticated
using (public.is_admin() or user_id = auth.uid());

drop policy if exists "membership request admin update" on public.membership_requests;
create policy "membership request admin update"
on public.membership_requests for update to authenticated
using (public.is_admin()) with check (public.is_admin());

-- Only admins can read/change the persistent notification feed.
drop policy if exists "admin notifications admin read" on public.admin_notifications;
create policy "admin notifications admin read"
on public.admin_notifications for select to authenticated
using (public.is_admin());

drop policy if exists "admin notifications admin update" on public.admin_notifications;
create policy "admin notifications admin update"
on public.admin_notifications for update to authenticated
using (public.is_admin()) with check (public.is_admin());

-- Admin dashboard needs to see all relevant records.
drop policy if exists "test bookings admin read" on public.test_bookings;
create policy "test bookings admin read"
on public.test_bookings for select to authenticated
using (public.is_admin() or user_id = auth.uid());

drop policy if exists "memberships admin read" on public.memberships;
create policy "memberships admin read"
on public.memberships for select to authenticated
using (public.is_admin() or user_id = auth.uid());

drop policy if exists "profiles admin read" on public.profiles;
create policy "profiles admin read"
on public.profiles for select to authenticated
using (public.is_admin() or id = auth.uid());

-- Realtime publication. Safe if tables are already present in the publication.
do $$
begin
  begin alter publication supabase_realtime add table public.test_bookings; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.membership_requests; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.contact_messages; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.memberships; exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.admin_notifications; exception when duplicate_object then null; end;
end $$;

-- Notification triggers. They create one persistent notification for each new event.
create or replace function public.notify_admin_new_booking()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.admin_notifications(event_type,title,body,reference_id)
  values (
    'test_booking',
    'New test booking',
    upper(coalesce(new.test_type,'TEST')) || ' booked for ' || new.booking_date::text || ' at ' || new.booking_time::text,
    new.id
  );
  return new;
end;
$$;

drop trigger if exists trg_admin_new_booking on public.test_bookings;
create trigger trg_admin_new_booking
after insert on public.test_bookings
for each row execute function public.notify_admin_new_booking();

create or replace function public.notify_admin_membership_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.admin_notifications(event_type,title,body,reference_id)
  values (
    'membership_request',
    'New membership request',
    new.plan_name || ' · ' || coalesce(new.term,'') || ' · ₹' || coalesce(new.price,0)::text,
    new.id
  );
  return new;
end;
$$;

drop trigger if exists trg_admin_membership_request on public.membership_requests;
create trigger trg_admin_membership_request
after insert on public.membership_requests
for each row execute function public.notify_admin_membership_request();

create or replace function public.notify_admin_contact_message()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.admin_notifications(event_type,title,body,reference_id)
  values (
    'contact_message',
    'New contact message',
    'Message from ' || new.name || ' · ' || new.phone,
    new.id
  );
  return new;
end;
$$;

drop trigger if exists trg_admin_contact_message on public.contact_messages;
create trigger trg_admin_contact_message
after insert on public.contact_messages
for each row execute function public.notify_admin_contact_message();

create or replace function public.notify_admin_membership_purchase()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.admin_notifications(event_type,title,body,reference_id)
  values (
    'membership_purchase',
    'New membership activated',
    coalesce(new.plan_name,'Membership') || ' · status: ' || coalesce(new.status,'active'),
    new.id
  );
  return new;
end;
$$;

drop trigger if exists trg_admin_membership_purchase on public.memberships;
create trigger trg_admin_membership_purchase
after insert on public.memberships
for each row execute function public.notify_admin_membership_purchase();


-- ============================================================
-- ADMIN TEST REPORTS
-- Authorized admin: zeonixco@gmail.com
-- ============================================================

create table if not exists public.test_reports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  report_type text not null check (report_type in ('blood','bmi')),
  file_name text not null,
  file_path text not null,
  file_url text not null,
  created_at timestamptz not null default now()
);

alter table public.test_reports enable row level security;

-- Members can read only their own reports.
drop policy if exists "members read own reports" on public.test_reports;
create policy "members read own reports"
on public.test_reports for select
to authenticated
using (auth.uid() = user_id);

-- Only the authorized admin can manage report rows.
drop policy if exists "admin manage reports" on public.test_reports;
create policy "admin manage reports"
on public.test_reports for all
to authenticated
using ((auth.jwt()->>'email') = 'zeonixco@gmail.com')
with check ((auth.jwt()->>'email') = 'zeonixco@gmail.com');

-- Storage bucket for reports.
insert into storage.buckets (id, name, public)
values ('test-reports', 'test-reports', false)
on conflict (id) do nothing;

-- Admin can manage all report files.
drop policy if exists "admin manage report files" on storage.objects;
create policy "admin manage report files"
on storage.objects for all
to authenticated
using (
  bucket_id = 'test-reports'
  and (auth.jwt()->>'email') = 'zeonixco@gmail.com'
)
with check (
  bucket_id = 'test-reports'
  and (auth.jwt()->>'email') = 'zeonixco@gmail.com'
);

-- A member can read only files stored under their own user-id folder.
drop policy if exists "members read own report files" on storage.objects;
create policy "members read own report files"
on storage.objects for select
to authenticated
using (
  bucket_id = 'test-reports'
  and (storage.foldername(name))[1] = auth.uid()::text
);


-- ============================================================
-- PASSWORD RESET / EMAIL OTP
-- ============================================================
-- Enable Email OTP in Supabase Dashboard:
-- Authentication -> Providers -> Email -> enable Email provider/OTP.
-- Configure your SMTP sender in Authentication -> SMTP Settings for
-- production delivery. Supabase Auth handles OTP expiry/rate limiting.
-- No passwords or OTPs are stored by this website.
