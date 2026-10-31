import { apiUrl, publicKey } from './interesse-config.js';
const form = document.querySelector('#interest-form');
const status = document.querySelector('#form-status');
const states = 'AC AL AP AM BA CE DF ES GO MA MT MS MG PA PB PR PE PI RJ RN RS RO RR SC SP SE TO'.split(' ');
for (const uf of states) form.elements.uf.add(new Option(uf, uf));
let busy = false;
form.addEventListener('submit', async event => {
  event.preventDefault(); if (busy || !form.reportValidity()) return;
  busy = true; const button = form.querySelector('button[type=submit]'); button.disabled = true;
  status.dataset.error = 'false'; status.textContent = 'Salvando seu interesse…';
  const data = Object.fromEntries(new FormData(form)); data.consentimento = form.elements.consentimento.checked;
  try {
    const response = await fetch(apiUrl + '/functions/v1/interesse-motoristas', {
      method: 'POST', headers: { 'Content-Type': 'application/json', apikey: publicKey, Authorization: 'Bearer ' + publicKey },
      body: JSON.stringify(data), signal: AbortSignal.timeout(20000),
    });
    const result = await response.json();
    if (!response.ok) throw new Error(result.message || 'Não foi possível salvar agora. Tente novamente em instantes.');
    status.textContent = result.message; form.reset(); button.textContent = 'Interesse registrado ✓';
    // Successful submissions stay disabled; network errors allow a safe retry.
  } catch (error) {
    status.dataset.error = 'true'; status.textContent = error.name === 'TimeoutError' || error instanceof TypeError
      ? 'Não conseguimos confirmar o envio. Confira sua conexão e tente novamente; seu e-mail não será duplicado.' : error.message;
    button.disabled = false; busy = false;
  }
});
