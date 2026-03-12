create table public.tax_year (
  id bigserial not null,
  user_id uuid not null,
  year_of_assessment integer not null,
  filing_status text not null default 'single'::text,
  income_profile text not null default 'non_business'::text,
  filing_deadline date generated always as (
    case
      when income_profile = any (array['business'::text, 'mixed'::text])
        then make_date((year_of_assessment + 1), 6, 30)
      else make_date((year_of_assessment + 1), 4, 30)
    end
  ) stored,
  status text not null default 'draft'::text,
  total_income numeric(12, 2) not null default 0,
  total_deductions numeric(12, 2) not null default 0,
  total_relief numeric(12, 2) not null default 0,
  chargeable_income numeric(12, 2) not null default 0,
  tax_payable numeric(12, 2) not null default 0,
  submitted_at timestamp with time zone null,
  created_by uuid null,
  created_at timestamp without time zone not null default now(),
  updated_by uuid null,
  updated_at timestamp without time zone null,
  isdeleted boolean not null default false,
  constraint tax_year_pkey primary key (id),
  constraint fk_tax_year_user foreign key (user_id) references auth.users (id),
  constraint tax_year_filing_status_check check (
    filing_status = any (array['single'::text, 'married_joint'::text, 'married_separate'::text])
  ),
  constraint tax_year_income_profile_check check (
    income_profile = any (array['non_business'::text, 'business'::text, 'mixed'::text])
  ),
  constraint tax_year_status_check check (
    status = any (array['draft'::text, 'ready_for_review'::text, 'filed'::text, 'amended'::text])
  ),
  constraint tax_year_year_of_assessment_check check (year_of_assessment >= 2025)
) TABLESPACE pg_default;

create unique index IF not exists ux_tax_year_user_ya on public.tax_year using btree (user_id, year_of_assessment) TABLESPACE pg_default
where
  (isdeleted = false);

create index IF not exists idx_tax_year_user_id on public.tax_year using btree (user_id) TABLESPACE pg_default;

create index IF not exists idx_tax_year_status on public.tax_year using btree (status) TABLESPACE pg_default
where
  (isdeleted = false);
