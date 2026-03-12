create table public.expense_category_tax_relief_mapping (
  id bigserial not null,
  expense_category_id bigint not null,
  tax_relief_category_id bigint not null,
  year_of_assessment integer not null,
  mapping_strength text not null default 'suggested'::text,
  confidence_score numeric(3, 2) not null default 0.80,
  requires_manual_override boolean not null default false,
  notes text null,
  created_by uuid null,
  created_at timestamp without time zone not null default now(),
  updated_by uuid null,
  updated_at timestamp without time zone null,
  isdeleted boolean not null default false,
  constraint expense_category_tax_relief_mapping_pkey primary key (id),
  constraint fk_ectrm_expense_category foreign key (expense_category_id) references expense_category (id) on delete cascade,
  constraint fk_ectrm_tax_relief_category foreign key (tax_relief_category_id) references tax_relief_category (id) on delete cascade,
  constraint expense_category_tax_relief_mapping_mapping_strength_check check (
    mapping_strength = any (array['suggested'::text, 'strong'::text, 'manual_only'::text, 'excluded'::text])
  ),
  constraint expense_category_tax_relief_mapping_confidence_score_check check (
    (confidence_score >= 0.00) and (confidence_score <= 1.00)
  ),
  constraint expense_category_tax_relief_mapping_year_of_assessment_check check (year_of_assessment >= 2025)
) TABLESPACE pg_default;

create unique index IF not exists ux_expense_category_tax_relief_mapping on public.expense_category_tax_relief_mapping using btree (expense_category_id, tax_relief_category_id, year_of_assessment) TABLESPACE pg_default
where
  (isdeleted = false);

create index IF not exists idx_ectrm_expense_category_id on public.expense_category_tax_relief_mapping using btree (expense_category_id) TABLESPACE pg_default
where
  (isdeleted = false);

create index IF not exists idx_ectrm_tax_relief_category_id on public.expense_category_tax_relief_mapping using btree (tax_relief_category_id) TABLESPACE pg_default
where
  (isdeleted = false);
