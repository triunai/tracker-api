create table public.tax_relief_claim (
  id bigserial not null,
  tax_year_id bigint not null,
  user_id uuid not null,
  tax_relief_category_id bigint not null,
  expense_item_id bigint null,
  document_id bigint null,
  dependent_id bigint null,
  claim_source text not null default 'manual'::text,
  claimed_amount numeric(10, 2) not null default 0,
  eligible_amount numeric(10, 2) null,
  status text not null default 'draft'::text,
  override_reason text null,
  notes text null,
  created_by uuid null,
  created_at timestamp without time zone not null default now(),
  updated_by uuid null,
  updated_at timestamp without time zone null,
  isdeleted boolean not null default false,
  constraint tax_relief_claim_pkey primary key (id),
  constraint fk_tax_relief_claim_tax_year foreign key (tax_year_id) references tax_year (id) on delete cascade,
  constraint fk_tax_relief_claim_user foreign key (user_id) references auth.users (id),
  constraint fk_tax_relief_claim_tax_relief_category foreign key (tax_relief_category_id) references tax_relief_category (id),
  constraint fk_tax_relief_claim_expense_item foreign key (expense_item_id) references expense_item (id) on delete set null,
  constraint fk_tax_relief_claim_document foreign key (document_id) references documents (id) on delete set null,
  constraint fk_tax_relief_claim_dependent foreign key (dependent_id) references tax_dependent (id) on delete set null,
  constraint tax_relief_claim_claim_source_check check (
    claim_source = any (array['auto_mapped'::text, 'manual'::text, 'fixed_relief'::text])
  ),
  constraint tax_relief_claim_claimed_amount_check check (claimed_amount >= 0),
  constraint tax_relief_claim_eligible_amount_check check (
    (eligible_amount is null) or (eligible_amount >= 0)
  ),
  constraint tax_relief_claim_status_check check (
    status = any (array['draft'::text, 'confirmed'::text, 'rejected'::text])
  )
) TABLESPACE pg_default;

create index IF not exists idx_tax_relief_claim_tax_year_id on public.tax_relief_claim using btree (tax_year_id) TABLESPACE pg_default
where
  (isdeleted = false);

create index IF not exists idx_tax_relief_claim_user_id on public.tax_relief_claim using btree (user_id) TABLESPACE pg_default
where
  (isdeleted = false);

create index IF not exists idx_tax_relief_claim_category_id on public.tax_relief_claim using btree (tax_relief_category_id) TABLESPACE pg_default
where
  (isdeleted = false);

create index IF not exists idx_tax_relief_claim_dependent_id on public.tax_relief_claim using btree (dependent_id) TABLESPACE pg_default
where
  (
    (dependent_id is not null)
    and (isdeleted = false)
  );

create unique index IF not exists ux_tax_relief_claim_expense_item on public.tax_relief_claim using btree (tax_year_id, expense_item_id) TABLESPACE pg_default
where
  (
    (expense_item_id is not null)
    and (isdeleted = false)
  );
