
DECLARE
  budget_user_id UUID;
BEGIN
  -- Get the user_id for this budget to ensure we only count their expenses
  SELECT b.user_id INTO budget_user_id 
  FROM budget b 
  WHERE b.id = budget_id;

  RETURN QUERY
  SELECT
    ec.id AS category_id,
    ec.name AS category_name,
    COALESCE(SUM(ei.amount), 0) AS total_spent,
    b.amount AS budget_amount,
    CASE 
      WHEN b.amount > 0 THEN 
        ROUND((COALESCE(SUM(ei.amount), 0) / b.amount) * 100, 2)
      ELSE 0
    END AS percentage
  FROM budget_category bc
    JOIN expense_category ec ON bc.category_id = ec.id
    JOIN budget b ON bc.budget_id = b.id
    LEFT JOIN expense_item ei ON ec.id = ei.category_id
      AND (ei.isdeleted = false OR ei.isdeleted IS NULL)
    LEFT JOIN expense e ON ei.expense_id = e.id
      AND (e.isdeleted = false OR e.id IS NULL)
      AND e.user_id = budget_user_id  -- Add this filter!
  WHERE bc.budget_id = budget_id
    AND bc.isdeleted = false
    AND ec.isdeleted = false
  GROUP BY ec.id, ec.name, b.amount
  ORDER BY total_spent DESC;
END;
