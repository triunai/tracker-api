create table public.expense_item (
  id bigserial not null,
  expense_id bigint not null,
  category_id bigint null,
  amount numeric(10, 2) not null,
  description text null,
  created_by uuid null,
  created_at timestamp without time zone not null default now(),
  updated_by uuid null,
  updated_at timestamp without time zone null,
  isdeleted boolean not null default false,
  income_category_id bigint null,
  fts tsvector null,
  constraint expense_item_pkey primary key (id),
  constraint fk_expense_item_category foreign KEY (category_id) references expense_category (id),
  constraint fk_expense_item_expense foreign KEY (expense_id) references expense (id),
  constraint fk_expense_item_income_category foreign KEY (income_category_id) references income_category (id),
  constraint check_single_category check (
    (
      (
        (category_id is null)
        and (income_category_id is not null)
      )
      or (
        (category_id is not null)
        and (income_category_id is null)
      )
    )
  )
) TABLESPACE pg_default;

create index IF not exists idx_expense_item_fts on public.expense_item using gin (fts) TABLESPACE pg_default;