CREATE OR REPLACE FUNCTION public.calculate_budget_spending_by_date(
  budget_id bigint,
  p_start_date date,
  p_end_date date
)
RETURNS numeric
LANGUAGE plpgsql
AS $$
DECLARE
  total_spent NUMERIC;
  budget_user_id UUID;
BEGIN
  -- Get the user_id for this budget to ensure we only count their expenses
  SELECT b.user_id INTO budget_user_id 
  FROM budget b 
  WHERE b.id = calculate_budget_spending_by_date.budget_id;

  SELECT COALESCE(SUM(ei.amount), 0)
  INTO total_spent
  FROM budget b
    JOIN budget_category bc ON b.id = bc.budget_id
    LEFT JOIN expense_item ei ON ei.category_id = bc.category_id
    LEFT JOIN expense e ON e.id = ei.expense_id
  WHERE b.id = calculate_budget_spending_by_date.budget_id
    AND b.isdeleted = false
    AND bc.isdeleted = false
    AND (ei.isdeleted = false OR ei.isdeleted IS NULL)
    AND (e.isdeleted = false OR e.id IS NULL)
    AND (e.date BETWEEN p_start_date AND p_end_date)
    AND (e.user_id = budget_user_id OR e.id IS NULL);  -- Filter by budget owner
  
  RETURN total_spent;
END;
$$;
