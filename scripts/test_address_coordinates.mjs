import test from 'node:test';
import assert from 'node:assert/strict';
import ts from 'typescript';
import vm from 'node:vm';
import fs from 'node:fs';
import { coordenadasValidas, cidadeDoEndereco, numeroDoEndereco, resultadoEnderecoCompativel } from '../src/features/routes/services/addressCoordinates.ts';

const exports = {};
vm.runInNewContext(ts.transpileModule(fs.readFileSync(new URL('../src/features/routes/services/routeOptimization.ts', import.meta.url), 'utf8'), {
  compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
}).outputText, { exports, require: () => ({ coordenadasValidas, resultadoEnderecoCompativel }), console, fetch: (...args) => globalThis.fetch(...args) });
const { geocodificarEndereco } = exports;

test('missing, zero, infinite and out-of-range coordinates are not destinations', () => {
  for (const point of [null, {}, {lat: 0, lng: 0}, {lat: NaN, lng: -48}, {lat: -27, lng: Infinity}, {lat: -91, lng: -48}, {lat: -27, lng: 181}, {lat: '-27', lng: -48}]) {
    assert.equal(coordenadasValidas(point), false);
  }
  assert.equal(coordenadasValidas({lat: -27.65, lng: -48.67}), true);
});

test('geocoding failure never fabricates a point in Florianópolis', async () => {
  const previous = globalThis.fetch;
  try {
    for (const [status, body] of [[200, []], [503, [{lat: '-27.5954', lon: '-48.5480'}]], [200, [{lat: 'invalid', lon: '-48'}]], [200, [{lat: '-27', lon: '999'}]]]) {
      globalThis.fetch = async () => new Response(JSON.stringify(body), {status});
      assert.equal(await geocodificarEndereco('R. Ver. Jacob Knabben da Silva, 3080, Palhoça'), null);
    }
  } finally { globalThis.fetch = previous; }
});

test('a successful lookup preserves the returned coordinates and full address', async () => {
  const previous = globalThis.fetch;
  try {
    const address = 'Rua Vereador Jacob Knabben da Silva, 3080, Palhoça, Santa Catarina, Brasil';
    globalThis.fetch = async (url) => {
      assert.match(decodeURIComponent(String(url)), /Palhoça/);
      return new Response(JSON.stringify([{lat: '-27.65', lon: '-48.67', display_name: address}]));
    };
    const result = await geocodificarEndereco(address);
    assert.equal(result.endereco, address);
    assert.equal(result.coordenadas.lat, -27.65);
    assert.equal(result.coordenadas.lng, -48.67);
  } finally { globalThis.fetch = previous; }
});

test('address metadata preserves Palhoça rather than labelling every destination Florianópolis', () => {
  assert.equal(cidadeDoEndereco('R. Ver. Jacob Knabben da Silva, 3080 - Pedra Branca, Palhoça - SC, 88132-292'), 'Palhoça');
  assert.equal(cidadeDoEndereco('Rua Vereador Jacob Knabben da Silva, Pagani, Palhoça, Santa Catarina, Brasil'), 'Palhoça');
  assert.equal(cidadeDoEndereco('Rua X, Centro, Florianópolis - SC'), 'Florianópolis');
  assert.equal(cidadeDoEndereco('Endereço não resolvido'), '');
});

test('saving rejects missing coordinates and sends the valid address and municipality unchanged', async () => {
  const saved = [];
  const saveExports = {};
  const code = ts.transpileModule(fs.readFileSync(new URL('../src/features/routes/services/salvarClienteEndereco.ts', import.meta.url), 'utf8'), {
    compilerOptions: {module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022},
  }).outputText;
  vm.runInNewContext(code, {exports: saveExports, crypto: globalThis.crypto, require: name => {
    if (name.includes('addressCoordinates')) return {coordenadasValidas, cidadeDoEndereco};
    if (name.includes('company')) return {requireCompanyId: async () => 'company', hasActiveSupabaseSession: async () => true};
    return {isSupabaseConfigured: true, supabase: {rpc: async (_name, args) => {saved.push(args.p_dados);return {data:{id:'address'}};}}};
  }});
  await assert.rejects(saveExports.salvarClienteEndereco({endereco_completo:'Palhoça'}));
  assert.equal(saved.length, 0);
  await saveExports.salvarClienteEndereco({endereco_completo:'Rua X, 3080, Palhoça - SC, 88132-292', coordenadas:{lat:-27.65,lng:-48.67}});
  assert.equal(saved[0].cidade, 'Palhoça');
  assert.equal(saved[0].cep, '88132-292');
  assert.equal(saved[0].latitude, -27.65);
  assert.equal(saved[0].longitude, -48.67);
});

test('numbered destinations require the requested number and municipality', async () => {
  const address = 'Avenida Pedra Branca, 95, Palhoça, SC, Brasil';
  assert.equal(numeroDoEndereco(address), '95');
  assert.equal(numeroDoEndereco('Rua X, Palhoça - SC, 88137-270'), '');
  assert.equal(resultadoEnderecoCompativel(address, 'Avenida Pedra Branca, Palhoça'), false);
  assert.equal(resultadoEnderecoCompativel(address, 'Avenida Pedra Branca, 95, Florianópolis'), false);
  assert.equal(resultadoEnderecoCompativel(address, address), true);
  const previous=globalThis.fetch;
  try {
    globalThis.fetch=async()=>new Response(JSON.stringify([
      {lat:'-27.6185',lon:'-48.6832',display_name:'Avenida Pedra Branca, Palhoça',address:{city:'Palhoça'}},
      {lat:'-27.6265',lon:'-48.6730',display_name:address,address:{city:'Palhoça',house_number:'95'}},
    ]));
    const result=await geocodificarEndereco(address);
    assert.equal(result.coordenadas.lat,-27.6265);
    assert.equal(result.endereco,address);
    globalThis.fetch=async()=>new Response(JSON.stringify([
      {lat:'-27.6185',lon:'-48.6832',display_name:'Avenida Pedra Branca, Palhoça',address:{city:'Palhoça'}},
    ]));
    assert.equal(await geocodificarEndereco(address),null);
  } finally {globalThis.fetch=previous;}
});
