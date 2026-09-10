-- Suggestions may be empty when current evidence supports no useful adjustment.
-- Keep the same table, owner policies and maximum; no task/check migration is needed.
alter table public.daily_plans drop constraint daily_plans_tasks_check;
alter table public.daily_plans add constraint daily_plans_tasks_check
  check (jsonb_typeof(tasks) = 'array' and jsonb_array_length(tasks) between 0 and 5);
