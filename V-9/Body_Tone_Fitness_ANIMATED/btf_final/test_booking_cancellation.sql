-- Body Tone Fitness: test booking + cancellation rules
-- Run this once in Supabase SQL Editor.

alter table public.test_bookings
  add column if not exists cancelled_at timestamptz;

-- Enforce the 4-hour advance-booking rule at the database level too.
create or replace function public.enforce_test_booking_four_hour_rule()
returns trigger
language plpgsql
as $$
declare
  appointment_at timestamp;
begin
  appointment_at := new.booking_date + new.booking_time;

  if tg_op = 'INSERT' then
    if appointment_at < now() + interval '4 hours' then
      raise exception 'Tests must be booked at least 4 hours in advance.';
    end if;
  elsif tg_op = 'UPDATE' and old.status = 'confirmed' and new.status = 'cancelled' then
    if appointment_at < now() + interval '4 hours' then
      raise exception 'Cancellation is only available at least 4 hours before the test.';
    end if;
    new.cancelled_at := coalesce(new.cancelled_at, now());
  end if;

  return new;
end;
$$;

drop trigger if exists trg_test_booking_four_hour_rule on public.test_bookings;
create trigger trg_test_booking_four_hour_rule
before insert or update of status on public.test_bookings
for each row execute function public.enforce_test_booking_four_hour_rule();

-- The website hides cancelled tests immediately from the member profile.
-- BMI cancellations also clear the pending BMI retest reminder in the website.
