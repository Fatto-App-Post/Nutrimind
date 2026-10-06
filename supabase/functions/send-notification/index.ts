import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';
import { importPKCS8, SignJWT } from 'https://esm.sh/jose@5.9.6';

// Invio push tramite FCM HTTP v1. L'API legacy (fcm/send con server key)
// è stata dismessa da Google a luglio 2024.
//
// Secret richiesto: FIREBASE_SERVICE_ACCOUNT = JSON completo del service
// account (Firebase Console > Impostazioni progetto > Account di servizio
// > Genera nuova chiave privata).
//
// Chi può inviare: il service role (job/trigger lato server), un admin,
// oppure un nutrizionista con collegamento attivo verso il destinatario.

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...corsHeaders, 'Content-Type': 'application/json' } });

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

let cachedToken: { value: string; expiresAt: number } | null = null;

async function getAccessToken(sa: ServiceAccount): Promise<string> {
  if (cachedToken && cachedToken.expiresAt > Date.now() + 60_000) return cachedToken.value;

  const key = await importPKCS8(sa.private_key, 'RS256');
  const now = Math.floor(Date.now() / 1000);
  const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/firebase.messaging' })
    .setProtectedHeader({ alg: 'RS256', typ: 'JWT' })
    .setIssuer(sa.client_email)
    .setAudience('https://oauth2.googleapis.com/token')
    .setIssuedAt(now)
    .setExpirationTime(now + 3600)
    .sign(key);

  const res = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
  });
  if (!res.ok) throw new Error(`Google OAuth error (HTTP ${res.status})`);
  const data = await res.json();
  cachedToken = { value: data.access_token, expiresAt: Date.now() + data.expires_in * 1000 };
  return cachedToken.value;
}

/// Vero se [key] è una chiave con privilegi di servizio del progetto: la
/// service_role JWT legacy o una secret key `sb_secret_...`. Il confronto
/// con SUPABASE_SERVICE_ROLE_KEY non basta, perché con le nuove chiavi
/// il chiamante può usarne una diversa ma ugualmente valida. Si verifica
/// quindi con un'operazione riservata alle chiavi di servizio.
async function isServiceKey(key: string, serviceRoleKey: string): Promise<boolean> {
  if (key === serviceRoleKey) return true;
  const looksLikeServiceKey = key.startsWith('sb_secret_') || jwtRole(key) === 'service_role';
  if (!looksLikeServiceKey) return false;
  const probe = createClient(Deno.env.get('SUPABASE_URL') ?? '', key, { auth: { persistSession: false } });
  const { error } = await probe.auth.admin.listUsers({ page: 1, perPage: 1 });
  return !error;
}

/// Claim `role` di un JWT senza verificarne la firma: usato solo per
/// decidere se tentare la verifica lato server in isServiceKey.
function jwtRole(token: string): string | null {
  const parts = token.split('.');
  if (parts.length !== 3) return null;
  try {
    const payload = JSON.parse(atob(parts[1].replace(/-/g, '+').replace(/_/g, '/')));
    return typeof payload.role === 'string' ? payload.role : null;
  } catch {
    return null;
  }
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders });
  }

  try {
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
    const admin = createClient(Deno.env.get('SUPABASE_URL') ?? '', serviceRoleKey);

    const body = await req.json().catch(() => null);
    const { title, body: text, user_id, data = {} } = body ?? {};
    if (!title || !text || !user_id) {
      return json({ error: 'title, body, and user_id are required', code: 'invalid_request' }, 400);
    }

    // Autorizzazione
    const bearer = (req.headers.get('Authorization') ?? '').replace(/^Bearer\s+/i, '');
    if (!bearer) return json({ error: 'Unauthorized', code: 'unauthorized' }, 401);
    if (!(await isServiceKey(bearer, serviceRoleKey))) {
      const { data: { user }, error } = await admin.auth.getUser(bearer);
      if (error || !user) return json({ error: 'Unauthorized', code: 'unauthorized' }, 401);

      const { data: profile } = await admin.from('profiles').select('role').eq('id', user.id).maybeSingle();
      let allowed = profile?.role === 'admin';
      if (!allowed && profile?.role === 'nutritionist') {
        const { data: link } = await admin
          .from('patient_links')
          .select('id')
          .eq('nutritionist_id', user.id)
          .eq('patient_id', user_id)
          .eq('status', 'active')
          .maybeSingle();
        allowed = !!link;
      }
      if (!allowed) return json({ error: 'Forbidden', code: 'forbidden' }, 403);
    }

    const rawSa = Deno.env.get('FIREBASE_SERVICE_ACCOUNT');
    if (!rawSa) return json({ error: 'FIREBASE_SERVICE_ACCOUNT not configured', code: 'not_configured' }, 503);
    const sa = JSON.parse(rawSa) as ServiceAccount;

    const { data: tokens } = await admin
      .from('device_tokens')
      .select('token, platform')
      .eq('user_id', user_id);

    if (!tokens || tokens.length === 0) {
      return json({ sent: 0, total: 0, message: 'No device tokens found' });
    }

    const accessToken = await getAccessToken(sa);
    const fcmUrl = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
    // In HTTP v1 i valori di `data` devono essere stringhe
    const stringData: Record<string, string> = { type: 'nutrimind_notification' };
    for (const [k, v] of Object.entries(data as Record<string, unknown>)) {
      if (v !== null && v !== undefined) stringData[k] = typeof v === 'string' ? v : JSON.stringify(v);
    }

    let sent = 0;
    const stale: string[] = [];
    for (const { token } of tokens) {
      const res = await fetch(fcmUrl, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'Authorization': `Bearer ${accessToken}` },
        body: JSON.stringify({ message: { token, notification: { title, body: text }, data: stringData } }),
      });
      if (res.ok) {
        sent++;
      } else if (res.status === 404 || res.status === 400) {
        // UNREGISTERED / INVALID_ARGUMENT: token non più valido
        const err = await res.json().catch(() => ({}));
        const code = err?.error?.details?.[0]?.errorCode ?? err?.error?.status;
        if (code === 'UNREGISTERED' || code === 'INVALID_ARGUMENT') stale.push(token);
      } else {
        console.error('FCM error', res.status);
      }
    }

    if (stale.length) await admin.from('device_tokens').delete().in('token', stale);

    return json({ sent, total: tokens.length, removed: stale.length });
  } catch (error) {
    console.error('Error sending notification:', error instanceof Error ? error.message : error);
    return json({ error: 'Internal error', code: 'internal_error' }, 500);
  }
});
