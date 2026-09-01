-- 11 · the identity row at the top of ME, and the Name field in PERSONAL INFO. There was
-- nowhere to put either: profiles carried the numbers the maths needs and nothing a person
-- would recognise as themselves, so the app showed its own "ZEPH · you@nextbody.app" on
-- top of a real account.
alter table public.profiles
  add column if not exists display_name text check (display_name is null or length(display_name) <= 60);

update public.profiles p set display_name = 'ZEPH'
from auth.users u where u.id = p.user_id and u.email = 'demo@nextbody.app' and p.display_name is null;
