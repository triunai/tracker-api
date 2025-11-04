CREATE OR REPLACE FUNCTION public.get_expense_summary_by_category(
  p_user_id uuid,
  p_start_date date,
  p_end_date date
)
RETURNS TABLE (
  category_id bigint,
  category_name text,
  total numeric
) 
LANGUAGE plpgsql
AS $$
BEGIN
  RETURN QUERY
  SELECT
      ec.id AS category_id,
      ec.name AS category_name,
      COALESCE(SUM(ei.amount), 0) AS total
  FROM expense_category ec
  LEFT JOIN expense_item ei ON ec.id = ei.category_id AND ei.isdeleted = false
  LEFT JOIN expense e ON ei.expense_id = e.id AND e.isdeleted = false
      AND e.user_id = p_user_id
      AND date_trunc('day', e.date) >= date_trunc('day', p_start_date)
      AND date_trunc('day', e.date) <= date_trunc('day', p_end_date)
      AND (e.transaction_type = 'expense' OR e.transaction_type IS NULL)
  WHERE ec.isdeleted = false
    AND (ec.user_id IS NULL OR ec.user_id = p_user_id)  -- ✨ User-scoping: global + user's custom
  GROUP BY ec.id, ec.name
  ORDER BY total DESC;
END;
$$;
