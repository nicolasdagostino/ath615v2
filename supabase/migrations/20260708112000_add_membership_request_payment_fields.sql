alter table public.membership_requests
add column if not exists payment_method text not null default 'cash',
add column if not exists payment_status text not null default 'pending';

alter table public.membership_requests
drop constraint if exists membership_requests_payment_method_check;

alter table public.membership_requests
add constraint membership_requests_payment_method_check
check (payment_method in ('cash', 'card'));

alter table public.membership_requests
drop constraint if exists membership_requests_payment_status_check;

alter table public.membership_requests
add constraint membership_requests_payment_status_check
check (payment_status in ('pending', 'paid', 'failed', 'cancelled', 'refunded'));

create index if not exists membership_requests_gym_status_payment_idx
on public.membership_requests (gym_id, status, payment_method, payment_status, created_at desc);
