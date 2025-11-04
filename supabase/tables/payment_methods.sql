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


//GLOBAL DEFAULTS DOWN HERE

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