create table public.tax_dependent (
  id bigserial not null,
  user_id uuid not null,
  tax_year_id bigint not null,
  name character varying(200) not null,
  relationship text not null,
  date_of_birth date null,
  is_disabled boolean not null default false,
  is_studying boolean not null default false,
  study_level text null,
  study_location text null,
  is_married boolean not null default false,
  notes text null,
  created_at timestamp without time zone not null default now(),
  updated_at timestamp without time zone null,
  isdeleted boolean not null default false,
  constraint tax_dependent_pkey primary key (id),
  constraint fk_tax_dependent_user foreign key (user_id) references auth.users (id),
  constraint fk_tax_dependent_tax_year foreign key (tax_year_id) references tax_year (id) on delete cascade,
  constraint tax_dependent_relationship_check check (
    relationship = any (
      array[
        'child'::text,
        'spouse'::text,
        'parent'::text,
        'grandparent'::text,
        'sibling'::text
      ]
    )
  ),
  constraint tax_dependent_study_level_check check (
    (
      study_level is null
      or study_level = any (
        array[
          'pre_university'::text,
          'diploma'::text,
          'degree'::text,
          'masters'::text,
          'doctorate'::text
        ]
      )
    )
  ),
  constraint tax_dependent_study_location_check check (
    (
      study_location is null
      or study_location = any (
        array['malaysia'::text, 'outside_malaysia'::text]
      )
    )
  )
) TABLESPACE pg_default;

create index IF not exists idx_tax_dependent_user_id on public.tax_dependent using btree (user_id) TABLESPACE pg_default
where
  (isdeleted = false);

create index IF not exists idx_tax_dependent_tax_year_id on public.tax_dependent using btree (tax_year_id) TABLESPACE pg_default
where
  (isdeleted = false);

create unique index IF not exists ux_tax_dependent_identity on public.tax_dependent using btree (user_id, tax_year_id, name, relationship) TABLESPACE pg_default
where
  (isdeleted = false);
