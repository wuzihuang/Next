-- 20260902060000 shipped the two English rows with doubled backslashes (a literal "\\b").
delete from public.banned_phrases where pattern in ('(?i)\\blogged\\b', '(?i)\\bsaved\\b');
insert into public.banned_phrases (pattern, reason, replace_with) values
  ('(?i)\blogged\b', 'F4 §02 · the model cannot write', 'confirm'),
  ('(?i)\bsaved\b',  'F4 §02 · the model cannot write', 'confirm')
on conflict do nothing;
