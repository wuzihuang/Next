-- F5 C7 · the model has no write tool (F4 §02: the client commits the draft), so any sentence
-- that says a thing was logged is a claim about a write that did not happen. One such frame
-- reached the panel on 2026-09-02 (「半碗面加一个鸡蛋已记录」, tool_trace []). The table was
-- English-only; the panel speaks zh-CN.
insert into public.banned_phrases (pattern, reason, replace_with) values
  ('已记录',            'F4 §02 · the model cannot write; a logged claim is unbacked',  '确认记录'),
  ('已记入',            'F4 §02 · the model cannot write',                              '确认记录'),
  ('已保存',            'F4 §02 · the model cannot write',                              '确认记录'),
  ('记好了',            'F4 §02 · the model cannot write',                              '确认记录'),
  ('(?i)\\blogged\\b',  'F4 §02 · the model cannot write',                              'confirm'),
  ('(?i)\\bsaved\\b',   'F4 §02 · the model cannot write',                              'confirm')
on conflict do nothing;
