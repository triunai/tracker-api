import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { Mistral } from 'https://esm.sh/@mistralai/mistralai@1.7.2';
import OpenAI from 'https://esm.sh/openai@4.25.0?target=deno';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', {
      headers: corsHeaders
    });
  }
  
  try {
    // Cache the request body to avoid "Body already consumed" error
    const requestBody = await req.json();
    
    // 🔍 DIAGNOSTIC: Log the complete request body structure
    console.log('📥 FULL REQUEST BODY:', JSON.stringify(requestBody, null, 2));
    console.log('📥 Request keys:', Object.keys(requestBody));
    console.log('📥 documentId type:', typeof requestBody.documentId, 'value:', requestBody.documentId);
    console.log('📥 fileName type:', typeof requestBody.fileName, 'value:', requestBody.fileName);
    console.log('📥 filePath type:', typeof requestBody.filePath, 'value:', requestBody.filePath);

    const { documentId, fileName } = requestBody;

    if (!documentId || !fileName) {
      throw new Error('Missing documentId or fileName');
    }

    // Initialize Supabase client
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    // Step 1: Update status to processing
    console.log('🔄 Updating status to processing...');
    await supabase.rpc('update_document_processing_status', {
      p_document_id: documentId,
      p_status: 'processing'
    });

    // Step 2: Get file from storage and convert to base64
    console.log('📁 Downloading file from storage...');
    const { data: fileData, error: downloadError } = await supabase.storage
      .from('document-uploads')
      .download(fileName);

    if (downloadError) {
      console.error('❌ Download error:', downloadError);
      throw new Error(`Failed to download file: ${downloadError.message}`);
    }

    if (!fileData) {
      throw new Error('No file data received');
    }

    console.log('✅ File downloaded successfully:', {
      size: fileData.size,
      type: fileData.type
    });

    // Step 3: Perform OCR using Mistral with base64
    console.log('🔍 Starting OCR process...');
    const ocrText = await performOCR(fileData);

    // Step 4: Update status to OCR completed
    console.log('📝 Updating status to OCR completed...');
    await supabase.rpc('update_document_processing_status', {
      p_document_id: documentId,
      p_status: 'ocr_completed',
      p_raw_markdown_output: ocrText
    });

    // Step 5: Get document to retrieve user_id for scoped categories
    console.log('📊 Fetching document to get user_id...');
    const { data: document, error: docError } = await supabase
      .from('documents')
      .select('user_id')
      .eq('id', documentId)
      .single();

    if (docError || !document) {
      throw new Error(`Failed to fetch document: ${docError?.message || 'Document not found'}`);
    }

    const userId = document.user_id;
    console.log(`✅ Retrieved user_id: ${userId}`);

    // Step 6: Get user's existing categories for AI context (global + user's custom)
    console.log('📊 Fetching categories and payment methods...');
    const { data: expenseCategories } = await supabase
      .from('expense_category')
      .select('id, name, description')
      .eq('isdeleted', false)
      .or(`user_id.is.null,user_id.eq.${userId}`);

    const { data: incomeCategories } = await supabase
      .from('income_category')
      .select('id, name, description')
      .eq('isdeleted', false)
      .or(`user_id.is.null,user_id.eq.${userId}`);

    const { data: paymentMethods } = await supabase
      .from('payment_methods')
      .select('id, method_name')
      .eq('isdeleted', false)
      .or(`user_id.is.null,user_id.eq.${userId}`);

    // Step 7: Use AI to parse financial data
    console.log('🧠 Parsing document with OpenRouter AI...');
    const parsedData = await parseWithOpenRouter(ocrText, {
      expenseCategories: expenseCategories || [],
      incomeCategories: incomeCategories || [],
      paymentMethods: paymentMethods || []
    });

    // Step 8: Update document with parsed data
    console.log('💾 Updating document with parsed data...');
    await supabase.rpc('update_document_processing_status', {
      p_document_id: documentId,
      p_status: 'parsed',
      p_document_type: parsedData.documentType,
      p_vendor_name: parsedData.vendorName,
      p_transaction_date: parsedData.transactionDate,
      p_total_amount: parsedData.totalAmount,
      p_transaction_type: parsedData.transactionType,
      p_suggested_category_id: parsedData.suggestedCategoryId,
      p_suggested_category_type: parsedData.suggestedCategoryType,
      p_ai_confidence_score: parsedData.confidenceScore,
      p_suggested_payment_method_id: parsedData.suggestedPaymentMethodId
    });

    console.log(`✅ Successfully processed document ${documentId}`);

    return new Response(
      JSON.stringify({
        success: true,
        documentId,
        parsedData
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      },
    );
  } catch (error) {
    console.error('💥 Error processing document:', error);
    
    // Note: Could not update document status to failed due to scope limitations

    return new Response(
      JSON.stringify({
        success: false,
        error: error.message,
        details: error.stack
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      },
    );
  }
});

// OCR Function using Mistral OCR API with proper upload flow
async function performOCR(fileData: Blob): Promise<string> {
  console.log("🔍 [OCR] Starting OCR process with Mistral AI (Upload → Signed URL)...")
  console.log("🔍 [OCR] File size:", fileData.size, "bytes")
  console.log("🔍 [OCR] File type:", fileData.type)

  const mistralApiKey = Deno.env.get("MISTRAL_API_KEY")
  if (!mistralApiKey) throw new Error("MISTRAL_API_KEY not set")

  const mistral = new Mistral({ apiKey: mistralApiKey })

  // Determine file type and create appropriate filename
  const mimeType = fileData.type || 'application/octet-stream'
  const isImage = mimeType.startsWith('image/')
  const ext = mimeType.split('/')[1] || 'bin'
  const fileName = `upload-${Date.now()}.${ext}`

  console.log('📄 File details:', {
    originalSize: fileData.size,
    mimeType,
    isImage,
    fileName,
    supportedImageTypes: ['image/jpeg', 'image/png', 'image/jpg'],
    isJPEG: mimeType === 'image/jpeg',
    isPNG: mimeType === 'image/png'
  })

  // 🔍 DIAGNOSTIC: Check if this is a supported image type
  if (isImage && !['image/jpeg', 'image/png', 'image/jpg'].includes(mimeType)) {
    console.warn('⚠️ Unsupported image type:', mimeType)
  }

  // Prepare document configuration based on file type
  let documentConfig
  let fileId = null
  let signedUrl = null

  if (isImage) {
    console.log('🖼️ Processing as IMAGE with base64 (direct approach)...')
    
    // For images, use base64 directly (no upload needed)
    const arrayBuffer = await fileData.arrayBuffer()
    const uint8Array = new Uint8Array(arrayBuffer)
    const base64String = btoa(String.fromCharCode(...uint8Array))
    const dataUri = `data:${mimeType};base64,${base64String}`
    
    documentConfig = {
      type: "image_url",
      imageUrl: dataUri
    }
    
    console.log('📄 Using base64 data URI for image:', {
      base64Length: base64String.length,
      dataUriPrefix: dataUri.substring(0, 100) + '...'
    })
  } else {
    console.log('📄 Processing as DOCUMENT with signed URL...')
    
    // For PDFs, upload file and use signed URL
    console.log('📤 Uploading file to Mistral...')
    const fileObj = new File([await fileData.arrayBuffer()], fileName, { type: mimeType })
    
    const uploadedFile = await mistral.files.upload({
      file: fileObj,
      purpose: "ocr"
    })

    fileId = uploadedFile.id
    console.log('✅ File uploaded to Mistral:', fileId)

    // Get signed URL
    console.log('🔗 Getting signed URL...')
    const signedUrlResponse = await mistral.files.getSignedUrl({
      fileId: fileId
    })

    signedUrl = signedUrlResponse.url
    console.log('✅ Signed URL obtained successfully')
    
    documentConfig = {
      type: "document_url",
      documentUrl: signedUrl
    }
  }

  try {

    console.log('🤖 Mistral OCR Request Details:', {
      model: "mistral-ocr-latest",
      documentConfigType: documentConfig.type,
      fileId: fileId,
      isImageType: isImage,
      mimeType: mimeType,
      ...(isImage ? {
        base64Length: documentConfig.imageUrl?.length || 0,
        dataUriPrefix: documentConfig.imageUrl?.substring(0, 50) + '...'
      } : {
        signedUrlPreview: 'documentUrl' in documentConfig ? documentConfig.documentUrl.substring(0, 100) + '...' : 'N/A'
      })
    })

    // Step 4: Process OCR
    console.log('🤖 Processing OCR...')
    
    let ocrResponse
    
    if (isImage) {
      // For images, try OCR endpoint first, then fallback to Vision model
      try {
        console.log('🔍 Trying OCR endpoint for image...')
        ocrResponse = await mistral.ocr.process({
          model: "mistral-ocr-latest",
          document: documentConfig,
          includeImageBase64: true  // As per Mistral docs for images
        })
        console.log('✅ OCR API call successful')
      } catch (ocrError) {
        console.log('⚠️ OCR endpoint failed for image, trying Vision model fallback...')
        console.log('OCR Error details:', ocrError.message)
        
        // Fallback: Use Mistral Vision model for image text extraction
        try {
          const visionResponse = await mistral.chat.complete({
            model: "pixtral-12b-2409",
            messages: [
              {
                role: "user",
                content: [
                  {
                    type: "text",
                    text: "Extract all text from this image. Return the text exactly as it appears, preserving formatting and structure. Focus on receipts, invoices, or financial documents."
                  },
                  {
                    type: "image_url",
                    imageUrl: documentConfig.imageUrl
                  }
                ]
              }
            ],
            temperature: 0.1,
            maxTokens: 2000
          })
          
          const extractedText = visionResponse.choices[0]?.message?.content || ""
          console.log('✅ Vision model extraction successful')
          console.log('📄 Extracted text length:', extractedText.length)
          
          // Convert to OCR response format
          ocrResponse = {
            pages: [{
              markdown: extractedText
            }],
            model: "pixtral-12b-2409"
          }
        } catch (visionError) {
          console.error('❌ Vision model also failed:', visionError)
          throw new Error(`Both OCR and Vision models failed. OCR: ${ocrError.message}, Vision: ${visionError.message}`)
        }
      }
    } else {
      // For PDFs, use OCR endpoint
      try {
        ocrResponse = await mistral.ocr.process({
          model: "mistral-ocr-latest",
          document: documentConfig,
          includeImageBase64: false
        })
        console.log('✅ OCR API call successful')
      } catch (ocrError) {
        console.error('❌ OCR API Error:', {
          error: ocrError,
          message: ocrError.message,
          status: ocrError.status || 'unknown',
          isImageType: isImage,
          mimeType: mimeType,
          fileSize: fileData.size
        })
        throw new Error(`OCR processing failed: ${ocrError.message}`)
      }
    }

    console.log('✅ OCR processing successful:', {
      pagesProcessed: ocrResponse.pages?.length || 0,
      model: ocrResponse.model
    })

    // Extract markdown from all pages
    const pages = ocrResponse.pages ?? []
    const markdown = pages.map((p) => p.markdown ?? "").join("\n\n").trim()

    if (!markdown) throw new Error("No text extracted from document")

    console.log(`📝 [OCR] Extracted ${markdown.length} chars`)
    
    // 🔍 DIAGNOSTIC: Log the actual OCR text to debug amount extraction
    console.log('📄 OCR TEXT PREVIEW (first 500 chars):')
    console.log(markdown.substring(0, 500))
    console.log('📄 OCR TEXT PREVIEW (last 500 chars):')
    console.log(markdown.substring(Math.max(0, markdown.length - 500)))
    
    return markdown

  } finally {
    // Step 5: Clean up - delete the uploaded file (only if we uploaded one)
    if (fileId) {
      try {
        console.log('🗑️ Cleaning up uploaded file...')
        await mistral.files.delete({ fileId: fileId })
        console.log('✅ File deleted from Mistral')
      } catch (deleteError) {
        console.warn('⚠️ Failed to delete file from Mistral:', deleteError)
      }
    }
  }
}

// Type definitions for context
interface Category {
  id: number
  name: string
  description: string
}

interface PaymentMethod {
  id: number
  method_name: string
}

interface ParseContext {
  expenseCategories: Category[]
  incomeCategories: Category[]
  paymentMethods: PaymentMethod[]
}

// AI Parsing Function using OpenRouter with GPT-4o-mini
async function parseWithOpenRouter(ocrText: string, context: ParseContext) {
  console.log('🤖 Parsing document with OpenRouter AI...');
  
  try {
    // Get OpenRouter API key from environment
    const openrouterApiKey = Deno.env.get('OPENROUTER_API_KEY');
    if (!openrouterApiKey) {
      throw new Error('OPENROUTER_API_KEY not found in environment variables');
    }

    // Initialize OpenAI client with OpenRouter configuration
    const openai = new OpenAI({
      baseURL: "https://openrouter.ai/api/v1",
      apiKey: openrouterApiKey,
      defaultHeaders: {
        "HTTP-Referer": "https://tracker-zenith.vercel.app",
        "X-Title": "FinanceTracker-DocumentProcessor"
      }
    });

    // Create JSON schema for structured output (simplified for OpenRouter compatibility)
    const schema = {
      type: "object",
      additionalProperties: false,
      properties: {
        vendor: { 
          type: "string", 
          description: "The name of the store or vendor" 
        },
        total: { 
          type: "number", 
          description: "The final grand total amount as a number" 
        },
        invoice_id: { 
          type: "string", 
          description: "Invoice or receipt number" 
        },
        purchase_date: { 
          type: "string", 
          description: "Purchase date in YYYY-MM-DD format" 
        },
        currency: { 
          type: "string", 
          description: "Currency code like MYR, USD, EUR" 
        },
        transaction_type: { 
          type: "string", 
          enum: ["expense", "income"], 
          description: "Transaction type" 
        },
        suggested_category_id: { 
          type: "integer", 
          description: "Best matching category ID" 
        },
        suggested_category_type: { 
          type: "string", 
          enum: ["expense", "income"], 
          description: "Category type" 
        },
        confidence_score: { 
          type: "number", 
          minimum: 0, 
          maximum: 1, 
          description: "Confidence level 0.0-1.0" 
        },
        items: {
          type: "array",
          items: {
            type: "object",
            additionalProperties: false,
            properties: {
              item: { 
                type: "string", 
                description: "Item name" 
              },
              quantity: { 
                type: "number", 
                description: "Quantity" 
              },
              price: { 
                type: "number", 
                description: "Total price for line item" 
              }
            },
            required: ["item", "quantity", "price"]
          }
        }
      },
      required: ["vendor", "total", "transaction_type", "suggested_category_id", "suggested_category_type", "confidence_score", "items"]
    };

    // Create enhanced prompt for AI parsing
    const prompt = `Extract financial transaction data from this receipt/invoice text. Return valid JSON only.

**IMPORTANT FORMATTING RULES:**
- Vendor name: Create a descriptive transaction title that includes the activity + business name in proper title case
  Examples: 
  • "LEMON GRASS" → "Dining at Lemon Grass"
  • "McDONALD'S" → "Eating at McDonald's" 
  • "SHELL" → "Fuel at Shell"
  • "STARBUCKS" → "Coffee at Starbucks"
  • "GROCERY STORE" → "Shopping at Grocery Store"
  • "CINEMA" → "Movies at Cinema"
  • "HOSPITAL" → "Medical at Hospital"
- Total amount: Extract only the final grand total as a number (e.g., "Total: RM 84.30" returns 84.30)
- Date format: Always use YYYY-MM-DD format
- Currency: Default to MYR for Malaysian businesses

**Available Expense Categories:**
${context.expenseCategories.map((cat) => `${cat.id}: ${cat.name} - ${cat.description}`).join('\n')}

**Available Income Categories:**
${context.incomeCategories.map((cat) => `${cat.id}: ${cat.name} - ${cat.description}`).join('\n')}

**Available Payment Methods:**
${context.paymentMethods.map((pm) => `${pm.id}: ${pm.method_name}`).join('\n')}

**Raw Document Text:**
---
${ocrText}
---

Extract all transaction data carefully. Create meaningful transaction descriptions and match to the most appropriate available categories and payment methods.`;

    // Call OpenRouter with structured output
    console.log('🤖 Making OpenRouter API call with gpt-4o-mini...');
    
    const completion = await openai.chat.completions.create({
      model: "openai/gpt-4o-mini",
      messages: [
        {
          role: "system",
          content: "You are a precise financial document parser. Extract data exactly as specified in the schema. Return only valid JSON."
        },
        {
          role: "user",
          content: prompt
        }
      ],
      response_format: {
        type: "json_schema",
        json_schema: {
          name: "financial_document",
          strict: true,
          schema: schema
        }
      },
      temperature: 0.1,
      max_tokens: 2000
    });

    const aiResponse = completion.choices[0]?.message?.content;
    if (!aiResponse) {
      throw new Error('No response from OpenRouter AI');
    }

    console.log('🤖 OpenRouter AI response received');

    // Parse the JSON response
    let parsedData;
    try {
      parsedData = JSON.parse(aiResponse);
      
      console.log('📊 PARSED DATA FROM OPENROUTER:', {
        vendor: parsedData.vendor,
        total: parsedData.total,
        totalType: typeof parsedData.total,
        currency: parsedData.currency,
        confidence: parsedData.confidence_score
      });
      
    } catch (parseError) {
      console.error('Failed to parse OpenRouter AI response as JSON:', parseError);
      throw new Error('Invalid JSON response from AI');
    }

    // Return in the expected format
    return {
      documentType: 'receipt',
      vendorName: parsedData.vendor || 'Unknown Vendor',
      transactionDate: parsedData.purchase_date || new Date().toISOString().split('T')[0],
      totalAmount: parseFloat(parsedData.total) || 0,
      currency: parsedData.currency || 'MYR',
      transactionType: parsedData.transaction_type === 'income' ? 'income' : 'expense',
      suggestedCategoryId: parseInt(parsedData.suggested_category_id) || context.expenseCategories[0]?.id || 1,
      suggestedCategoryType: parsedData.suggested_category_type === 'income' ? 'income' : 'expense',
      confidenceScore: parseFloat(parsedData.confidence_score) || 0.8,
      suggestedPaymentMethodId: parsedData.suggested_payment_method_id ? parseInt(parsedData.suggested_payment_method_id) : null
    };

  } catch (error) {
    console.error('❌ OpenRouter AI parsing error:', error);
    
    // Fallback to the existing parseWithAI function as backup
    console.log('🔄 Falling back to Mistral AI parsing...');
    return await parseWithAI(ocrText, context);
  }
}

// AI Parsing Function using Mistral Chat API (kept as fallback)
async function parseWithAI(ocrText: string, context: ParseContext) {
  console.log('🧠 Parsing document with Mistral AI...')
  
  try {
    // Get Mistral API key from environment
    const mistralApiKey = Deno.env.get('MISTRAL_API_KEY')
    if (!mistralApiKey) {
      throw new Error('MISTRAL_API_KEY not found in environment variables')
    }

    // Initialize Mistral client
    const client = new Mistral({
      apiKey: mistralApiKey
    })

    // Create enhanced prompt for AI parsing
    const prompt = `You are an expert data extraction API. Your job is to parse the raw text from a document and return a clean, valid JSON object.

**Instructions:**
1. **Extract the following fields** from the text based on the schema provided.
2. **Be precise.** Do not add any fields that are not in the schema.
3. **Handle missing data.** If a field is optional and not present in the text, omit it from the JSON. For required fields, use the specified defaults.
4. **Format correctly.** Dates must be "YYYY-MM-DD". Times must be "HH:MM:SS". Numerical values must be float or int, not strings.
5. **Return only JSON.** Your entire output must be a single, valid JSON object, with no surrounding text, comments, or markdown.

**Schema:**
- "vendor" (string, required): The name of the store or vendor.
- "total" (float, required): The final grand total amount. Look for keywords like "Total", "Grand Total", "Amount Due", "Balance", or the largest monetary value. Extract ONLY the number (e.g., if you see "Total: $21.50" or "RM 21.50", return 21.5).
- "invoice_id" (string, optional): CRITICAL document identifier. Look for labels like "Invoice #", "Receipt No.", "Doc #", "INV-", or common abbreviations like "NO.". It is often near the top of the document.
- "order_id" (string, optional): The order number, if different from the invoice ID. Look for "Order #", "Ref:", etc.
- "purchase_date" (string, optional, format: YYYY-MM-DD): The date of purchase.
- "purchase_time" (string, optional, format: HH:MM:SS): The time of purchase.
- "currency" (string, optional, default: MYR): The currency code. Look for "RM", "MYR" (Malaysian Ringgit), "$", "USD" (US Dollar), "€", "EUR" (Euro), etc. If unclear, default to MYR for Malaysian businesses.
- "tax_amount" (float, optional): The total tax amount.
- "subtotal" (float, optional): The subtotal before tax.
- "payment_method" (string, optional): How the payment was made.
- "transaction_type" (string, required, default: "expense"): Either "expense" or "income".
- "suggested_category_id" (int, required): Best matching category ID from available categories.
- "suggested_category_type" (string, required): Either "expense" or "income".
- "confidence_score" (float, required): Confidence level between 0.0-1.0.
- "items" (array of objects, required): List of purchased items. Each item must contain:
    - "item" (string, required): Item name. Use "name" field from source if available.
    - "quantity" (float, required, default: 1.0): The quantity.
    - "price" (float, required): The total price for the line item.
    - "unit_price" (float, optional): The price for a single unit.
    - "description" (string, optional): Extra item details.

**Available Expense Categories:**
${context.expenseCategories.map((cat) => `${cat.id}: ${cat.name} - ${cat.description}`).join('\n')}

**Available Income Categories:**
${context.incomeCategories.map((cat) => `${cat.id}: ${cat.name} - ${cat.description}`).join('\n')}

**Available Payment Methods:**
${context.paymentMethods.map((pm) => `${pm.id}: ${pm.method_name}`).join('\n')}

**Raw Document Text to Parse:**
---
${ocrText}
---`

    // Call Mistral Chat API with retry logic
    let chatResponse
    const maxRetries = 3
    const models = ["mistral-large-latest", "mistral-medium-latest", "open-mistral-7b"]
    
    for (let modelIndex = 0; modelIndex < models.length; modelIndex++) {
      const currentModel = models[modelIndex]
      
      for (let attempt = 1; attempt <= maxRetries; attempt++) {
        try {
          console.log(`🤖 Attempting AI parsing with ${currentModel} (attempt ${attempt}/${maxRetries})...`)
          
          chatResponse = await client.chat.complete({
            model: currentModel,
            messages: [
              {
                role: "user",
                content: prompt
              }
            ],
            temperature: 0.1,
            maxTokens: 1000
          })
          
          console.log(`✅ AI parsing successful with ${currentModel}`)
          break // Success, exit retry loop
          
        } catch (apiError) {
          console.log(`⚠️ ${currentModel} attempt ${attempt} failed:`, apiError.message)
          
          if (apiError.statusCode === 429) {
            // Rate limited - try next model or wait
            if (attempt < maxRetries) {
              const waitTime = Math.pow(2, attempt) * 1000 // Exponential backoff
              console.log(`⏳ Rate limited, waiting ${waitTime}ms before retry...`)
              await new Promise(resolve => setTimeout(resolve, waitTime))
            } else if (modelIndex < models.length - 1) {
              console.log(`🔄 ${currentModel} exhausted, trying next model...`)
              break // Try next model
            }
          } else {
            // Non-rate-limit error - try next model immediately
            console.log(`❌ ${currentModel} failed with non-rate-limit error, trying next model...`)
            break
          }
          
          // If this was the last attempt with the last model, throw error
          if (attempt === maxRetries && modelIndex === models.length - 1) {
            throw apiError
          }
        }
      }
      
      // If we got a successful response, break out of model loop
      if (chatResponse) break
    }

    const aiResponse = chatResponse.choices[0]?.message?.content
    if (!aiResponse) {
      throw new Error('No response from Mistral AI')
    }

    console.log('🤖 Mistral AI response:', aiResponse)

    // Parse the JSON response
    let parsedData
    try {
      // Extract JSON from response (in case there's extra text)
      const jsonMatch = aiResponse.match(/\{[\s\S]*\}/)
      const jsonString = jsonMatch ? jsonMatch[0] : aiResponse
      parsedData = JSON.parse(jsonString)
      
      // 🔍 DIAGNOSTIC: Log the parsed data to debug amount extraction
      console.log('📊 PARSED DATA FROM AI:', {
        vendor: parsedData.vendor,
        total: parsedData.total,
        totalType: typeof parsedData.total,
        rawTotal: parsedData.total,
        parsedFloat: parseFloat(parsedData.total),
        currency: parsedData.currency,
        allKeys: Object.keys(parsedData)
      })
      
    } catch (parseError) {
      console.error('Failed to parse AI response as JSON:', parseError)
      throw new Error('Invalid JSON response from AI')
    }

    // Validate and return the parsed data with new schema
    return {
      documentType: 'receipt',
      vendorName: parsedData.vendor || 'Unknown Vendor',
      transactionDate: parsedData.purchase_date || new Date().toISOString().split('T')[0],
      totalAmount: parseFloat(parsedData.total) || 0,
      currency: parsedData.currency || 'MYR',
      transactionType: parsedData.transaction_type === 'income' ? 'income' : 'expense',
      suggestedCategoryId: parseInt(parsedData.suggested_category_id) || context.expenseCategories[0]?.id || 1,
      suggestedCategoryType: parsedData.suggested_category_type === 'income' ? 'income' : 'expense',
      confidenceScore: parseFloat(parsedData.confidence_score) || 0.5,
      suggestedPaymentMethodId: parsedData.suggested_payment_method_id ? parseInt(parsedData.suggested_payment_method_id) : null
    }

  } catch (error) {
    console.error('❌ Mistral AI parsing error:', error)
    
    // Fallback to rule-based parsing
    console.log('🔄 Falling back to rule-based parsing...')
    console.log('📄 Raw OCR text for fallback parsing:', ocrText.substring(0, 1000))
    
    // Clean up markdown formatting from OCR text
    const cleanText = ocrText
      .replace(/```[\s\S]*?```/g, '') // Remove code blocks
      .replace(/#{1,6}\s*/g, '') // Remove markdown headers
      .replace(/\*\*(.*?)\*\*/g, '$1') // Remove bold formatting
      .replace(/\*(.*?)\*/g, '$1') // Remove italic formatting
      .replace(/\[(.*?)\]\(.*?\)/g, '$1') // Remove markdown links
      .replace(/^\s*[-*+]\s+/gm, '') // Remove bullet points
      .replace(/^\s*\d+\.\s+/gm, '') // Remove numbered lists
      .trim()
    
    console.log('🧹 Cleaned text for parsing:', cleanText.substring(0, 500))
    
    // Extract amount with multiple patterns
    console.log('🔍 FALLBACK: Trying to extract amount from cleaned text...')
    
    // Try multiple amount extraction patterns
    const amountPatterns = [
      /(?:Total|Grand\s*Total|Amount\s*Due|Balance|TOTAL|AMOUNT)\s*:?\s*(?:RM|MYR|\$|USD)?\s*(\d+(?:\.\d{2})?)/i,
      /(?:RM|MYR|\$|USD)\s*(\d+(?:\.\d{2})?)/g,
      /(\d+\.\d{2})\s*(?:RM|MYR|\$|USD)?/g,
      /(?:^|\s)(\d{1,4}\.\d{2})(?:\s|$)/g // Any amount with 2 decimals
    ]
    
    let totalAmount = 0
    let foundPattern: string | null = null
    
    for (const pattern of amountPatterns) {
      const matches = cleanText.match(pattern)
      if (matches) {
        console.log(`💰 Found amount with pattern ${pattern}:`, matches)
        // Extract the numeric part
        const numericMatch = matches[0].match(/(\d+(?:\.\d{2})?)/)
        if (numericMatch) {
          totalAmount = parseFloat(numericMatch[1])
          foundPattern = pattern.toString()
          break
        }
      }
    }
    
    console.log('💰 FALLBACK extracted amount:', { totalAmount, foundPattern })

    // Extract vendor name - look for business-like names
    const lines = cleanText.trim().split('\n').filter(line => line.trim().length > 0)
    let vendorName = 'Unknown Vendor'
    
    // Look for vendor name in first few lines, avoiding common receipt headers
    for (const line of lines.slice(0, 5)) {
      const trimmedLine = line.trim()
      // Skip common receipt headers and formatting artifacts
      if (trimmedLine.length > 3 && 
          !trimmedLine.match(/^(receipt|invoice|bill|date|time|no\.|#|\d+\/\d+\/\d+)/i) &&
          !trimmedLine.match(/^(transaction|details|summary)/i)) {
        vendorName = trimmedLine
        break
      }
    }
    
    console.log('🏪 FALLBACK extracted vendor:', vendorName)

    // Extract date with multiple patterns
    const datePatterns = [
      /(?:Date|DATE)\s*:?\s*(\d{4}-\d{2}-\d{2})/i,
      /(?:Date|DATE)\s*:?\s*(\d{1,2}\/\d{1,2}\/\d{4})/i,
      /(?:Date|DATE)\s*:?\s*(\d{1,2}-\d{1,2}-\d{4})/i,
      /(\d{4}-\d{2}-\d{2})/,
      /(\d{1,2}\/\d{1,2}\/\d{4})/,
      /(\d{1,2}-\d{1,2}-\d{4})/
    ]
    
    let transactionDate = new Date().toISOString().split('T')[0] // Default to today
    
    for (const pattern of datePatterns) {
      const dateMatch = cleanText.match(pattern)
      if (dateMatch) {
        let dateStr = dateMatch[1]
        // Convert to YYYY-MM-DD format
        if (dateStr.includes('/')) {
          const parts = dateStr.split('/')
          if (parts.length === 3) {
            // Assume MM/DD/YYYY or DD/MM/YYYY format
            const year = parts[2]
            const month = parts[0].padStart(2, '0')
            const day = parts[1].padStart(2, '0')
            dateStr = `${year}-${month}-${day}`
          }
                 } else if (dateStr.includes('-') && dateStr.length === 10) {
           // Already in YYYY-MM-DD format
           // dateStr is already in correct format
         }
        transactionDate = dateStr
        break
      }
    }
    
    console.log('📅 FALLBACK extracted date:', transactionDate)

    // Simple category matching based on vendor name
    const vendorLower = vendorName.toLowerCase()
    let bestCategory = context.expenseCategories[0] // Default to first category
    
    // Smart category matching
    for (const cat of context.expenseCategories) {
      const catName = cat.name.toLowerCase()
      const catDesc = cat.description.toLowerCase()
      
      if ((vendorLower.includes('food') || vendorLower.includes('restaurant') || 
           vendorLower.includes('cafe') || vendorLower.includes('starbucks')) &&
          (catName.includes('food') || catName.includes('dining') || catName.includes('meal'))) {
        bestCategory = cat
        break
      } else if ((vendorLower.includes('gas') || vendorLower.includes('petrol') || 
                  vendorLower.includes('fuel')) &&
                 (catName.includes('transport') || catName.includes('fuel') || catName.includes('gas'))) {
        bestCategory = cat
        break
      } else if ((vendorLower.includes('grocery') || vendorLower.includes('market') || 
                  vendorLower.includes('supermarket')) &&
                 (catName.includes('grocery') || catName.includes('food'))) {
        bestCategory = cat
        break
      }
    }
    
    console.log('🏷️ FALLBACK selected category:', { id: bestCategory.id, name: bestCategory.name })

    return {
      documentType: 'receipt',
      vendorName,
      transactionDate,
      totalAmount,
      currency: 'MYR', // Default to MYR in fallback
      transactionType: 'expense',
      suggestedCategoryId: bestCategory.id,
      suggestedCategoryType: 'expense',
      confidenceScore: totalAmount > 0 ? 0.7 : 0.4, // Higher confidence if we found an amount
      suggestedPaymentMethodId: null as number | null
    }
  }
}
