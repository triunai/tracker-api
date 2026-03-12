create table public.tax_relief_category (
  id bigserial not null,
  code character varying(100) not null,
  name character varying(200) not null,
  description text null,
  display_group character varying(80) not null,
  sort_order smallint not null,
  amount_type text not null default 'up_to'::text,
  max_amount numeric(10, 2) null,
  sub_limit_amount numeric(10, 2) null,
  shared_limit_group character varying(100) null,
  requires_receipt boolean not null default true,
  requires_manual_review boolean not null default false,
  effective_from_ya integer not null,
  effective_to_ya integer null,
  is_active boolean not null default true,
  created_at timestamp without time zone not null default now(),
  constraint tax_relief_category_pkey primary key (id),
  constraint tax_relief_category_code_key unique (code),
  constraint tax_relief_category_amount_type_check check (
    amount_type = any (array['fixed'::text, 'up_to'::text, 'per_child'::text, 'net_deposit'::text, 'calculated'::text])
  )
) TABLESPACE pg_default;

create index IF not exists idx_tax_relief_category_group on public.tax_relief_category using btree (display_group, sort_order) TABLESPACE pg_default;

create index IF not exists idx_tax_relief_category_effective_year on public.tax_relief_category using btree (effective_from_ya, effective_to_ya) TABLESPACE pg_default;

create index IF not exists idx_tax_relief_category_shared_limit_group on public.tax_relief_category using btree (shared_limit_group) TABLESPACE pg_default
where
  (shared_limit_group is not null);
