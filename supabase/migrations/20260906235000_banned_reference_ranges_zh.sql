-- F5 §06 · the reference-range ban was English-only.
--
-- The list already refuses "normal", "abnormal", "out of range" and "a bit low" — a
-- reference range is a diagnostic threshold by another name. The app's own language is
-- Simplified Chinese, and the 2026-09-06 coverage sweep printed 「都在正常范围」 and
-- 「偏低」 on the same reasoning path the English words are banned from. A rule that only
-- holds in one language is not a rule.
--
-- ⚠️ The bare word 正常 is deliberately NOT banned: "手环工作正常" is a device state, not a
-- health verdict. What is banned is the range claim and the grading words.
insert into public.banned_phrases (pattern, reason, replace_with) values
  ('正常范围',   'F5 §06 · 参考区间就是诊断阈值的另一种说法',      '写测到的值和它的窗口'),
  ('参考范围',   'F5 §06 · 参考区间就是诊断阈值的另一种说法',      '写测到的值和它的窗口'),
  ('正常值',     'F5 §06 · 参考区间就是诊断阈值的另一种说法',      '写测到的值和它的窗口'),
  ('异常',       'F5 §06 · 判定「异常」是设备声明',                '说方向，不下判定'),
  ('偏高',       'F5 §06 · 相对某个隐含正常值的评级',              '写和这个人自己的基线比是多少'),
  ('偏低',       'F5 §06 · 相对某个隐含正常值的评级（英文 a bit low 已在列）', '写和这个人自己的基线比是多少')
on conflict do nothing;

-- ⚠️ 「已记录 0 餐」 was thrown away as a write claim. The ban exists because the model
-- cannot write, not because the word may never appear: followed by a number it is a count
-- of the user's own records, which is exactly what the fuel screen is for. The claim form
-- ("已记录了这一餐" / "logged it") stays banned.
update public.banned_phrases set pattern = '已记录(?!\s*[0-9０-９])' where pattern = '已记录';
update public.banned_phrases set pattern = '(?i)\blogged\b(?!\s+[0-9])' where pattern = '(?i)\blogged\b';
