-- F5 §06 · FDA general wellness — the forbidden list. C7: every English sentence the panel
-- shows passes this table first; a hit throws the whole segment away with E_CLAIM. The table
-- held only F4's persona words (great job, you should…); none of the words that turn a
-- wellness product into a device claim were on it, so "your HRV is abnormal" would have shipped.
insert into public.banned_phrases (pattern, reason, replace_with) values
  ('(?i)\bdiagnos(e|es|ed|ing|is|tic)\b', 'F5 §06 · a diagnostic verb moves the product from general wellness into a device claim', 'a direction, not a diagnosis'),
  ('(?i)\bdetect(s|ed|ing|ion)?\b',        'F5 §06 · a diagnostic verb',                                                  'a direction, not a diagnosis'),
  ('(?i)clinically[- ]validated',           'F5 §06 · an accuracy claim needs submitted methodology under 1.4.1',            'an estimate'),
  ('(?i)medical[- ]grade',                  'F5 §06 · an accuracy claim',                                                  'an estimate'),
  ('(?i)accurate to',                       'F5 §06 · an accuracy claim',                                                  'your seven-day trend'),
  ('(?i)\babnormal\b',                      'F5 §06 · a reference range is a diagnostic threshold by another name',         'low confidence / not enough data yet'),
  ('(?i)\bnormal\b',                        'F5 §06 · a reference range is a diagnostic threshold by another name',         'low confidence / not enough data yet'),
  ('(?i)out of range',                      'F5 §06 · a reference range',                                                  'not enough data yet'),
  ('(?i)\bdiseases?\b',                     'F5 §06 · naming a disease for this user is a device claim',                    'general wellness'),
  ('(?i)\bdisorders?\b',                    'F5 §06 · naming a disorder',                                                  'general wellness'),
  ('(?i)\bconditions?\b',                   'F5 §06 · naming a condition',                                                 'general wellness'),
  ('(?i)\btreat(s|ed|ing|ment)?\b',         'F5 §06 · a treatment verb is the shortest path over the line',                'This isn''t medical advice.'),
  ('(?i)\bcures?\b',                        'F5 §06 · a treatment verb',                                                   'This isn''t medical advice.'),
  ('(?i)\bprevent(s|ed|ing|ion)?\b',        'F5 §06 · a treatment verb',                                                   'This isn''t medical advice.'),
  ('(?i)\bmanage your\b',                   'F5 §06 · a treatment verb',                                                   'This isn''t medical advice.'),
  ('(?i)see a doctor',                      'F5 §06 · value-triggered referral needs a defined abnormal, which V1 does not define', 'Talk to a professional if you want to go further.'),
  ('(?i)\byou should see\b',                'F5 §06 · value-triggered referral',                                           'Talk to a professional if you want to go further.'),
  ('(?i)\bmeasurement\b',                   'F5 §06 · test / measurement call an estimate a test',                         'body fat estimate'),
  ('(?i)\btest result',                     'F5 §06 · test / measurement call an estimate a test',                         'body composition scan')
on conflict do nothing;
