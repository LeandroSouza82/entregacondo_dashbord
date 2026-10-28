type Checkout = { id: string; email: string; url?: string; preapproval_id?: string; valor: number; ambiente: 'test' | 'production'; inicio_cobranca?: string | null; servidor_em?: string; estado_provedor?: string };
type PaymentContext = { checkout_id: string; preapproval_id: string };
type BillingDiagnostic = {
  status: number;
  reason: 'test_account_mismatch' | 'invalid_credentials' | 'invalid_return_url' | 'invalid_payer' | 'provider_rejected' | 'provider_unavailable' | 'network_unavailable';
};
type Dependencies = {
  accessToken: string; webhookSecret: string; publicUrl: string; allowedOrigins?: string[]; live: boolean;
  reserve: (jwt: string, company: string) => Promise<Checkout>;
  link: (id: string, preapproval: string, url: string) => Promise<boolean>;
  context: (payment: string) => Promise<PaymentContext | null>;
  record: (params: Record<string, unknown>) => Promise<boolean>;
  lookup?: (jwt: string, company: string) => Promise<{id: string; preapproval_id?: string; ambiente: string} | null>;
  sync?: (params: Record<string, unknown>) => Promise<boolean>;
  fetch: typeof fetch;
  reportProviderFailure?: (diagnostic: BillingDiagnostic) => void;
};
const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const resourceId = /^[a-zA-Z0-9_-]{1,100}$/;
function reply(status: number, body: object, origin?: string) {
  return new Response(JSON.stringify(body), { status, headers: {
    'Content-Type': 'application/json', 'Cache-Control': 'no-store',
    ...(origin ? { 'Access-Control-Allow-Origin': origin, 'Vary': 'Origin', 'Access-Control-Allow-Headers': 'authorization, apikey, x-client-info, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' } : {}),
  } });
}
function checkoutUrl(value: unknown) {
  const url = new URL(String(value));
  if (url.protocol !== 'https:' || !['www.mercadopago.com.br', 'mercadopago.com.br'].includes(url.hostname)) throw new Error('Invalid checkout URL');
  return url.href;
}
async function jsonBody(req: Request | Response) {
  const reader = req.body?.getReader(); let bytes = 0; const chunks: Uint8Array[] = [];
  if (!reader) throw new Error('Empty body');
  while (true) { const { value, done } = await reader.read(); if (done) break; bytes += value.length; if (bytes > 32768) { await reader.cancel(); throw new Error('Body too large'); } chunks.push(value); }
  const body = new Uint8Array(bytes); let offset = 0; for (const chunk of chunks) { body.set(chunk, offset); offset += chunk.length; }
  return JSON.parse(new TextDecoder().decode(body));
}
function reportProviderFailure(deps: Dependencies, diagnostic: BillingDiagnostic) {
  // Only fixed categories and HTTP status may leave this helper. Never log
  // provider bodies, request payloads, emails, session JWTs or server secrets.
  try { deps.reportProviderFailure?.(diagnostic); } catch { /* Diagnostics cannot affect billing. */ }
}
function providerFailure(status: number, message: unknown): BillingDiagnostic {
  const text = typeof message === 'string' ? message.toLowerCase() : '';
  const reason = status === 401 || status === 403 ? 'invalid_credentials'
    : text.includes('both payer and collector') && text.includes('test') ? 'test_account_mismatch'
    : text.includes('back_url') ? 'invalid_return_url'
    : text.includes('payer_email') ? 'invalid_payer'
    : status >= 500 ? 'provider_unavailable' : 'provider_rejected';
  return { status, reason };
}
async function mp(deps: Dependencies, path: string, init?: RequestInit) {
  if (!deps.accessToken) throw new Error('Billing not configured');
  let response: Response;
  try {
    response = await deps.fetch('https://api.mercadopago.com' + path, { ...init,
      headers: { Authorization: 'Bearer ' + deps.accessToken, 'Content-Type': 'application/json', ...init?.headers },
      signal: AbortSignal.timeout(6000), redirect: 'error',
    });
  } catch {
    reportProviderFailure(deps, { status: 0, reason: 'network_unavailable' });
    throw new Error('Payment provider unavailable');
  }
  if (!response.ok) {
    let message: unknown;
    try { message = (await jsonBody(response))?.message; } catch { /* Malformed or oversized response. */ }
    reportProviderFailure(deps, providerFailure(response.status, message));
    throw new Error('Payment provider unavailable');
  }
  return await response.json();
}

async function syncSubscription(deps: Dependencies, id: string, expectedCheckout?: string) {
  if (!resourceId.test(id) || !deps.sync) throw new Error('Subscription reconciliation unavailable');
  const subscription = await mp(deps, '/preapproval/' + id);
  const merchant = await mp(deps, '/users/me');
  if (subscription.id !== id || !uuid.test(subscription.external_reference)
    || (expectedCheckout && subscription.external_reference !== expectedCheckout)
    || !/^\d+$/.test(String(merchant.id)) || String(subscription.collector_id) !== String(merchant.id)
    || Number(subscription.auto_recurring?.transaction_amount) !== 149.90
    || subscription.auto_recurring?.currency_id !== 'BRL' || subscription.auto_recurring?.frequency !== 1
    || subscription.auto_recurring?.frequency_type !== 'months'
    || !['pending', 'authorized', 'paused', 'cancelled'].includes(subscription.status)
    || !Number.isFinite(Date.parse(subscription.last_modified))) throw new Error('Invalid subscription');
  if (!await deps.sync({p_checkout_id: subscription.external_reference, p_preapproval_id: id,
    p_status: subscription.status, p_atualizado_em: subscription.last_modified,
    p_inicio_cobranca: subscription.auto_recurring?.start_date || null,
    p_proxima_cobranca: subscription.next_payment_date || null})) throw new Error('Subscription not recorded');
  return subscription.status;
}

export function createCheckoutHandler(deps: Dependencies) {
  const returnOrigin = new URL(deps.publicUrl).origin;
  return async (req: Request) => {
    const requestOrigin = req.headers.get('origin');
    if (requestOrigin && ![returnOrigin, ...(deps.allowedOrigins || [])].includes(requestOrigin)) return reply(403, { error: 'Origem não permitida.' });
    const origin = requestOrigin || returnOrigin;
    if (req.method === 'OPTIONS') return reply(200, {}, origin);
    if (req.method !== 'POST') return reply(405, { error: 'Método não permitido.' }, origin);
    const jwt = req.headers.get('authorization')?.match(/^Bearer (\S+)$/i)?.[1];
    if (!jwt) return reply(401, { error: 'Entre na sua conta.' }, origin);
    if (!deps.accessToken || !deps.webhookSecret) return reply(503, { error: 'Pagamento ainda não configurado.' }, origin);
    try {
      const body = await jsonBody(req);
      if (!uuid.test(body?.empresa_id)) return reply(400, { error: 'Empresa inválida.' }, origin);
      if (body.consultar === true) {
        if (!deps.lookup) throw new Error('Subscription lookup unavailable');
        const saved = await deps.lookup(jwt, body.empresa_id);
        if (!saved?.preapproval_id) return reply(200, { estado: 'sem_checkout' }, origin);
        if (saved.ambiente !== (deps.live ? 'production' : 'test')) return reply(503, { error: 'Pagamentos ainda estão em validação.' }, origin);
        const estado = await syncSubscription(deps, saved.preapproval_id, saved.id);
        return reply(200, { estado }, origin);
      }
      // reserve validates the JWT and approved manager membership on the server.
      const checkout = await deps.reserve(jwt, body.empresa_id);
      if (!uuid.test(checkout.id) || Number(checkout.valor) !== 149.90) throw new Error('Invalid plan');
      if (checkout.ambiente !== (deps.live ? 'production' : 'test')) return reply(503, { error: 'Pagamentos ainda estão em validação. Tente novamente mais tarde.' }, origin);
      if (checkout.url) {
        const estado = await syncSubscription(deps, String(checkout.preapproval_id), checkout.id);
        if (estado === 'authorized') return reply(200, { estado }, origin);
        if (estado !== 'pending') return reply(409, { error: 'A assinatura foi pausada ou cancelada. Atualize a situação antes de continuar.' }, origin);
        return reply(200, { url: checkoutUrl(checkout.url) }, origin);
      }
      let scheduledStart: string | undefined;
      if (checkout.inicio_cobranca) {
        const start = Date.parse(checkout.inicio_cobranca), serverNow = Date.parse(checkout.servidor_em || '');
        if (!Number.isFinite(start) || !Number.isFinite(serverNow)) throw new Error('Invalid billing schedule');
        if (start > serverNow) scheduledStart = new Date(start).toISOString();
      }
      const subscription = await mp(deps, '/preapproval', { method: 'POST',
        headers: { 'X-Idempotency-Key': checkout.id }, body: JSON.stringify({
          reason: 'EntregaCondo · Plano mensal', external_reference: checkout.id, payer_email: checkout.email,
          auto_recurring: { frequency: 1, frequency_type: 'months', transaction_amount: 149.90, currency_id: 'BRL', ...(scheduledStart ? { start_date: scheduledStart } : {}) },
          back_url: returnOrigin + '/#/assinatura', status: 'pending',
        }),
      });
      if (typeof subscription.id !== 'string' || !resourceId.test(subscription.id)) throw new Error('Invalid subscription');
      if (scheduledStart && Date.parse(subscription.auto_recurring?.start_date) !== Date.parse(scheduledStart)) throw new Error('Provider did not preserve trial');
      const url = checkoutUrl(subscription.init_point);
      if (!await deps.link(checkout.id, String(subscription.id), url)) throw new Error('Checkout changed');
      return reply(200, { url }, origin);
    } catch { return reply(400, { error: 'Não foi possível preparar o pagamento. Confira seu acesso e tente novamente.' }, origin); }
  };
}

export async function validWebhookSignature(req: Request, id: string, secret: string) {
  if (!secret || !resourceId.test(id)) return false;
  const requestId = req.headers.get('x-request-id') || '';
  if (!/^[a-zA-Z0-9_-]{1,200}$/.test(requestId)) return false;
  const parts = (req.headers.get('x-signature') || '').split(',').map(v => v.trim().split('='));
  if (parts.filter(p => p[0] === 'ts').length !== 1 || parts.filter(p => p[0] === 'v1').length !== 1) return false;
  const ts = parts.find(p => p[0] === 'ts')?.[1] || '', signature = parts.find(p => p[0] === 'v1')?.[1] || '';
  if (!/^\d{10,13}$/.test(ts) || !/^[a-f0-9]{64}$/i.test(signature)) return false;
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey('raw', encoder.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const signed = new Uint8Array(await crypto.subtle.sign('HMAC', key, encoder.encode(`id:${id.toLowerCase()};request-id:${requestId};ts:${ts};`)));
  let difference = 0; for (let i = 0; i < signed.length; i++) difference |= signed[i] ^ parseInt(signature.slice(i * 2, i * 2 + 2), 16);
  // Old deliveries are safe: resource state is fetched again and the DB records
  // payment ids idempotently. Rejecting old timestamps would break MP retries.
  return difference === 0;
}

export function createSubscriptionWebhook(deps: Dependencies) {
  let merchant: { id: string; until: number } | null = null;
  async function merchantId() {
    if (merchant && merchant.until > Date.now()) return merchant.id;
    const account = await mp(deps, '/users/me');
    if (!/^\d+$/.test(String(account.id))) throw new Error('Invalid merchant');
    merchant = { id: String(account.id), until: Date.now() + 300_000 }; return merchant.id;
  }
  return async (req: Request) => {
    if (req.method !== 'POST') return reply(405, {});
    if (!deps.webhookSecret || !deps.accessToken) return reply(503, {});
    try {
      const url = new URL(req.url); const id = url.searchParams.get('data.id') || '';
      if (!await validWebhookSignature(req, id, deps.webhookSecret)) return reply(401, {});
      const body = await jsonBody(req); const type = body?.type;
      if (String(body?.data?.id).toLowerCase() !== id.toLowerCase() || (url.searchParams.has('type') && url.searchParams.get('type') !== type)) return reply(400, {});
      if (type === 'subscription_preapproval') {
        await syncSubscription(deps, id);
        return reply(200, { received: true });
      }
      if (!['subscription_authorized_payment', 'payment'].includes(type)) return reply(200, { received: true });
      if (!/^\d{1,30}$/.test(id)) return reply(400, {});
      let context: PaymentContext; let payment;
      if (type === 'subscription_authorized_payment') {
        const invoice = await mp(deps, '/authorized_payments/' + id);
        if (String(invoice.id) !== id || !resourceId.test(String(invoice.preapproval_id)) || Number(invoice.transaction_amount) !== 149.90 || invoice.currency_id !== 'BRL') throw new Error('Invalid invoice');
        if (!invoice.payment?.id) return reply(200, { received: true });
        const subscription = await mp(deps, '/preapproval/' + invoice.preapproval_id);
        if (String(subscription.id) !== String(invoice.preapproval_id) || !uuid.test(String(subscription.external_reference))
          || String(subscription.collector_id) !== await merchantId()
          || Number(subscription.auto_recurring?.transaction_amount) !== 149.90 || subscription.auto_recurring?.currency_id !== 'BRL'
          || subscription.auto_recurring?.frequency !== 1 || subscription.auto_recurring?.frequency_type !== 'months') throw new Error('Invalid subscription');
        if (invoice.external_reference && String(invoice.external_reference) !== String(subscription.external_reference)) throw new Error('Wrong invoice reference');
        context = { checkout_id: String(subscription.external_reference), preapproval_id: String(subscription.id) };
        if (!/^\d{1,30}$/.test(String(invoice.payment.id))) throw new Error('Invalid payment id');
        payment = await mp(deps, '/v1/payments/' + invoice.payment.id);
        if (String(payment.id) !== String(invoice.payment.id)) throw new Error('Wrong payment');
      } else {
        // A standalone payment cannot grant access. This path only reconciles
        // previously registered subscription charges (refunds/chargebacks).
        const saved = await deps.context(id);
        if (!saved) return reply(200, { received: true });
        context = saved; payment = await mp(deps, '/v1/payments/' + id);
        if (String(payment.id) !== id) throw new Error('Wrong payment');
      }
      if (String(payment.collector_id) !== await merchantId() || payment.live_mode !== deps.live
        || Number(payment.transaction_amount) !== 149.90
        || payment.currency_id !== 'BRL' || !Number.isFinite(Date.parse(payment.date_last_updated))) throw new Error('Invalid payment');
      const ok = await deps.record({ p_checkout_id: context.checkout_id, p_preapproval_id: context.preapproval_id,
        p_pagamento_id: String(payment.id), p_status: Number(payment.transaction_amount_refunded || 0) > 0 ? 'refunded' : payment.status, p_valor: Number(payment.transaction_amount), p_moeda: payment.currency_id,
        p_aprovado_em: payment.date_approved || null, p_atualizado_em: payment.date_last_updated });
      if (!ok) throw new Error('Payment not recorded');
      return reply(200, { received: true });
    } catch { return reply(500, { error: 'Não foi possível conferir a notificação.' }); }
  };
}
