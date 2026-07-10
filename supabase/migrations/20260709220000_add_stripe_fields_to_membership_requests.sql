alter table public.membership_requests
add column if not exists stripe_checkout_session_id text,
add column if not exists stripe_payment_intent_id text,
add column if not exists amount_total integer,
add column if not exists currency text,
add column if not exists paid_at timestamptz;

create unique index if not exists membership_requests_stripe_checkout_session_id_unique_idx
on public.membership_requests (stripe_checkout_session_id)
where stripe_checkout_session_id is not null;

create index if not exists membership_requests_card_payment_status_idx
on public.membership_requests (payment_method, payment_status, created_at desc)
where payment_method = 'card';
