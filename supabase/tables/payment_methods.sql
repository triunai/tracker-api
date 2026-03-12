create table public.payment_methods (
  id serial not null,
  method_name character varying(50) not null,
  created_by uuid null,
  created_at timestamp without time zone not null default now(),
  updated_by uuid null,
  updated_at timestamp without time zone null,
  isdeleted boolean not null default false,
  user_id uuid null,
  icon text null,
  constraint payment_methods_pkey primary key (id)
) TABLESPACE pg_default;

create unique INDEX IF not exists ux_payment_methods_global_name on public.payment_methods using btree (method_name) TABLESPACE pg_default
where
  (
    (user_id is null)
    and (isdeleted = false)
  );

create unique INDEX IF not exists ux_payment_methods_user_name on public.payment_methods using btree (user_id, method_name) TABLESPACE pg_default
where
  (
    (user_id is not null)
    and (isdeleted = false)
  );

create index IF not exists idx_payment_methods_user on public.payment_methods using btree (user_id) TABLESPACE pg_default
where
  (isdeleted = false);

create trigger set_user_id_payment_methods BEFORE INSERT on payment_methods for EACH row
execute FUNCTION set_user_id_on_insert ();

// GLOBAL DEFAULTS DOWN HERE
[
  {
    "id": 1,
    "method_name": "QR"
  },
  {
    "id": 2,
    "method_name": "Cash"
  },
  {
    "id": 3,
    "method_name": "Debit"
  },
  {
    "id": 4,
    "method_name": "Touch 'n Go"
  },
  {
    "id": 5,
    "method_name": "Online Banking"
  }
]