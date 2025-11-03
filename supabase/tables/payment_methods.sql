create table public.payment_methods (
  id serial not null,
  method_name character varying(50) not null,
  created_by uuid null,
  created_at timestamp without time zone not null default now(),
  updated_by uuid null,
  updated_at timestamp without time zone null,
  isdeleted boolean not null default false,
  constraint payment_methods_pkey primary key (id),
  constraint payment_methods_method_name_key unique (method_name)
) TABLESPACE pg_default;