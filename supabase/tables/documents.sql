create table public.documents (
  id bigserial not null,
  user_id uuid not null,
  file_path text not null,
  original_filename text not null,
  file_size bigint not null,
  mime_type text not null,
  status text not null default 'uploaded'::text,
  raw_markdown_output text null,
  processing_error text null,
  document_type text null,
  vendor_name text null,
  transaction_date date null,
  total_amount numeric(10, 2) null,
  currency text null default 'USD'::text,
  transaction_type text null,
  suggested_category_id bigint null,
  suggested_category_type text null,
  ai_confidence_score numeric(3, 2) null,
  suggested_payment_method_id integer null,
  created_expense_id bigint null,
  created_by uuid null,
  created_at timestamp without time zone not null default now(),
  updated_by uuid null,
  updated_at timestamp without time zone null,
  isdeleted boolean not null default false,
  constraint documents_pkey primary key (id),
  constraint documents_suggested_payment_method_id_fkey foreign KEY (suggested_payment_method_id) references payment_methods (id),
  constraint documents_created_expense_id_fkey foreign KEY (created_expense_id) references expense (id),
  constraint documents_user_id_fkey foreign KEY (user_id) references auth.users (id),
  constraint documents_transaction_type_check check (
    (
      transaction_type = any (array['expense'::text, 'income'::text])
    )
  ),
  constraint documents_status_check check (
    (
      status = any (
        array[
          'uploaded'::text,
          'processing'::text,
          'ocr_completed'::text,
          'parsed'::text,
          'transaction_created'::text,
          'failed'::text
        ]
      )
    )
  ),
  constraint documents_document_type_check check (
    (
      document_type = any (
        array[
          'receipt'::text,
          'invoice'::text,
          'bank_statement'::text,
          'other'::text
        ]
      )
    )
  ),
  constraint documents_ai_confidence_score_check check (
    (
      (ai_confidence_score >= 0.00)
      and (ai_confidence_score <= 1.00)
    )
  ),
  constraint documents_suggested_category_type_check check (
    (
      suggested_category_type = any (array['expense'::text, 'income'::text])
    )
  )
) TABLESPACE pg_default;

create index IF not exists idx_documents_user_id on public.documents using btree (user_id) TABLESPACE pg_default;

create index IF not exists idx_documents_status on public.documents using btree (status) TABLESPACE pg_default;

create index IF not exists idx_documents_created_at on public.documents using btree (created_at) TABLESPACE pg_default;

create index IF not exists idx_documents_transaction_date on public.documents using btree (transaction_date) TABLESPACE pg_default;