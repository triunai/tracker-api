# Document Processing Function

> **🚀 AI-Powered Financial Document Processing**  
> Part of the **Tracker Zenith** Finance Management System

## Overview

This Supabase Edge Function provides AI-powered document processing capabilities for financial documents (receipts, invoices, bank statements). It uses Mistral AI for OCR (Optical Character Recognition) and intelligent data extraction to automatically convert uploaded documents into structured transaction data.

The function is a critical component of the **Tracker Zenith** personal finance application, enabling users to digitize paper receipts and automate expense tracking through cutting-edge AI technology.

## 🎯 Key Features

- **🔍 OCR Processing**: Extracts text from images (PNG, JPG) and PDFs
- **🧠 AI-Powered Parsing**: Uses Mistral AI to understand and extract financial data
- **📁 Multi-format Support**: Handles both image-based and PDF documents
- **🏷️ Intelligent Categorization**: Suggests appropriate expense/income categories
- **⚡ Real-time Status Updates**: Tracks processing stages with detailed status reporting
- **🔄 Fallback Mechanisms**: Multiple AI models and rule-based parsing as backup
- **🧹 File Cleanup**: Automatic cleanup of temporary files from Mistral servers
- **💰 Cost Optimization**: Smart model selection to minimize processing costs

## 🏗️ Architecture Overview

```mermaid
graph TB
    subgraph "Frontend Layer"
        A[DocumentUploader Component]
        B[Real-time Status Updates]
        C[Transaction Creation UI]
    end
    
    subgraph "Supabase Infrastructure"
        D[Authentication]
        E[File Storage]
        F[PostgreSQL Database]
        G[Edge Functions Runtime]
    end
    
    subgraph "Document Processing Pipeline"
        H[File Upload Handler]
        I{File Type Detection}
        J[Image Base64 Encoder]
        K[PDF Upload to Mistral]
        L[OCR Processing]
        M[AI Text Parsing]
        N[Category Matching]
        O[Database Updates]
    end
    
    subgraph "External Services"
        P[Mistral AI OCR API]
        Q[Mistral AI Chat API]
        R[Vision Model Fallback]
    end
    
    A --> H
    H --> E
    H --> I
    I -->|Image| J
    I -->|PDF| K
    J --> L
    K --> L
    L --> P
    L --> Q
    L --> R
    M --> N
    N --> O
    O --> F
    O --> B
    B --> C
    
    style A fill:#e1f5fe
    style L fill:#fff3e0
    style P fill:#f3e5f5
    style Q fill:#f3e5f5
    style F fill:#e8f5e8
```

## 📂 Project Structure

```
tracker-zenith/                              # Root project directory
├── 📁 supabase/
│   ├── 📁 functions/
│   │   └── 📁 process-document/
│   │       ├── 📄 index.ts                  # Main processing function (698 lines)
│   │       └── 📄 README.md                 # This comprehensive documentation
│   └── 📄 config.toml                       # Supabase configuration
├── 📁 src/                                  # Frontend React application
│   ├── 📁 components/
│   │   ├── 📁 Dashboard/
│   │   │   └── 📄 DocumentUploader.tsx      # File upload & processing UI (479 lines)
│   │   ├── 📁 Transactions/                 # Transaction management components
│   │   ├── 📁 Budgets/                      # Budget tracking components
│   │   └── 📁 Charts/                       # Data visualization components
│   ├── 📁 interfaces/
│   │   ├── 📄 document-interface.ts         # Document processing types
│   │   └── 📄 types/                        # Additional TypeScript definitions
│   ├── 📁 lib/
│   │   ├── 📁 api/                          # API client utilities
│   │   ├── 📁 auth/                         # Authentication logic
│   │   └── 📁 supabase/                     # Supabase client configuration
│   └── 📁 pages/                            # Application routes & pages
├── 📁 .cursor/rules/
│   └── 📄 remote-procedure-calls.mdc        # Database schema & RPC functions
├── 📄 package.json                          # Frontend dependencies
├── 📄 vite.config.ts                        # Build configuration
└── 📄 README.md                             # Project main documentation
```

## ⚙️ Technical Dependencies

### Runtime Environment
- **Deno Runtime**: v1.x or higher (Edge Functions environment)
- **Supabase Edge Functions**: Deno-based serverless computing
- **TypeScript**: v5.x for compile-time type safety

### External APIs & Services
- **Mistral AI OCR**: Professional document text extraction
- **Mistral AI Chat**: Large language model for intelligent parsing
- **Supabase Database**: PostgreSQL with custom stored procedures
- **Supabase Storage**: File storage with CDN capabilities

### Frontend Integration
- **React**: v18.x with hooks for state management
- **TanStack Query**: Data fetching and caching
- **React Dropzone**: File upload interface
- **Shadcn/ui**: Modern UI component library

### Required Environment Variables
```bash
# 🔑 Mistral AI Configuration
MISTRAL_API_KEY=sk-your-mistral-api-key

# 🏗️ Supabase Configuration  
SUPABASE_URL=https://your-project-id.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
SUPABASE_ANON_KEY=your-anon-key-here
```

## 🔗 API Reference

### Endpoint Information
```
POST https://your-project.supabase.co/functions/v1/process-document
```

### Authentication Headers
```http
Authorization: Bearer <user_jwt_token>
Content-Type: application/json
apikey: <supabase_anon_key>
```

### Request Schema
```typescript
interface ProcessDocumentRequest {
  documentId: number;      // Database ID of uploaded document
  fileName: string;        // Storage path: "user-id/uuid.extension"
  filePath?: string;       // Legacy support (optional)
}
```

### Response Schema
```typescript
interface ProcessDocumentResponse {
  success: boolean;
  documentId: number;
  parsedData?: {
    documentType: 'receipt' | 'invoice' | 'statement';
    vendorName: string;
    transactionDate: string;     // ISO date format (YYYY-MM-DD)
    totalAmount: number;         // Parsed monetary amount
    currency: string;            // ISO currency code (MYR, USD, EUR)
    transactionType: 'expense' | 'income';
    suggestedCategoryId: number;
    suggestedCategoryType: 'expense' | 'income';
    confidenceScore: number;     // AI confidence (0.0 - 1.0)
    suggestedPaymentMethodId?: number;
  };
  error?: string;
  details?: string;            // Stack trace for debugging
}
```

### 📋 Complete Example Usage

**Frontend Integration:**
```typescript
// React component usage example
import { useState } from 'react';
import { supabase } from '@/lib/supabase/supabase';

const DocumentProcessor = () => {
  const [processing, setProcessing] = useState(false);
  const [result, setResult] = useState<any>(null);

  const processDocument = async (documentId: number, fileName: string) => {
    setProcessing(true);
    
    try {
      const { data, error } = await supabase.functions.invoke('process-document', {
        body: {
          documentId,
          fileName
        }
      });

      if (error) throw error;
      
      if (data.success) {
        setResult(data.parsedData);
        console.log('✅ Document processed:', data.parsedData);
      } else {
        throw new Error(data.error);
      }
    } catch (err) {
      console.error('❌ Processing failed:', err);
    } finally {
      setProcessing(false);
    }
  };

  return (
    <div>
      {processing && <div>Processing document...</div>}
      {result && (
        <div>
          <h3>Extracted Data:</h3>
          <p>Vendor: {result.vendorName}</p>
          <p>Amount: {result.currency} {result.totalAmount}</p>
          <p>Date: {result.transactionDate}</p>
          <p>Confidence: {Math.round(result.confidenceScore * 100)}%</p>
        </div>
      )}
    </div>
  );
};
```

**cURL Example:**
```bash
curl -X POST \
  https://your-project.supabase.co/functions/v1/process-document \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." \
  -H "Content-Type: application/json" \
  -H "apikey: eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." \
  -d '{
    "documentId": 123,
    "fileName": "550e8400-e29b-41d4-a716-446655440000/starbucks-receipt.pdf"
  }'
```

**Success Response Example:**
```json
{
  "success": true,
  "documentId": 123,
  "parsedData": {
    "documentType": "receipt",
    "vendorName": "Starbucks Corporation",
    "transactionDate": "2024-01-15",
    "totalAmount": 12.50,
    "currency": "MYR",
    "transactionType": "expense",
    "suggestedCategoryId": 5,
    "suggestedCategoryType": "expense",
    "confidenceScore": 0.95,
    "suggestedPaymentMethodId": 2
  }
}
```

## 🔄 Detailed Processing Workflow

### Phase 1: Input Validation & Security
```typescript
// 1. CORS handling for preflight requests
if (req.method === 'OPTIONS') {
  return new Response('ok', { headers: corsHeaders });
}

// 2. Authentication verification (handled by Supabase)
// 3. Input validation
const { documentId, fileName } = await req.json();
if (!documentId || !fileName) {
  throw new Error('Missing required parameters');
}
```

### Phase 2: Document Status Management
The function maintains detailed status tracking:

```mermaid
stateDiagram-v2
    [*] --> uploaded: File uploaded to storage
    uploaded --> processing: Edge function triggered
    processing --> ocr_completed: Text extraction finished
    ocr_completed --> parsed: AI parsing completed
    parsed --> transaction_created: User creates transaction
    processing --> failed: Any error occurs
    ocr_completed --> failed: Parsing fails
    failed --> [*]: Manual retry required
    transaction_created --> [*]: Workflow complete
```

Status updates are persisted using the `update_document_processing_status` RPC:
```sql
-- Database function signature
CREATE OR REPLACE FUNCTION update_document_processing_status(
  p_document_id BIGINT,
  p_status VARCHAR,
  p_raw_markdown_output TEXT DEFAULT NULL,
  p_document_type VARCHAR DEFAULT NULL,
  p_vendor_name VARCHAR DEFAULT NULL,
  p_transaction_date DATE DEFAULT NULL,
  p_total_amount NUMERIC DEFAULT NULL,
  p_transaction_type VARCHAR DEFAULT NULL,
  p_suggested_category_id BIGINT DEFAULT NULL,
  p_suggested_category_type VARCHAR DEFAULT NULL,
  p_ai_confidence_score NUMERIC DEFAULT NULL,
  p_suggested_payment_method_id INTEGER DEFAULT NULL
)
```

### Phase 3: File Processing Pipeline

#### Image Processing (PNG, JPG, JPEG)
```typescript
if (isImage) {
  console.log('🖼️ Processing as IMAGE with base64...');
  
  // Direct base64 encoding - no external upload needed
  const arrayBuffer = await fileData.arrayBuffer();
  const uint8Array = new Uint8Array(arrayBuffer);
  const base64String = btoa(String.fromCharCode(...uint8Array));
  const dataUri = `data:${mimeType};base64,${base64String}`;
  
  documentConfig = {
    type: "image_url",
    imageUrl: dataUri
  };
}
```

#### PDF Processing
```typescript
else {
  console.log('📄 Processing as DOCUMENT with signed URL...');
  
  // Upload file to Mistral for processing
  const fileObj = new File([await fileData.arrayBuffer()], fileName, { type: mimeType });
  
  const uploadedFile = await mistral.files.upload({
    file: fileObj,
    purpose: "ocr"
  });

  const signedUrlResponse = await mistral.files.getSignedUrl({
    fileId: uploadedFile.id
  });
  
  documentConfig = {
    type: "document_url",
    documentUrl: signedUrlResponse.url
  };
}
```

### Phase 4: OCR Processing with Intelligent Fallbacks

The system implements a sophisticated three-tier fallback strategy:

#### Tier 1: Mistral OCR API (Primary)
```typescript
try {
  ocrResponse = await mistral.ocr.process({
    model: "mistral-ocr-latest",
    document: documentConfig,
    includeImageBase64: isImage
  });
} catch (ocrError) {
  // Proceed to Tier 2 fallback
}
```

#### Tier 2: Mistral Vision Model (Images Only)
```typescript
if (isImage && ocrError) {
  const visionResponse = await mistral.chat.complete({
    model: "pixtral-12b-2409",
    messages: [{
      role: "user",
      content: [{
        type: "text",
        text: "Extract all text from this image. Return the text exactly as it appears, preserving formatting and structure. Focus on receipts, invoices, or financial documents."
      }, {
        type: "image_url",
        imageUrl: documentConfig.imageUrl
      }]
    }],
    temperature: 0.1,
    maxTokens: 2000
  });
}
```

#### Tier 3: Rule-Based Fallback (Last Resort)
```typescript
// Clean up markdown formatting and extract key data
const cleanText = ocrText
  .replace(/```[\s\S]*?```/g, '')  // Remove code blocks
  .replace(/#{1,6}\s*/g, '')       // Remove headers
  .replace(/\*\*(.*?)\*\*/g, '$1') // Remove bold formatting
  .trim();

// Pattern-based amount extraction
const amountPatterns = [
  /(?:Total|Grand\s*Total|Amount\s*Due|Balance|TOTAL)\s*:?\s*(?:RM|MYR|\$|USD)?\s*(\d+(?:\.\d{2})?)/i,
  /(?:RM|MYR|\$|USD)\s*(\d+(?:\.\d{2})?)/g,
  /(\d+\.\d{2})\s*(?:RM|MYR|\$|USD)?/g
];
```

### Phase 5: AI-Powered Data Extraction

The function uses advanced prompt engineering to extract structured data:

```typescript
const prompt = `You are an expert data extraction API specialized in financial documents.

**EXTRACTION REQUIREMENTS:**
1. Extract ONLY the fields specified in the schema below
2. Return a single, valid JSON object with no additional text
3. Use the exact field names and data types specified
4. For missing optional fields, omit them from the response
5. Dates must be in YYYY-MM-DD format
6. Amounts must be numeric (float/int), not strings

**DOCUMENT SCHEMA:**
{
  "vendor": "string (required) - Store/vendor name",
  "total": "float (required) - Final grand total amount as number",
  "purchase_date": "string (optional) - Date in YYYY-MM-DD format",
  "currency": "string (optional) - Currency code (RM/MYR, USD, EUR, etc.)",
  "transaction_type": "string (required) - 'expense' or 'income'",
  "suggested_category_id": "int (required) - Best category ID from list below",
  "confidence_score": "float (required) - Confidence level 0.0-1.0"
}

**AVAILABLE CATEGORIES:**
${context.expenseCategories.map(cat => 
  `${cat.id}: ${cat.name} - ${cat.description}`
).join('\n')}

**PAYMENT METHODS:**
${context.paymentMethods.map(pm => 
  `${pm.id}: ${pm.method_name}`
).join('\n')}

**DOCUMENT TEXT:**
---
${ocrText}
---`;
```

### Phase 6: Smart Category & Payment Method Matching

The AI considers user's existing categories and payment methods for intelligent suggestions:

```typescript
// The system provides context about user's existing data
const context = {
  expenseCategories: await supabase
    .from('expense_category')
    .select('id, name, description')
    .eq('isdeleted', false),
  
  incomeCategories: await supabase
    .from('income_category')
    .select('id, name, description')
    .eq('isdeleted', false),
    
  paymentMethods: await supabase
    .from('payment_methods')
    .select('id, method_name')
    .eq('isdeleted', false)
};
```

## 🗄️ Database Integration

### Core RPC Functions

The function integrates with several PostgreSQL stored procedures:

#### 1. `update_document_processing_status`
Updates document processing status and parsed data at each stage.

```sql
SELECT update_document_processing_status(
  p_document_id := 123,
  p_status := 'parsed',
  p_vendor_name := 'Starbucks Corporation',
  p_total_amount := 12.50,
  p_transaction_type := 'expense',
  p_suggested_category_id := 5,
  p_ai_confidence_score := 0.95
);
```

#### 2. Frontend Integration Functions
- **`insert_document_data`**: Creates initial document record
- **`create_transaction_from_document`**: Converts parsed data to actual transaction

### Document Lifecycle States

```mermaid
erDiagram
    DOCUMENT {
        bigint id PK
        uuid user_id FK
        varchar file_path
        varchar original_filename
        bigint file_size
        varchar mime_type
        varchar status
        text raw_markdown_output
        varchar document_type
        varchar vendor_name
        date transaction_date
        numeric total_amount
        varchar currency
        varchar transaction_type
        bigint suggested_category_id
        varchar suggested_category_type
        numeric ai_confidence_score
        integer suggested_payment_method_id
        timestamp created_at
        boolean isdeleted
    }
    
    EXPENSE_CATEGORY {
        bigint id PK
        varchar name
        text description
        boolean isdeleted
    }
    
    PAYMENT_METHODS {
        integer id PK
        varchar method_name
        boolean isdeleted
    }
    
    DOCUMENT ||--o| EXPENSE_CATEGORY : suggests
    DOCUMENT ||--o| PAYMENT_METHODS : suggests
```

## 🛡️ Error Handling & Resilience

### Multi-Model Fallback Strategy

The function implements sophisticated error recovery:

```typescript
const models = [
  "mistral-large-latest",    // Primary: Highest accuracy
  "mistral-medium-latest",   // Secondary: Good balance of speed/accuracy  
  "open-mistral-7b"          // Tertiary: Fastest, lower cost
];

for (let modelIndex = 0; modelIndex < models.length; modelIndex++) {
  const currentModel = models[modelIndex];
  
  for (let attempt = 1; attempt <= maxRetries; attempt++) {
    try {
      chatResponse = await client.chat.complete({
        model: currentModel,
        messages: [{ role: "user", content: prompt }],
        temperature: 0.1,
        maxTokens: 1000
      });
      
      console.log(`✅ AI parsing successful with ${currentModel}`);
      break; // Success - exit retry loop
      
    } catch (apiError) {
      if (apiError.statusCode === 429) {
        // Rate limited - exponential backoff
        const waitTime = Math.pow(2, attempt) * 1000;
        await new Promise(resolve => setTimeout(resolve, waitTime));
      } else {
        // Other errors - try next model
        console.log(`⚠️ ${currentModel} failed, trying next model...`);
        break;
      }
    }
  }
  
  if (chatResponse) break; // Success with current model
}
```

### Error Categories & Handling

| Error Type | Description | Recovery Strategy |
|------------|-------------|-------------------|
| **Network Errors** | Connection issues with Mistral API | Retry with exponential backoff |
| **Rate Limiting** | API quota exceeded | Switch to alternative model |
| **File Errors** | Invalid format, corrupted files | Return structured error response |
| **Processing Errors** | OCR/parsing failures | Fallback to vision model or rules |
| **Database Errors** | RPC function failures | Log error, return partial data |
| **Authentication** | Invalid API keys | Immediate failure with clear message |

### Comprehensive Error Logging

```typescript
console.error('❌ OCR API Error:', {
  error: ocrError,
  message: ocrError.message,
  status: ocrError.status || 'unknown',
  isImageType: isImage,
  mimeType: mimeType,
  fileSize: fileData.size,
  timestamp: new Date().toISOString()
});
```

## ⚡ Performance Optimization

### Processing Time Optimization

| Document Type | Average Time | Optimization Strategy |
|---------------|-------------|----------------------|
| **Clear Images** | 3-7 seconds | Direct base64 encoding |
| **Scanned PDFs** | 8-15 seconds | Mistral file upload + OCR |
| **Multi-page PDFs** | 15-30 seconds | Page-by-page processing |
| **Poor Quality** | 20-45 seconds | Multiple model attempts |

### Resource Management

```typescript
// Automatic cleanup of Mistral temporary files
finally {
  if (fileId) {
    try {
      console.log('🗑️ Cleaning up uploaded file...');
      await mistral.files.delete({ fileId: fileId });
      console.log('✅ File deleted from Mistral');
    } catch (deleteError) {
      console.warn('⚠️ Failed to delete file from Mistral:', deleteError);
    }
  }
}
```

### Cost Optimization Strategies

1. **Smart Model Selection**: Start with smaller models for simple documents
2. **Caching**: Store OCR results to avoid reprocessing
3. **File Size Limits**: Reject oversized files early
4. **Format Detection**: Optimize processing path based on file type

## 🚀 Setup & Deployment

### Local Development Environment

#### Prerequisites
```bash
# Install Supabase CLI
npm install -g supabase@latest

# Verify installation
supabase --version
```

#### Environment Setup
```bash
# 1. Clone the repository
git clone <repository-url>
cd tracker-zenith

# 2. Install dependencies
npm install

# 3. Setup local Supabase
supabase start

# 4. Create environment file
cat > .env.local << EOF
VITE_SUPABASE_URL=http://localhost:54321
VITE_SUPABASE_ANON_KEY=your-local-anon-key
MISTRAL_API_KEY=your-mistral-api-key
EOF

# 5. Start development servers
npm run dev                    # Frontend (Vite)
supabase functions serve       # Edge Functions
```

#### Local Function Testing
```bash
# Serve specific function
supabase functions serve process-document --env-file .env.local

# Test with curl
curl -i --location --request POST 'http://localhost:54321/functions/v1/process-document' \
  --header 'Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...' \
  --header 'Content-Type: application/json' \
  -d '{"documentId": 1, "fileName": "test/sample.pdf"}'
```

### Production Deployment

#### Supabase Project Setup
```bash
# 1. Link to production project
supabase login
supabase link --project-ref your-project-id

# 2. Deploy database migrations (if any)
supabase db push

# 3. Deploy edge function
supabase functions deploy process-document

# 4. Set production secrets
supabase secrets set MISTRAL_API_KEY=sk-your-production-key
```

#### Environment Configuration
```bash
# Production environment variables
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_SERVICE_ROLE_KEY=your-service-role-key
MISTRAL_API_KEY=sk-your-production-mistral-key

# Optional: Custom domain configuration
CUSTOM_DOMAIN=api.your-domain.com
```

#### CI/CD Pipeline Example (GitHub Actions)
```yaml
name: Deploy Edge Functions
on:
  push:
    branches: [main]
    paths: ['supabase/functions/**']

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Supabase CLI
        uses: supabase/setup-cli@v1
        
      - name: Deploy function
        run: |
          supabase functions deploy process-document
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
          PROJECT_REF: ${{ secrets.PROJECT_REF }}
```

## 📊 Monitoring & Analytics

### Function Monitoring
```bash
# Real-time logs
supabase functions logs process-document --follow

# Function statistics
supabase functions stats process-document

# Database query performance
supabase db inspect --query="
  SELECT 
    function_name,
    avg(duration_ms) as avg_duration,
    count(*) as invocations,
    count(*) filter (where status = 'error') as errors
  FROM function_logs 
  WHERE function_name = 'process-document'
  AND created_at > NOW() - INTERVAL '24 hours'
  GROUP BY function_name
"
```

### Performance Metrics Dashboard

| Metric | Target | Monitoring |
|--------|--------|------------|
| **Success Rate** | >95% | Function completion status |
| **Average Processing Time** | <15 seconds | Timestamp tracking |
| **Error Rate** | <5% | Exception counting |
| **API Cost** | <$0.10 per document | Mistral API usage |
| **Storage Usage** | Minimal | Automatic cleanup verification |

### Alerting Setup
```typescript
// Example monitoring integration
const monitoring = {
  success: (documentId: number, duration: number) => {
    console.log(`✅ Document ${documentId} processed in ${duration}ms`);
    // Send to analytics service
  },
  
  error: (documentId: number, error: Error) => {
    console.error(`❌ Document ${documentId} failed:`, error);
    // Alert on high error rates
    if (getErrorRate() > 0.1) {
      sendAlert('High error rate in document processing');
    }
  }
};
```

## 🔒 Security & Compliance

### Data Privacy Protection

1. **Temporary File Handling**
   - Files uploaded to Mistral AI are automatically deleted after processing
   - No persistent storage of document content on third-party servers
   - Processing happens in memory whenever possible

2. **Access Control**
   - Function requires valid Supabase authentication
   - Users can only process their own documents (enforced by RLS)
   - API keys stored securely as Supabase secrets

3. **Audit Trail**
   - All processing activities logged with timestamps
   - User actions tracked for compliance
   - Error logs exclude sensitive content

### Security Best Practices

```typescript
// Input sanitization
const sanitizeInput = (input: string): string => {
  return input
    .replace(/[<>\"']/g, '')  // Remove potential XSS characters
    .slice(0, 1000);          // Limit input length
};

// Rate limiting (handled by Supabase)
// Authentication verification (automatic)
// CORS headers properly configured
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};
```

### GDPR Compliance Features

- **Right to be Forgotten**: Documents can be permanently deleted
- **Data Portability**: Parsed data exportable in JSON format
- **Processing Transparency**: Clear documentation of AI processing steps
- **Consent Management**: User explicitly uploads documents for processing

## 🧪 Testing Strategy

### Unit Testing
```typescript
// test/document-processing.test.ts
import { describe, it, expect } from 'vitest';
import { parseWithAI } from '../index.ts';

describe('Document Processing', () => {
  it('should extract vendor name from receipt text', () => {
    const ocrText = 'Starbucks Corporation\nReceipt #12345\nTotal: $12.50';
    const result = parseWithAI(ocrText, mockContext);
    expect(result.vendorName).toBe('Starbucks Corporation');
    expect(result.totalAmount).toBe(12.50);
  });

  it('should handle malformed OCR text gracefully', () => {
    const ocrText = 'corrupted...text...';
    const result = parseWithAI(ocrText, mockContext);
    expect(result.confidenceScore).toBeLessThan(0.5);
  });
});
```

### Integration Testing
```bash
# Test with real Mistral API
npm run test:integration

# Test with mock data
npm run test:unit

# End-to-end testing
npm run test:e2e
```

### Load Testing
```javascript
// Load test script
const testConcurrentProcessing = async () => {
  const promises = Array.from({ length: 10 }, (_, i) => 
    processDocument(i, `test-file-${i}.pdf`)
  );
  
  const results = await Promise.allSettled(promises);
  const successful = results.filter(r => r.status === 'fulfilled').length;
  
  console.log(`✅ ${successful}/10 documents processed successfully`);
};
```

## 🔧 Advanced Configuration

### Custom Model Selection
```typescript
// Advanced model configuration
const modelConfig = {
  primary: "mistral-large-latest",
  fallback: ["mistral-medium-latest", "open-mistral-7b"],
  timeout: 30000,
  retries: 3,
  costThreshold: 0.10 // Max cost per document
};
```

### Plugin Architecture
```typescript
// Extensible processing plugins
interface ProcessingPlugin {
  name: string;
  process(ocrText: string): Promise<any>;
  canHandle(documentType: string): boolean;
}

const plugins: ProcessingPlugin[] = [
  new ReceiptPlugin(),
  new InvoicePlugin(),
  new BankStatementPlugin()
];
```

### Custom Category Training
```typescript
// Machine learning enhancement (future feature)
const trainCategoryModel = async (userId: string) => {
  const userTransactions = await getUserTransactions(userId);
  // Train personalized category suggestions
  return trainModel(userTransactions);
};
```

## 🚨 Troubleshooting Guide

### Common Issues & Solutions

#### Issue: "MISTRAL_API_KEY not set"
```bash
# Check if secret is configured
supabase secrets list

# Set the secret
supabase secrets set MISTRAL_API_KEY=your-key-here

# Verify in function logs
supabase functions logs process-document | grep "MISTRAL_API_KEY"
```

#### Issue: "Failed to download file"
```typescript
// Debug file path issues
const debugFilePath = (fileName: string) => {
  console.log('Attempting to download:', fileName);
  console.log('Expected format: user-id/uuid.extension');
  console.log('Actual format:', fileName.split('/'));
};
```

#### Issue: Low confidence scores
```typescript
// Confidence score interpretation
const interpretConfidence = (score: number) => {
  if (score > 0.9) return 'Excellent - auto-process';
  if (score > 0.7) return 'Good - review recommended';
  if (score > 0.5) return 'Fair - manual review required';
  return 'Poor - manual entry suggested';
};
```

#### Issue: Processing timeouts
```bash
# Increase function timeout (max 30 minutes for Pro plan)
# In supabase/config.toml:
[functions.process-document]
timeout = 300  # 5 minutes
```

### Debug Mode Activation
```typescript
// Enable verbose logging
const DEBUG_MODE = Deno.env.get('DEBUG_DOCUMENT_PROCESSING') === 'true';

if (DEBUG_MODE) {
  console.log('🔍 DEBUG: OCR text preview:', ocrText.substring(0, 500));
  console.log('🔍 DEBUG: AI parsing prompt:', prompt);
  console.log('🔍 DEBUG: Response data:', chatResponse);
}
```

## 📈 Future Enhancements

### Planned Features

1. **Multi-language Support**
   - OCR for non-English documents
   - Currency detection improvements
   - Regional date format handling

2. **Advanced AI Capabilities**
   - Line-item extraction from receipts
   - Tax calculation verification
   - Duplicate detection

3. **Performance Optimizations**
   - Edge caching for repeated documents
   - Progressive image enhancement
   - Batch processing for multiple documents

4. **Integration Expansions**
   - Email attachment processing
   - Mobile app camera integration
   - Bank statement import

### Migration to OpenRouter
> **Note**: This function is planned for migration from direct Mistral AI integration to OpenRouter for improved reliability and cost optimization. See the separate OpenRouter migration plan for details.

---

## 📞 Support & Contributing

### Getting Help
- **Documentation**: This README and inline code comments
- **Community**: GitHub Issues and Discussions
- **Professional Support**: Contact the development team

### Contributing Guidelines
1. **Code Standards**: TypeScript, comprehensive error handling, detailed logging
2. **Testing**: Unit tests required for new features
3. **Documentation**: Update README for any API changes
4. **Performance**: Monitor processing time and cost impact

### Code Review Checklist
- [ ] Error handling covers all failure modes
- [ ] Logging provides sufficient debugging information
- [ ] Security measures properly implemented
- [ ] Performance impact assessed
- [ ] Documentation updated

---

**📋 Document Version**: v3.0 (Comprehensive)  
**🕒 Last Updated**: January 2025  
**👥 Maintainers**: Tracker Zenith Development Team  
**📄 License**: Proprietary - Internal Use Only 