create table public.budget (
  id bigserial not null,
  user_id uuid not null,
  name character varying(100) not null,
  amount numeric(10, 2) not null,
  period public.period_enum not null,
  start_date date null default now(),
  end_date date null,
  created_by uuid null,
  created_at timestamp without time zone not null default now(),
  updated_by uuid null,
  updated_at timestamp without time zone null,
  isdeleted boolean not null default false,
  constraint budget_pkey primary key (id),
  constraint fk_budget_user foreign KEY (user_id) references auth.users (id)
) TABLESPACE pg_default;