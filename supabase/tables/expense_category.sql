create table public.expense_category (
  id bigserial not null,
  name character varying(100) not null,
  description text not null,
  created_by uuid null,
  created_at timestamp without time zone not null default now(),
  updated_by uuid null,
  updated_at timestamp without time zone null,
  isdeleted boolean not null default false,
  constraint expense_category_pkey primary key (id),
  constraint expense_category_name_key unique (name)
) TABLESPACE pg_default;