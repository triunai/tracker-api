create table public.budget_category (
  budget_id bigint not null,
  category_id bigint not null,
  alert_threshold numeric(10, 2) null,
  created_by uuid null,
  created_at timestamp without time zone not null default now(),
  updated_by uuid null,
  updated_at timestamp without time zone null,
  isdeleted boolean not null default false,
  constraint budget_category_pkey primary key (budget_id, category_id),
  constraint fk_budgetcat_budget foreign KEY (budget_id) references budget (id),
  constraint fk_budgetcat_category foreign KEY (category_id) references expense_category (id)
) TABLESPACE pg_default;