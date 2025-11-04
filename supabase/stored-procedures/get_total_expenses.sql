CREATE OR REPLACE FUNCTION public.get_total_expenses(
  p_user_id uuid,
  p_start_date date,
  p_end_date date
)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
  total_amount NUMERIC;
BEGIN
  SELECT COALESCE(SUM(ei.amount), 0)
  INTO total_amount
  FROM expense e
  JOIN expense_item ei ON e.id = ei.expense_id
  WHERE e.user_id = p_user_id
    AND date_trunc('day', e.date) >= date_trunc('day', p_start_date)
    AND date_trunc('day', e.date) <= date_trunc('day', p_end_date)
    AND e.isdeleted = false
    AND ei.isdeleted = false
    AND (e.transaction_type = 'expense' OR e.transaction_type IS NULL);

  RETURN total_amount;
END;
$$;
