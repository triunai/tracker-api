import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type'
};

interface EmbedRequest {
  content: string;
}

serve(async (req) => {
  // Handle CORS preflight requests
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const { content }: EmbedRequest = await req.json();

    if (!content || typeof content !== 'string' || content.trim().length === 0) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Content is required and must be a non-empty string'
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 400,
        },
      );
    }

    console.log('🔍 Generating embedding for content:', content.substring(0, 100) + '...');

    const openaiApiKey = Deno.env.get('OPENAI_API_KEY');
    
    if (!openaiApiKey) {
      return new Response(
        JSON.stringify({
          success: false,
          error: 'OPENAI_API_KEY environment variable is required'
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 500,
        },
      );
    }

    // Generate embedding using OpenAI API (text-embedding-3-small, 384 dimensions)
    const response = await fetch('https://api.openai.com/v1/embeddings', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${openaiApiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        input: content.trim(),
        model: 'text-embedding-3-small',
        dimensions: 384
      })
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('❌ OpenAI API error:', errorText);
      return new Response(
        JSON.stringify({
          success: false,
          error: `OpenAI API error: ${response.status} ${errorText}`
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 500,
        },
      );
    }

    const embeddingData = await response.json();
    
    if (!embeddingData.data || !embeddingData.data[0] || !embeddingData.data[0].embedding) {
      console.error('❌ Invalid embedding response:', embeddingData);
      return new Response(
        JSON.stringify({
          success: false,
          error: 'Invalid embedding response from OpenAI'
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 500,
        },
      );
    }

    const embedding = embeddingData.data[0].embedding;

    // Validate embedding data
    if (!embedding || !Array.isArray(embedding) || embedding.length !== 384) {
      console.error('❌ Invalid embedding response:', {
        isArray: Array.isArray(embedding),
        length: embedding?.length,
        expected: 384
      });
      return new Response(
        JSON.stringify({
          success: false,
          error: `Invalid embedding response: expected 384-dim array, got ${embedding?.length || 'unknown'}`
        }),
        {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 500,
        },
      );
    }

    console.log('✅ Successfully generated 384-dimensional embedding');

    return new Response(
      JSON.stringify({
        success: true,
        embedding: embedding,
        dimensions: embedding.length,
        model: 'text-embedding-3-small',
        provider: 'openai'
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      },
    );

  } catch (error) {
    console.error('💥 Fatal error in embed-query function:', error);

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