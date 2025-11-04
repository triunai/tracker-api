import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};

interface EmbeddingJob {
  id: number;
  table_name: string;
  record_id: number;
  content: string;
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
    const supabaseServiceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const openaiApiKey = Deno.env.get('OPENAI_API_KEY');
    
    if (!openaiApiKey) {
      throw new Error('OPENAI_API_KEY environment variable is required');
    }
    
    const supabase = createClient(supabaseUrl, supabaseServiceKey);

    console.log('🚀 Starting batch embedding processing (expense-only MVP)...');

    // Get pending embedding jobs (expense only, up to 10 at a time to avoid timeout)
    const { data: jobs, error: jobsError } = await supabase.rpc('get_pending_embedding_jobs', {
      p_limit: 10
    });

    if (jobsError) {
      console.error('❌ Error fetching jobs:', jobsError);
      throw new Error(`Failed to fetch jobs: ${jobsError.message}`);
    }

    if (!jobs || jobs.length === 0) {
      console.log('✅ No pending embedding jobs found');
      return new Response(
        JSON.stringify({ 
          success: true, 
          message: 'No pending jobs', 
          processed: 0 
        }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    console.log(`📊 Found ${jobs.length} pending expense jobs to process`);

    let successCount = 0;
    let errorCount = 0;
    const errors: string[] = [];

    // Process each job
    for (const job of jobs as EmbeddingJob[]) {
      try {
        console.log(`🔄 Processing job ${job.id} for ${job.table_name}:${job.record_id}`);

        // Validate that this is an expense job (MVP safety check)
        if (job.table_name !== 'expense') {
          console.warn(`⚠️ Skipping non-expense job: ${job.table_name}`);
          continue;
        }

        // Mark job as processing
        await supabase.rpc('update_embedding_job_status', {
          p_job_id: job.id,
          p_status: 'processing'
        });

        // Generate embedding using OpenAI API (text-embedding-3-small, 384 dimensions)
        const response = await fetch('https://api.openai.com/v1/embeddings', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${openaiApiKey}`,
            'Content-Type': 'application/json'
          },
          body: JSON.stringify({
            input: job.content,
            model: 'text-embedding-3-small',
            dimensions: 384
          })
        });

        if (!response.ok) {
          const errorText = await response.text();
          console.error(`❌ OpenAI API error for job ${job.id}:`, errorText);
          
          await supabase.rpc('update_embedding_job_status', {
            p_job_id: job.id,
            p_status: 'failed',
            p_error_message: `OpenAI API error: ${response.status} ${errorText}`
          });
          
          errors.push(`Job ${job.id}: OpenAI API error ${response.status}`);
          errorCount++;
          continue;
        }

        const embeddingData = await response.json();
        
        if (!embeddingData.data || !embeddingData.data[0] || !embeddingData.data[0].embedding) {
          console.error(`❌ Invalid embedding response for job ${job.id}:`, embeddingData);
          
          await supabase.rpc('update_embedding_job_status', {
            p_job_id: job.id,
            p_status: 'failed',
            p_error_message: 'Invalid embedding response from OpenAI'
          });
          
          errors.push(`Job ${job.id}: Invalid OpenAI response`);
          errorCount++;
          continue;
        }

        // Extract embedding from response
        const embedding = embeddingData.data[0].embedding;
        
        if (!embedding || !Array.isArray(embedding) || embedding.length !== 384) {
          console.error(`❌ Invalid embedding dimensions for job ${job.id}:`, {
            isArray: Array.isArray(embedding),
            length: embedding?.length,
            expected: 384
          });
          
          await supabase.rpc('update_embedding_job_status', {
            p_job_id: job.id,
            p_status: 'failed',
            p_error_message: `Invalid embedding dimensions: ${embedding?.length || 'unknown'} (expected 384)`
          });
          
          errors.push(`Job ${job.id}: Wrong dimensions (${embedding?.length || 'unknown'})`);
          errorCount++;
          continue;
        }

        // Update the expense record with the embedding (expense-only MVP)
        const embeddingVector = `[${embedding.join(',')}]`;
        
        await supabase.rpc('update_record_embedding', {
          p_table_name: job.table_name,
          p_record_id: job.record_id,
          p_embedding: embeddingVector
        });

        // Mark job as completed
        await supabase.rpc('update_embedding_job_status', {
          p_job_id: job.id,
          p_status: 'completed'
        });

        console.log(`✅ Successfully processed expense job ${job.id}`);
        successCount++;

      } catch (error) {
        console.error(`💥 Unexpected error processing job ${job.id}:`, error);
        
        await supabase.rpc('update_embedding_job_status', {
          p_job_id: job.id,
          p_status: 'failed',
          p_error_message: `Unexpected error: ${error.message}`
        });
        
        errors.push(`Job ${job.id}: Unexpected error - ${error.message}`);
        errorCount++;
      }
    }

    console.log(`🏁 Batch processing complete: ${successCount} success, ${errorCount} errors`);

    return new Response(
      JSON.stringify({
        success: true,
        processed: jobs.length,
        successful: successCount,
        failed: errorCount,
        mvp_mode: 'expense_only',
        embedding_provider: 'openai_text_embedding_3_small',
        errors: errors.length > 0 ? errors : undefined
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      },
    );

  } catch (error) {
    console.error('💥 Fatal error in embed-expense function:', error);

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