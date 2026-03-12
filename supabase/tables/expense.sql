create table public.expense (
  id bigserial not null,
  user_id uuid not null,
  date timestamp without time zone not null default now(),
  description text null,
  payment_method_id integer null,
  created_by uuid null,
  created_at timestamp without time zone not null default now(),
  updated_by uuid null,
  updated_at timestamp without time zone null,
  isdeleted boolean not null default false,
  transaction_type character varying(10) not null default 'expense'::character varying,
  fts tsvector null,
  embedding public.vector null,
  constraint expense_pkey primary key (id),
  constraint expense_payment_method_id_fkey foreign KEY (payment_method_id) references payment_methods (id),
  constraint fk_expense_user foreign KEY (user_id) references auth.users (id),
  constraint expense_transaction_type_check check (
    (
      (transaction_type)::text = any (
        array[
          ('income'::character varying)::text,
          ('expense'::character varying)::text
        ]
      )
    )
  )
) TABLESPACE pg_default;

create index IF not exists idx_expense_fts on public.expense using gin (fts) TABLESPACE pg_default;

create index IF not exists idx_expense_embedding on public.expense using hnsw (embedding vector_cosine_ops)
with
  (m = '16', ef_construction = '64') TABLESPACE pg_default;

create trigger expense_fts_update BEFORE INSERT
or
update on expense for EACH row
execute FUNCTION update_expense_fts ();