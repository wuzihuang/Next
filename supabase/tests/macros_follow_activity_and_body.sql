begin;
create extension if not exists pgtap with schema extensions;
set search_path = public, extensions;
select plan(12);

-- ADR 0033 · protein and carbohydrate follow today's measured activity; fat follows the body
-- (sex, goal, lean mass) and the day without its activity. 75 kg / 180 cm male RECOMP unless
-- said otherwise; 1500 is a still day, 2270 the same day with 900 kcal of measured activity.
create or replace function pg_temp.split(p_weight numeric, p_height numeric, p_sex text,
  p_goal text, p_lean numeric, p_active numeric, p_target numeric)
returns record language sql as $$
  select (s.protein_g, s.fat_g, s.carb_g, s.kcal, s.reference_kg)
  from nb.macro_split(p_weight, p_height, p_sex, p_goal, p_lean, p_active, p_target) s $$;

select is((select protein_g from nb.macro_split(75,180,'male','RECOMP',null,100,1500)), 130,
  'a still RECOMP day asks 1.7 g/kg of protein');
select is((select protein_g from nb.macro_split(75,180,'male','RECOMP',null,900,2270)), 160,
  'a 12 kcal/kg training day adds 0.4 g/kg on top');
select ok((select a.protein_g < b.protein_g and b.protein_g < c.protein_g
           from nb.macro_split(75,180,'male','RECOMP',null,300,1700) a,
                nb.macro_split(75,180,'male','RECOMP',null,600,2000) b,
                nb.macro_split(75,180,'male','RECOMP',null,900,2300) c),
  'protein climbs with activity between the two ends');
select ok((select b.carb_g - a.carb_g >= 80
           from nb.macro_split(75,180,'male','RECOMP',null,400,1770) a,
                nb.macro_split(75,180,'male','RECOMP',null,900,2270) b),
  'carbohydrate carries most of the 500 kcal the training added');
select ok((select abs(b.fat_g - a.fat_g) <= 5
           from nb.macro_split(75,180,'male','RECOMP',null,400,1770) a,
                nb.macro_split(75,180,'male','RECOMP',null,900,2270) b),
  'fat does not follow the activity');
select ok((select 9 * fat_g >= 0.2 * kcal - 45 from nb.macro_split(75,180,'male','CUT',null,900,2150)),
  'fat never drops under a fifth of the day, within one rounding step');
select is((select fat_g from nb.macro_split(58,163,'female','RECOMP',null,700,1620)), 45,
  'a woman''s fat stops at 0.8 g/kg');
select is((select reference_kg from nb.macro_split(100,175,'male','CUT',62,400,1850)), 75.6,
  'a scanned heavy body is asked by its lean mass at 18 % body fat');
select is((select reference_kg from nb.macro_split(100,175,'male','CUT',null,400,1850)), 76.6,
  'an unscanned heavy body is capped at BMI 25');
select is((select reference_kg from nb.macro_split(75,180,'male','CUT',70,400,1850)), 75.0,
  'a lean body is never asked for more than its scale weight');
select ok((select bool_and(abs(s.kcal - t.target) <= 20)
           from (values (1500,100,'CUT'),(1770,400,'RECOMP'),(2950,900,'BULK'),(2400,700,'CUT'))
                  t(target,active,goal),
                nb.macro_split(75,180,'male',t.goal,null,t.active,t.target) s),
  'the split still adds back up to the target within one 20 kcal step');

-- compute_fuel reads the latest scan's lean mass for the split.
insert into auth.users(id) values ('33330000-0000-4000-8000-000000000001');
insert into public.profiles(user_id,timezone,sex,height_cm,birth_date,goal) values
 ('33330000-0000-4000-8000-000000000001','UTC','male',175,'1990-01-01','CUT');
insert into public.weigh_ins(user_id,measured_at,weight_kg,source,client_op_id) values
 ('33330000-0000-4000-8000-000000000001','2026-09-14 09:00+00',100,'manual',gen_random_uuid());
insert into public.body_composition(user_id,measured_at,user_day,measurement_source,input_weight_kg,body_fat_pct,lean_body_mass_kg,bmr_kcal) values
 ('33330000-0000-4000-8000-000000000001','2026-09-14 09:30+00','2026-09-14','device_bia',100,38,62,1950);
select set_config('nb.calculation_as_of','2026-09-15 12:00+00',true);
select set_config('nb.calculation_day','2026-09-15',true);
select is((select f.protein_g from nb.compute_fuel('33330000-0000-4000-8000-000000000001','2026-09-15') f),
  (select s.protein_g from nb.macro_split(100,175,'male','CUT',62,0,1500) s),
  'compute_fuel serves the split of the scanned lean mass');

select * from finish();
rollback;
