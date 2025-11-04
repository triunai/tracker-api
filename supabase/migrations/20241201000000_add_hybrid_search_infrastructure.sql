-- Enable required extensions for hybrid search
CREATE EXTENSION IF NOT EXISTS vector;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- Add FTS and embedding columns to expense table (singular, not plural!)
ALTER TABLE expense 
ADD COLUMN IF NOT EXISTS fts tsvector,
ADD COLUMN IF NOT EXISTS embedding vector(768);

-- Add FTS and embedding columns to expense_item table
ALTER TABLE expense_item
ADD COLUMN IF NOT EXISTS fts tsvector,
ADD COLUMN IF NOT EXISTS embedding vector(768);

-- Create embedding jobs queue table
CREATE TABLE IF NOT EXISTS embedding_jobs (
  id bigserial PRIMARY KEY,
  table_name text NOT NULL,
  record_id bigint NOT NULL,
  content text NOT NULL,
  status text DEFAULT 'pending' CHECK (status IN ('pending', 'processing', 'completed', 'failed')),
  created_at timestamp with time zone DEFAULT now(),
  processed_at timestamp with time zone,
  error_message text,
  UNIQUE(table_name, record_id)
);

-- Create hybrid search result type
CREATE TYPE hybrid_search_result AS (
  id bigint,
  table_name text,
  content text,
  fts_rank real,
  semantic_rank real,
  rrf_rank real,
  metadata jsonb
);

-- Create GIN indexes for full-text search
CREATE INDEX IF NOT EXISTS idx_expense_fts ON expense USING gin(fts);
CREATE INDEX IF NOT EXISTS idx_expense_item_fts ON expense_item USING gin(fts);

-- Create HNSW indexes for vector similarity (after embeddings are populated)
-- Note: These will be added later when we have data, as empty vector columns can't be indexed
-- CREATE INDEX idx_expense_embedding ON expense USING hnsw (embedding vector_ip_ops);
-- CREATE INDEX idx_expense_item_embedding ON expense_item USING hnsw (embedding vector_ip_ops);

-- Create triggers to automatically populate FTS columns
CREATE OR REPLACE FUNCTION update_expense_fts() 
RETURNS TRIGGER AS $$
BEGIN
  -- Combine expense description with payment method and category info
  NEW.fts := to_tsvector('english', 
    COALESCE(NEW.description, '') || ' ' ||
    COALESCE((SELECT method_name FROM payment_methods WHERE id = NEW.payment_method_id), '') || ' ' ||
    COALESCE((SELECT string_agg(ec.name || ' ' || COALESCE(ic.name, ''), ' ') 
              FROM expense_item ei 
              LEFT JOIN expense_category ec ON ei.category_id = ec.id
              LEFT JOIN income_category ic ON ei.income_category_id = ic.id
              WHERE ei.expense_id = NEW.id), '')
  );
  
  -- Queue for embedding generation
  INSERT INTO embedding_jobs (table_name, record_id, content)
  VALUES ('expense', NEW.id, 
    COALESCE(NEW.description, '') || ' ' ||
    COALESCE((SELECT method_name FROM payment_methods WHERE id = NEW.payment_method_id), '')
  )
  ON CONFLICT (table_name, record_id) 
  DO UPDATE SET 
    content = EXCLUDED.content,
    status = 'pending',
    created_at = now();
    
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION update_expense_item_fts() 
RETURNS TRIGGER AS $$
BEGIN
  -- Combine expense_item description with category info
  NEW.fts := to_tsvector('english', 
    COALESCE(NEW.description, '') || ' ' ||
    COALESCE((SELECT name FROM expense_category WHERE id = NEW.category_id), '') || ' ' ||
    COALESCE((SELECT name FROM income_category WHERE id = NEW.income_category_id), '')
  );
  
  -- Queue for embedding generation
  INSERT INTO embedding_jobs (table_name, record_id, content)
  VALUES ('expense_item', NEW.id, 
    COALESCE(NEW.description, '') || ' ' ||
    COALESCE((SELECT name FROM expense_category WHERE id = NEW.category_id), '') || ' ' ||
    COALESCE((SELECT name FROM income_category WHERE id = NEW.income_category_id), '')
  )
  ON CONFLICT (table_name, record_id) 
  DO UPDATE SET 
    content = EXCLUDED.content,
    status = 'pending',
    created_at = now();
    
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create triggers
DROP TRIGGER IF EXISTS expense_fts_update ON expense;
CREATE TRIGGER expense_fts_update 
  BEFORE INSERT OR UPDATE ON expense
  FOR EACH ROW EXECUTE FUNCTION update_expense_fts();

DROP TRIGGER IF EXISTS expense_item_fts_update ON expense_item;
CREATE TRIGGER expense_item_fts_update 
  BEFORE INSERT OR UPDATE ON expense_item
  FOR EACH ROW EXECUTE FUNCTION update_expense_item_fts();

-- Populate FTS for existing records
UPDATE expense SET fts = to_tsvector('english', 
  COALESCE(description, '') || ' ' ||
  COALESCE((SELECT method_name FROM payment_methods WHERE id = expense.payment_method_id), '')
) WHERE fts IS NULL;

UPDATE expense_item SET fts = to_tsvector('english', 
  COALESCE(description, '') || ' ' ||
  COALESCE((SELECT name FROM expense_category WHERE id = expense_item.category_id), '') || ' ' ||
  COALESCE((SELECT name FROM income_category WHERE id = expense_item.income_category_id), '')
) WHERE fts IS NULL;

-- Queue existing records for embedding generation
INSERT INTO embedding_jobs (table_name, record_id, content)
SELECT 'expense', id, 
  COALESCE(description, '') || ' ' ||
  COALESCE((SELECT method_name FROM payment_methods WHERE id = expense.payment_method_id), '')
FROM expense
ON CONFLICT (table_name, record_id) DO NOTHING;

INSERT INTO embedding_jobs (table_name, record_id, content)
SELECT 'expense_item', id,
  COALESCE(description, '') || ' ' ||
  COALESCE((SELECT name FROM expense_category WHERE id = expense_item.category_id), '') || ' ' ||
  COALESCE((SELECT name FROM income_category WHERE id = expense_item.income_category_id), '')
FROM expense_item
ON CONFLICT (table_name, record_id) DO NOTHING;

-- Basic hybrid search function (will be enhanced in Step 2)
CREATE OR REPLACE FUNCTION zenith_hybrid_search(
  p_user_id uuid,
  p_query_text text,
  p_match_limit int DEFAULT 20
)
RETURNS SETOF hybrid_search_result AS $$
BEGIN
  -- For now, just return FTS results (semantic search will be added in Step 2)
  RETURN QUERY
  WITH expense_results AS (
    SELECT 
      e.id,
      'expense'::text as table_name,
      COALESCE(e.description, '') as content,
      ts_rank_cd(e.fts, plainto_tsquery('english', p_query_text))::real as fts_rank,
      0::real as semantic_rank,
      ts_rank_cd(e.fts, plainto_tsquery('english', p_query_text))::real as rrf_rank,
      jsonb_build_object(
        'date', e.date,
        'payment_method_id', e.payment_method_id,
        'total_amount', (SELECT sum(amount) FROM expense_item WHERE expense_id = e.id)
      ) as metadata
    FROM expense e
    WHERE e.user_id = p_user_id 
      AND e.isdeleted = false
      AND e.fts @@ plainto_tsquery('english', p_query_text)
    ORDER BY fts_rank DESC
    LIMIT p_match_limit
  ),
  expense_item_results AS (
    SELECT 
      ei.id,
      'expense_item'::text as table_name,
      COALESCE(ei.description, '') as content,
      ts_rank_cd(ei.fts, plainto_tsquery('english', p_query_text))::real as fts_rank,
      0::real as semantic_rank,
      ts_rank_cd(ei.fts, plainto_tsquery('english', p_query_text))::real as rrf_rank,
      jsonb_build_object(
        'amount', ei.amount,
        'category_id', ei.category_id,
        'income_category_id', ei.income_category_id,
        'expense_id', ei.expense_id
      ) as metadata
    FROM expense_item ei
    JOIN expense e ON ei.expense_id = e.id
    WHERE e.user_id = p_user_id 
      AND ei.isdeleted = false
      AND e.isdeleted = false
      AND ei.fts @@ plainto_tsquery('english', p_query_text)
    ORDER BY fts_rank DESC
    LIMIT p_match_limit
  )
  SELECT * FROM expense_results
  UNION ALL
  SELECT * FROM expense_item_results
  ORDER BY rrf_rank DESC
  LIMIT p_match_limit;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER; 