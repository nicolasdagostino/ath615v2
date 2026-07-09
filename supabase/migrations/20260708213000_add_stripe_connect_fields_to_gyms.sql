alter table public.gyms
add column if not exists stripe_account_id text,
add column if not exists stripe_onboarding_complete boolean not null default false,
add column if not exists stripe_charges_enabled boolean not null default false,
add column if not exists stripe_payouts_enabled boolean not null default false;

create index if not exists gyms_stripe_account_id_idx
on public.gyms (stripe_account_id)
where stripe_account_id is not null;
