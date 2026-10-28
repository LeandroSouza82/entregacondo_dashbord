// Preserve links sent before the public site and dashboard received separate addresses.
// Tokens stay in the URL fragment; they are never sent to analytics or another service.
(() => {
  const hash = window.location.hash;
  const query = new URLSearchParams(window.location.search);
  const legacyRoute = /^#\/?(?:login|cadastro|assinatura|ativar|definir-senha|acompanhar|comprovante)(?:[/?]|$)/.test(hash);
  const authReturn = query.has('auth_action') || query.has('code') || /(?:^#|&)access_token=|(?:^#|&)error=/.test(hash);
  if (legacyRoute || authReturn) {
    window.location.replace('https://dashboard.entregacondo.com.br/' + window.location.search + hash);
  } else if (/^#\/?conheca\/?$/.test(hash)) {
    window.history.replaceState({}, '', '/');
  }
})();
