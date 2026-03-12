create table public.income_category (
  id bigserial not null,
  name character varying(100) not null,
  description text not null,
  created_by uuid null,
  created_at timestamp without time zone not null default now(),
  updated_by uuid null,
  updated_at timestamp without time zone null,
  isdeleted boolean not null default false,
  user_id uuid null,
  icon text null,
  constraint income_category_pkey primary key (id)
) TABLESPACE pg_default;

create unique INDEX IF not exists ux_income_category_global_name on public.income_category using btree (name) TABLESPACE pg_default
where
  (
    (user_id is null)
    and (isdeleted = false)
  );

create unique INDEX IF not exists ux_income_category_user_name on public.income_category using btree (user_id, name) TABLESPACE pg_default
where
  (
    (user_id is not null)
    and (isdeleted = false)
  );

create index IF not exists idx_income_category_user on public.income_category using btree (user_id) TABLESPACE pg_default
where
  (isdeleted = false);

create trigger set_user_id_income_category BEFORE INSERT on income_category for EACH row
execute FUNCTION set_user_id_on_insert ();