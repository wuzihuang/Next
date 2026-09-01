-- F3 · 数据与同步. Seventeen tables, not one fewer.
-- daily_results carries "one source, one instant"; sync_runs is what the word SYNCED stands on.
--
-- Two laws are enforced by Postgres, not by code review:
--   · unknown never degrades to 0 — the data layer writes null, the screen writes "——"
--   · a meal is never UPDATEd — an edit is a soft delete plus a new row

create extension if not exists "pgcrypto" with schema extensions;

-- ---------------------------------------------------------------- profiles

create table public.profiles (
  user_id       uuid primary key references auth.users (id) on delete cascade,
  timezone      text not null default 'UTC',
  sex           text check (sex in ('male', 'female')),
  height_cm     numeric(4, 1) check (height_cm between 80 and 250),
  birth_date    date,
  goal          text not null default 'RECOMP' check (goal in ('CUT', 'RECOMP', 'BULK')),
  units_metric  boolean not null default true,
  locale        text not null default 'zh-CN',
  -- F3 §02.3 · per-field provenance. A field marked "edit" is skipped by every later
  -- HealthKit sync — we do not compare timestamps, and we never win against the user.
  field_sources jsonb not null default '{}'::jsonb,
  deletion_requested_at timestamptz,
  created_at    timestamptz not null default now()
);

-- ---------------------------------------------------------------- devices

create table public.devices (
  id                    uuid primary key default extensions.gen_random_uuid(),
  user_id               uuid not null references auth.users (id) on delete cascade,
  -- ⚠️ On iOS this is a CoreBluetooth UUID, not a MAC. It changes with the phone,
  -- so it can never be a cross-platform device identity. The primary key is id.
  ble_identifier        text not null,
  ble_identifier_kind   text not null check (ble_identifier_kind in ('uuid', 'mac')),
  device_number         text,
  firmware_version      text,
  -- ⚠️ Three battery columns together: firmware with isPercent = false only reports
  -- 0–4 bars, and collapsing them into one column loses "82%" vs "4 bars" forever.
  battery_percent       smallint check (battery_percent between 0 and 100),
  battery_level         smallint check (battery_level between 0 and 4),
  battery_is_percent    boolean,
  bound_at              timestamptz not null default now(),
  unbound_at            timestamptz,
  last_origin_sync_at   timestamptz
);

-- One account, one band.
create unique index devices_one_bound_per_user
  on public.devices (user_id) where unbound_at is null;
create index devices_user_id_idx on public.devices (user_id);

-- ---------------------------------------------------------------- device_capabilities

create table public.device_capabilities (
  device_id             uuid primary key references public.devices (id) on delete cascade,
  user_id               uuid not null references auth.users (id) on delete cascade,
  read_at               timestamptz not null default now(),
  functions             jsonb not null default '{}'::jsonb,
  watch_data_day_number smallint,
  -- FunctionStatus values are stored verbatim, never squashed into a boolean:
  -- on screen "unknown" and "unsupported" both mean the row is not rendered,
  -- but when debugging they are two different problems.
  body_component        text,
  ecg                   text,
  hrv                   text,
  stress                text,
  auto_measure          text
);
create index device_capabilities_user_id_idx on public.device_capabilities (user_id);

-- ---------------------------------------------------------------- raw_samples

create table public.raw_samples (
  user_id      uuid not null references auth.users (id) on delete cascade,
  -- F2 rule 04 · UTC instant plus the tz the batch was collected in.
  -- No user_day column: the window is re-cut at settle time.
  ts           timestamptz not null,
  sampled_tz   text not null,
  day_offset   smallint not null default 0,
  calendar_day date not null,
  heart        smallint,
  step         integer,
  cal          integer,
  dis          integer,
  met          numeric(4, 2),
  spo2         smallint,
  temp         numeric(4, 2),
  stress       smallint,
  sleep_states smallint,
  src          text not null default 'band',
  primary key (user_id, ts, src)
);
create index raw_samples_user_ts_idx on public.raw_samples (user_id, ts desc);

-- ---------------------------------------------------------------- daily_results

create table public.daily_results (
  id                  uuid not null default extensions.gen_random_uuid(),
  user_id             uuid not null references auth.users (id) on delete cascade,
  -- F2 rule 03 · the user day. Local 04:00 → 04:00; dayOffset is a paging parameter only.
  user_day            date not null,
  training_load       numeric(4, 1) check (training_load between 0 and 21),
  reserve_score       smallint check (reserve_score between 0 and 100),
  fuel_balance_kcal   integer,
  daily_direction     text check (daily_direction in
                        ('DEFICIT', 'LEVEL', 'SURPLUS', 'GREY_NOTHING', 'GREY_NO_BURN')),
  the_call            text check (the_call in ('RECOMP', 'CUT', 'BULK', 'DRIFT', 'NO_CHANGE')),
  the_call_confidence text check (the_call_confidence in ('PENDING', 'MEDIUM', 'HIGH')),
  algo_version        text not null,
  inputs_hash         text,
  computed_at         timestamptz not null default now(),
  primary key (user_id, user_day),
  unique (id)
);
create index daily_results_user_day_idx on public.daily_results (user_id, user_day desc);

-- ---------------------------------------------------------------- daily_training

create table public.daily_training (
  result_id     uuid primary key references public.daily_results (id) on delete cascade,
  user_id       uuid not null references auth.users (id) on delete cascade,
  -- ⚠️ Every zone duration is a multiple of 5: the raw points are five minutes apart.
  zone_minutes  smallint[5] not null default '{0,0,0,0,0}',
  peak_hr       smallint,
  session_count smallint not null default 0,
  curve         jsonb not null default '[]'::jsonb
);
create index daily_training_user_id_idx on public.daily_training (user_id);

-- ---------------------------------------------------------------- reserve_*

-- ⚠️ Neutral table names on purpose: Body Battery is a token that may be renamed,
-- and a renamed metric must not require a migration.
create table public.reserve_samples (
  user_id uuid not null references auth.users (id) on delete cascade,
  ts      timestamptz not null,
  value   smallint not null check (value between 0 and 100),
  source  text not null default 'model',
  primary key (user_id, ts)
);
create index reserve_samples_user_ts_idx on public.reserve_samples (user_id, ts desc);

create table public.reserve_daily (
  result_id     uuid primary key references public.daily_results (id) on delete cascade,
  user_id       uuid not null references auth.users (id) on delete cascade,
  wake_value    smallint check (wake_value between 0 and 100),
  min_value     smallint check (min_value between 0 and 100),
  current_value smallint check (current_value between 0 and 100),
  -- 13 · the four attribution rows land here
  drain_drivers jsonb not null default '{}'::jsonb
);
create index reserve_daily_user_id_idx on public.reserve_daily (user_id);

-- ---------------------------------------------------------------- sleep_nights

-- D01 · input only, never rendered. Keyed to the day you woke up, because
-- "how was last night" appears on today's screen.
create table public.sleep_nights (
  user_id       uuid not null references auth.users (id) on delete cascade,
  user_day      date not null,
  total_minutes smallint,
  deep_minutes  smallint,
  light_minutes smallint,
  wake_count    smallint,
  raw           jsonb not null default '{}'::jsonb,
  primary key (user_id, user_day)
);

-- ---------------------------------------------------------------- body_composition

create table public.body_composition (
  id                 uuid primary key default extensions.gen_random_uuid(),
  user_id            uuid not null references auth.users (id) on delete cascade,
  measured_at        timestamptz not null,
  user_day           date not null,
  measurement_source text not null check (measurement_source in ('device_bia', 'health_scale', 'manual')),
  -- ⚠️ The band produces no weight: BodyCompositionTestResult has no weight field.
  -- Its BIA numbers are computed from the weight we pushed down via syncPersonalInfo.
  input_weight_kg    numeric(5, 2) not null check (input_weight_kg > 20),
  input_weight_id    uuid,
  body_fat_pct       numeric(4, 2),
  fat_mass_kg        numeric(5, 2),
  lean_body_mass_kg  numeric(5, 2),
  bmr_kcal           integer,
  -- F0 rule 09 · MEASURED re-anchors, DERIVED does not. Marked per field.
  derived_fields     text[] not null default '{}'
);
create index body_composition_user_measured_idx
  on public.body_composition (user_id, measured_at desc);

-- ---------------------------------------------------------------- weigh_ins

create table public.weigh_ins (
  id           uuid primary key default extensions.gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  measured_at  timestamptz not null,
  sampled_tz   text not null default 'UTC',
  weight_kg    numeric(5, 2) not null check (weight_kg > 20),
  source       text not null check (source in ('health', 'manual', 'band')),
  health_uuid  text,
  client_op_id uuid not null
);
create unique index weigh_ins_client_op on public.weigh_ins (user_id, client_op_id);
-- The same Health record never enters the table twice.
create unique index weigh_ins_health_uuid on public.weigh_ins (user_id, health_uuid)
  where health_uuid is not null;
create index weigh_ins_user_measured_idx on public.weigh_ins (user_id, measured_at desc);

alter table public.body_composition
  add constraint body_composition_input_weight_fk
  foreign key (input_weight_id) references public.weigh_ins (id) on delete set null;
create index body_composition_input_weight_idx
  on public.body_composition (input_weight_id);

-- ---------------------------------------------------------------- meals

-- F3 §02.2 · append only. An edit is a soft delete plus a new row, because the AI's kcal
-- carries a model_version — rewriting it in place would make one row both March's model
-- and September's model.
create table public.meals (
  id           uuid primary key default extensions.gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  user_day     date not null,
  slot         text not null check (slot in ('BREAKFAST', 'LUNCH', 'DINNER', 'SNACK')),
  logged_at    timestamptz not null default now(),
  deleted_at   timestamptz,
  text_input   text,
  -- A 0 kcal meal does not exist: writing 0 means the parser failed.
  kcal         integer check (kcal is null or kcal > 0),
  protein_g    integer check (protein_g is null or protein_g >= 0),
  carb_g       integer check (carb_g is null or carb_g >= 0),
  fat_g        integer check (fat_g is null or fat_g >= 0),
  confidence   text check (confidence in ('LOW', 'MEDIUM', 'HIGH')),
  model_version text,
  client_op_id uuid not null
);
create unique index meals_client_op on public.meals (user_id, client_op_id);
create index meals_user_day_idx on public.meals (user_id, user_day desc)
  where deleted_at is null;

-- ---------------------------------------------------------------- day_fuel

create table public.day_fuel (
  result_id    uuid primary key references public.daily_results (id) on delete cascade,
  user_id      uuid not null references auth.users (id) on delete cascade,
  intake_state text not null check (intake_state in ('UNLOGGED', 'PARTIAL', 'FASTED', 'CONFIRMED')),
  kcal_in      integer,
  kcal_out     integer,
  slot_states  jsonb not null default '{}'::jsonb,
  -- F3 §02.1 · the two laws, as constraints rather than as a code-review habit.
  -- UNLOGGED writing 0 is rejected; FASTED writing null is rejected.
  constraint fuel_unlogged_is_null check ((intake_state = 'UNLOGGED') = (kcal_in is null)),
  constraint fuel_fasted_is_zero   check (intake_state <> 'FASTED' or kcal_in = 0)
);
create index day_fuel_user_id_idx on public.day_fuel (user_id);

-- ---------------------------------------------------------------- call_changes

-- 10 · "the call is never allowed to change silently" stands on this table.
create table public.call_changes (
  id           uuid primary key default extensions.gen_random_uuid(),
  user_id      uuid not null references auth.users (id) on delete cascade,
  user_day     date not null,
  call         text not null,
  prev_call    text,
  reason       text not null,
  changed_by   text not null,
  algo_version text not null,
  created_at   timestamptz not null default now(),
  seen_at      timestamptz
);
create index call_changes_user_day_idx on public.call_changes (user_id, user_day desc);

-- ---------------------------------------------------------------- screen_frames

-- 07 · every frame the panel has rendered. When something goes wrong we replay the screen,
-- not the model.
create table public.screen_frames (
  id            uuid primary key default extensions.gen_random_uuid(),
  user_id       uuid not null references auth.users (id) on delete cascade,
  created_at    timestamptz not null default now(),
  expires_at    timestamptz,
  trigger       text not null,
  widget_tree   jsonb not null,
  theme         jsonb,
  model_version text,
  latency_ms    integer,
  tool_calls    jsonb
);
create index screen_frames_user_created_idx on public.screen_frames (user_id, created_at desc);

-- ---------------------------------------------------------------- analytics_events

create table public.analytics_events (
  id            bigint generated always as identity primary key,
  user_id       uuid not null references auth.users (id) on delete cascade,
  name          text not null,
  props         jsonb not null default '{}'::jsonb,
  client_ts     timestamptz not null,
  server_ts     timestamptz not null default now(),
  app_version   text,
  device_model  text
);
create index analytics_events_user_ts_idx on public.analytics_events (user_id, server_ts desc);

-- ---------------------------------------------------------------- sync_runs

create table public.sync_runs (
  id             uuid primary key default extensions.gen_random_uuid(),
  user_id        uuid not null references auth.users (id) on delete cascade,
  device_id      uuid references public.devices (id) on delete set null,
  started_at     timestamptz not null default now(),
  finished_at    timestamptz,
  -- outcome = 'partial' does not advance last_origin_sync_at, but the row is still written.
  outcome        text check (outcome in ('success', 'partial', 'failed', 'aborted')),
  days_requested smallint,
  days_returned  smallint,
  error_code     text
);
create index sync_runs_user_started_idx on public.sync_runs (user_id, started_at desc);
create index sync_runs_device_idx on public.sync_runs (device_id);

-- ---------------------------------------------------------------- recompute_log

-- F2 §08 · a bulk UPDATE without a row here is an incident, not a migration.
create table public.recompute_log (
  id           bigint generated always as identity primary key,
  algo_version text not null,
  reason       text not null,
  rows_touched integer not null,
  executed_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------- ai_turns

create table public.ai_turns (
  id            uuid primary key,
  user_id       uuid not null references auth.users (id) on delete cascade,
  created_at    timestamptz not null default now(),
  user_text     text,
  -- Every tool call's arguments, return value and duration, so we can always go back and
  -- find out why she said what she said.
  tool_trace    jsonb not null default '[]'::jsonb,
  frame_id      uuid references public.screen_frames (id) on delete set null,
  model_version text,
  latency_ms    integer,
  outcome       text
);
create index ai_turns_user_created_idx on public.ai_turns (user_id, created_at desc);

-- ---------------------------------------------------------------- banned_phrases

-- F4 §05 · read once at boot and cached for five minutes. The first week after launch
-- will certainly add words, and adding a word must not require a release.
create table public.banned_phrases (
  id       bigint generated always as identity primary key,
  pattern  text not null,
  reason   text not null,
  replace_with text
);

insert into public.banned_phrases (pattern, reason, replace_with) values
  ('(?i)\bgreat job\b',        'praise presumes a persona judging the user', 'drop the sentence, keep the number'),
  ('(?i)\bnice work\b',        'praise presumes a persona judging the user', 'drop the sentence, keep the number'),
  ('(?i)\byou crushed it\b',   'praise presumes a persona judging the user', 'drop the sentence, keep the number'),
  ('(?i)\bkeep it up\b',       'praise presumes a persona judging the user', 'drop the sentence, keep the number'),
  ('(?i)\byou should\b',       'advice is health advice however it is wrapped', 'state the fact'),
  ('(?i)\btry to\b',           'advice is health advice however it is wrapped', 'state the fact'),
  ('(?i)\bconsider\b',         'advice is health advice however it is wrapped', 'state the fact'),
  ('(?i)i''d recommend',       'advice is health advice however it is wrapped', 'state the fact'),
  ('(?i)\bamazing\b',          'an adjective turns a measurement into a verdict', 'use a direction word'),
  ('(?i)\bimpressive\b',       'an adjective turns a measurement into a verdict', 'use a direction word'),
  ('(?i)\bnot bad\b',          'an adjective turns a measurement into a verdict', 'use a direction word'),
  ('(?i)a bit low',            'implies a normal range, which is grading',      'use a direction word'),
  ('(?i)\bprobably\b',         'hedging is the doorway to invented numbers',    'render ESTIMATE · LOW'),
  ('(?i)\bi think\b',          'hedging is the doorway to invented numbers',    'render ESTIMATE · LOW'),
  ('(?i)\bit seems\b',         'hedging is the doorway to invented numbers',    'render ESTIMATE · LOW'),
  ('(?i)\broughly\b',          'hedging is the doorway to invented numbers',    'render ESTIMATE · LOW'),
  ('(?i)\bunfortunately\b',    'emotional labour; she has no emotions',         'use the fixed failure phrase'),
  ('(?i)\bdon''t worry\b',     'emotional labour; she has no emotions',         'use the fixed failure phrase'),
  ('(?i)\b0 kcal\b',           'the most expensive mistake in the product',     'em dash, slot state OPEN'),
  ('(?i)\b0 g\b',              'the most expensive mistake in the product',     'em dash, slot state OPEN'),
  ('(?i)as an ai',             'exposes the model; the screen is the product',  'NOT MEASURED / BAND OFFLINE'),
  ('(?i)i''m unable to',       'exposes the model; the screen is the product',  'NOT MEASURED / BAND OFFLINE'),
  -- F0 D02 · the acceptance line is zero occurrences in the whole product.
  ('(?i)\brecovery\b',         'F0 D02 renamed it; the model will drift back',  'BODY BATTERY'),
  ('(?i)\bstrain\b',           'F0 D02 renamed it; the model will drift back',  'TRAINING LOAD');
