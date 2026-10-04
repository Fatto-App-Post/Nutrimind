import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    );

    const { data: { user }, error: userError } = await supabaseClient.auth.getUser();
    if (userError || !user) {
      throw new Error('Unauthorized');
    }

    const { title, body, user_id, data = {} } = await req.json();

    if (!title || !body || !user_id) {
      throw new Error('title, body, and user_id are required');
    }

    // Get user's device tokens
    const { data: tokens } = await supabaseClient
      .from('device_tokens')
      .select('token, platform')
      .eq('user_id', user_id);

    if (!tokens || tokens.length === 0) {
      return new Response(
        JSON.stringify({ sent: 0, message: 'No device tokens found' }),
        { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
      );
    }

    // Send to Firebase Cloud Messaging (FCM)
    const fcmKey = Deno.env.get('FIREBASE_SERVER_KEY');
    if (!fcmKey) {
      throw new Error('FIREBASE_SERVER_KEY not configured');
    }

    const fcmUrl = 'https://fcm.googleapis.com/fcm/send';
    
    let sent = 0;
    for (const token of tokens) {
      try {
        const payload = {
          to: token.token,
          notification: {
            title,
            body,
          },
          data: {
            ...data,
            type: 'nutrimind_notification',
          },
        };

        const response = await fetch(fcmUrl, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': `key=${fcmKey}`,
          },
          body: JSON.stringify(payload),
        });

        if (response.ok) {
          sent++;
        }
      } catch (err) {
        console.error('Error sending to token:', token.token, err);
      }
    }

    return new Response(
      JSON.stringify({ sent, total: tokens.length }),
      { headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  } catch (error) {
    console.error('Error sending notification:', error);
    return new Response(
      JSON.stringify({ error: error instanceof Error ? error.message : 'Unknown error' }),
      { status: 400, headers: { ...corsHeaders, 'Content-Type': 'application/json' } }
    );
  }
});
