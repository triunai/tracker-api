create table public.user_profiles (
  id uuid not null,
  display_name character varying(100) null,
  email character varying(255) not null,
  avatar_url text null,
  created_at timestamp with time zone null default now(),
  updated_at timestamp with time zone null,
  preferences jsonb null default '{}'::jsonb,
  is_active boolean null default true,
  constraint user_profiles_pkey primary key (id),
  constraint user_profiles_id_fkey foreign KEY (id) references auth.users (id)
) TABLESPACE pg_default;