const origins = new Set(['https://entregacondo.com.br', 'https://www.entregacondo.com.br']);
const states = new Set('AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO'.split(' '));
const vehicles = new Set(['moto', 'carro', 'bicicleta', 'van', 'outro']);

Deno.serve(async (req: Request) => {
  const origin = req.headers.get('origin') || '';
  const headers = { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'Vary': 'Origin',
    ...(origins.has(origin) ? { 'Access-Control-Allow-Origin': origin } : {}),
    'Access-Control-Allow-Headers': 'authorization, apikey, content-type', 'Access-Control-Allow-Methods': 'POST, OPTIONS' };
  const reply = (status: number, message: string) => new Response(JSON.stringify({ message }), { status, headers });
  if (!origins.has(origin)) return reply(403, 'Origem não permitida.');
  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers });
  if (req.method !== 'POST') return reply(405, 'Método não permitido.');
  try {
    if (!req.headers.get('content-type')?.startsWith('application/json')) return reply(415, 'Envie os dados em JSON.');
    // Bound streamed bodies as well as Content-Length, without logging personal data.
    const reader = req.body?.getReader();
    if (!reader) return reply(400, 'Preencha o formulário.');
    let length = 0; const chunks: Uint8Array[] = [];
    while (true) { const { done, value } = await reader.read(); if (done) break;
      length += value.length; if (length > 4096) { await reader.cancel(); return reply(413, 'Formulário muito grande.'); } chunks.push(value); }
    const bytes = new Uint8Array(length); let offset = 0; for (const c of chunks) { bytes.set(c, offset); offset += c.length; }
    const data = JSON.parse(new TextDecoder().decode(bytes));
    if (data.website) return reply(200, 'Interesse registrado. Quando o lançamento estiver disponível, avisaremos por e-mail.');
    const clean = (v: unknown) => typeof v === 'string' ? v.trim() : '';
    const nome = clean(data.nome), email = clean(data.email).toLowerCase(), cidade = clean(data.cidade), uf = clean(data.uf).toUpperCase();
    const veiculo = clean(data.veiculo) || null;
    if (nome.length < 2 || nome.length > 100 || cidade.length < 2 || cidade.length > 100 || email.length > 254 || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || !states.has(uf) || (veiculo && !vehicles.has(veiculo)) || data.consentimento !== true) {
      return reply(400, 'Confira nome, e-mail, cidade, estado e a autorização para receber o aviso.');
    }
    const url = Deno.env.get('SUPABASE_URL')!, key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
    const ip = (req.headers.get('x-forwarded-for') || req.headers.get('x-real-ip') || 'unknown').split(',').at(-1)!.trim();
    const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(key + ':interesse:' + new Date().toISOString().slice(0, 10) + ':' + ip));
    const chave = Array.from(new Uint8Array(digest), n => n.toString(16).padStart(2, '0')).join('');
    const result = await fetch(url + '/rest/v1/rpc/registrar_interesse_motorista', {
      method: 'POST', headers: { apikey: key, Authorization: 'Bearer ' + key, 'Content-Type': 'application/json' },
      body: JSON.stringify({ p_nome: nome, p_email: email, p_cidade: cidade, p_uf: uf, p_veiculo: veiculo, p_chave: chave }),
    });
    if (!result.ok) {
      const failure = await result.text();
      return failure.includes('rate_limit') ? reply(429, 'Muitas tentativas. Aguarde uma hora e tente novamente.') : reply(503, 'Não foi possível salvar agora. Tente novamente em instantes.');
    }
    return reply(200, 'Interesse registrado. Quando o lançamento estiver disponível, avisaremos por e-mail.');
  } catch { return reply(400, 'Não foi possível processar o formulário. Confira os dados e tente novamente.'); }
});
