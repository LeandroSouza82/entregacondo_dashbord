import { apiUrl, publicKey } from './interesse-config.js';
const $ = id => document.getElementById(id);
const status = $('admin-status'); let session, records = [], shown = 100, loading = false;
function token() {
  try { return JSON.parse(localStorage.getItem('sb-' + new URL(apiUrl).hostname.split('.')[0] + '-auth-token'))?.access_token; } catch { return null; }
}
async function api(path, options = {}) {
  const response = await fetch(apiUrl + path, { ...options, headers: { apikey: publicKey, Authorization: 'Bearer ' + session, ...options.headers }, signal: AbortSignal.timeout(20000) });
  if (!response.ok) throw new Error(response.status === 401 ? 'Sua sessão expirou. Entre novamente no painel e volte a esta página.' : 'Não foi possível consultar os dados. Confira seu acesso e tente novamente.');
  return response.status === 204 ? null : response.json();
}
function render() {
  const term = $('search').value.trim().toLocaleLowerCase('pt-BR');
  const filtered = records.filter(r => [r.nome,r.email,r.cidade,r.uf].join(' ').toLocaleLowerCase('pt-BR').includes(term));
  const body = $('rows'); body.replaceChildren();
  for (const record of filtered.slice(0, shown)) {
    const tr = document.createElement('tr');
    for (const value of [new Date(record.created_at).toLocaleDateString('pt-BR'),record.nome,record.email,record.cidade + ' / ' + record.uf,record.veiculo || 'Não informado']) {
      const td = document.createElement('td'); td.textContent = value; tr.append(td);
    }
    const td = document.createElement('td'), button = document.createElement('button'); button.type = 'button'; button.textContent = 'Excluir';
    button.addEventListener('click', async () => {
      if (!confirm('Excluir definitivamente o interesse de ' + record.email + '? Essa pessoa sairá da lista de lançamento.')) return;
      button.disabled = true;
      try { await api('/rest/v1/interesse_motoristas?id=eq.' + encodeURIComponent(record.id), { method:'DELETE', headers:{ Prefer:'return=minimal' } }); await load(); }
      catch (error) { status.textContent = error.message; button.disabled = false; }
    }); td.append(button); tr.append(td); body.append(tr);
  }
  $('result-count').textContent = filtered.length + ' resultado(s) · exibindo ' + Math.min(shown, filtered.length);
  $('more').hidden = shown >= filtered.length;
}
async function load() {
  if (loading) return; loading = true; $('export').disabled = true; $('reload').disabled = true;
  status.textContent = 'Carregando lista…';
  try {
    session = token(); if (!session) throw new Error('Entre com sua conta de responsável no painel e volte a esta página.');
    const allowed = await api('/rest/v1/interesse_motoristas_admins?select=user_id&limit=1');
    if (!allowed.length) throw new Error('Esta conta não tem autorização para consultar os interessados.');
    const all = [];
    for (let offset=0;;offset+=1000) {
      const batch = await api('/rest/v1/interesse_motoristas?select=id,nome,email,cidade,uf,veiculo,created_at,consentimento,consentimento_versao,email_confirmado&order=created_at.desc,id.desc&limit=1000&offset='+offset);
      all.push(...batch); if (batch.length < 1000) break;
    }
    records = all; shown = 100;
    $('total').textContent = records.length.toLocaleString('pt-BR');
    const regions = new Map(); for (const r of records) { const key=r.cidade+' / '+r.uf; regions.set(key,(regions.get(key)||0)+1); }
    $('cities').textContent = regions.size.toLocaleString('pt-BR');
    $('recent').textContent = records.filter(r=>Date.parse(r.created_at)>=Date.now()-7*86400000).length.toLocaleString('pt-BR');
    $('regions').textContent = [...regions].sort((a,b)=>b[1]-a[1]).slice(0,10).map(([key,count])=>key+': '+count).join(' · ') || 'As cidades aparecerão aqui após os primeiros cadastros.';
    $('admin-content').hidden = false; $('admin-login').hidden = true; render(); status.textContent = 'Atualizado em '+new Date().toLocaleString('pt-BR');
    $('export').disabled = false;
  } catch (error) { records=[]; $('admin-content').hidden=true; status.textContent=error.message; $('admin-login').hidden=false; }
  finally { loading=false; $('reload').disabled=false; }
}
function csvCell(value) { let text=String(value??''); if (/^[\s]*[=+@-]/.test(text)) text="'"+text; return '"'+text.replaceAll('"','""')+'"'; }
$('export').addEventListener('click',()=>{
  const rows=[['Nome','Email','Cidade','UF','Veiculo','Cadastro','Consentimento','Versao do consentimento','Email confirmado'],...records.map(r=>[r.nome,r.email,r.cidade,r.uf,r.veiculo,r.created_at,'Sim',r.consentimento_versao,r.email_confirmado?'Sim':'Não'])];
  const blob=new Blob(['\ufeff'+rows.map(row=>row.map(csvCell).join(';')).join('\r\n')],{type:'text/csv;charset=utf-8'});
  const url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download='motoristas-interessados-'+new Date().toISOString().slice(0,10)+'.csv';a.click();setTimeout(()=>URL.revokeObjectURL(url),1000);
});
$('reload').addEventListener('click',load);$('search').addEventListener('input',()=>{shown=100;render();});$('more').addEventListener('click',()=>{shown+=100;render();});
if (location.hostname !== 'dashboard.entregacondo.com.br') { status.textContent='Abra esta área pelo endereço seguro do painel.'; const link=document.createElement('a');link.href='https://dashboard.entregacondo.com.br/site/interessados.html';link.textContent='Abrir área de interessados';status.append(document.createElement('br'),link); }
else load();
