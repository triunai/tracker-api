
DECLARE
  v_document documents%ROWTYPE;
  v_expense_id bigint;
  v_category_id bigint;
  v_income_category_id bigint;
  v_final_amount numeric(10,2);
  v_final_description text;
  v_final_payment_method_id integer;
  v_transaction_type text;
BEGIN
  -- Get document details and ensure it belongs to the current user
  SELECT * INTO v_document
  FROM public.documents 
  WHERE id = p_document_id 
    AND user_id = auth.uid()
    AND isdeleted = false;
    
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false, 
      'error', 'Document not found or access denied'
    );
  END IF;
  
  -- Check if transaction already created
  IF v_document.created_expense_id IS NOT NULL THEN
    RETURN jsonb_build_object(
      'success', false, 
      'error', 'Transaction already created for this document'
    );
  END IF;
  
  -- Determine final values (user overrides take precedence)
  v_final_amount := COALESCE(p_amount, v_document.total_amount);
  v_final_description := COALESCE(p_description, v_document.vendor_name, 'Document Transaction');
  v_final_payment_method_id := COALESCE(p_payment_method_id, v_document.suggested_payment_method_id);
  v_transaction_type := COALESCE(p_category_type, v_document.transaction_type, 'expense');
  
  -- Validate required fields
  IF v_final_amount IS NULL OR v_final_amount <= 0 THEN
    RETURN jsonb_build_object(
      'success', false, 
      'error', 'Valid amount is required'
    );
  END IF;
  
  -- Determine category IDs based on transaction type
  IF v_transaction_type = 'income' THEN
    v_category_id := NULL;
    v_income_category_id := COALESCE(p_category_id, v_document.suggested_category_id);
    
    -- Validate income category exists
    IF v_income_category_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM income_category WHERE id = v_income_category_id AND isdeleted = false
    ) THEN
      RETURN jsonb_build_object(
        'success', false, 
        'error', 'Valid income category is required'
      );
    END IF;
  ELSE
    v_category_id := COALESCE(p_category_id, v_document.suggested_category_id);
    v_income_category_id := NULL;
    
    -- Validate expense category exists
    IF v_category_id IS NULL OR NOT EXISTS (
      SELECT 1 FROM expense_category WHERE id = v_category_id AND isdeleted = false
    ) THEN
      RETURN jsonb_build_object(
        'success', false, 
        'error', 'Valid expense category is required'
      );
    END IF;
  END IF;
  
  -- Create the expense record
  INSERT INTO public.expense (
    user_id,
    date,
    description,
    payment_method_id,
    transaction_type,
    created_by
  ) VALUES (
    v_document.user_id,
    COALESCE(v_document.transaction_date, CURRENT_DATE),
    v_final_description,
    v_final_payment_method_id,
    v_transaction_type,
    v_document.user_id
  )
  RETURNING id INTO v_expense_id;
  
  -- Create the expense item
  INSERT INTO public.expense_item (
    expense_id,
    category_id,
    income_category_id,
    amount,
    description,
    created_by
  ) VALUES (
    v_expense_id,
    v_category_id,
    v_income_category_id,
    v_final_amount,
    v_final_description,
    v_document.user_id
  );
  
  -- Update document with created transaction reference and status
  UPDATE public.documents 
  SET 
    created_expense_id = v_expense_id,
    status = 'transaction_created',
    updated_at = now(),
    updated_by = v_document.user_id
  WHERE id = p_document_id;
  
  -- Return success with expense ID
  RETURN jsonb_build_object(
    'success', true, 
    'expense_id', v_expense_id,
    'document_id', p_document_id
  );
  
EXCEPTION WHEN OTHERS THEN
  -- Return error details
  RETURN jsonb_build_object(
    'success', false, 
    'error', 'Failed to create transaction: ' || SQLERRM
  );
END;
