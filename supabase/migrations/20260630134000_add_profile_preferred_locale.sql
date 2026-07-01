alter table public.profiles
add column if not exists preferred_locale text not null default 'en';

update public.profiles
set preferred_locale = 'es'
where preferred_locale is null
   or preferred_locale = 'en';
