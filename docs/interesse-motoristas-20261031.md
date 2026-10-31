# Lista de interessados e conteúdo público — 31/10/2026

Página pública: https://entregacondo.com.br/site/motoristas.html

Gestão restrita: https://dashboard.entregacondo.com.br/site/interessados.html

Entre primeiro no painel com uma das contas do responsável já existentes (Yahoo ou Gmail pessoal) e depois abra a gestão restrita. Outros gestores e motoristas não têm acesso à lista. Nome, e-mail, cidade e UF são obrigatórios; veículo é opcional. O consentimento fica registrado com data e versão. O e-mail é único e não tem titularidade confirmada. A lista não cria conta operacional nem libera motorista.

A gestão mostra total, cadastros dos últimos 7 dias, cidades/UF, busca, exportação CSV com proteção contra fórmulas e exclusão a pedido do titular. O aviso de lançamento ainda não foi enviado nem agendado. A exportação permite preparar o envio quando o responsável definir o lançamento.

## Publicação e preservação

- Projeto Vercel: `prj_JOyDsbKVBDYaeabMCWPkGgAL6sfC`.
- Publicação: `dpl_FeDLEiKWxiFsS3A9vPztwkJz4ZD6` (produção, READY).
- Base de produção preservada: `dpl_F2iSREz5DF3UZXzYRXVSeru1j51n`.
- Todos os arquivos operacionais `src/` e a configuração Vercel foram reutilizados por SHA, sem alterações. Somente dez arquivos públicos foram criados ou substituídos.
- A versão operacional publicada contém alterações do computador ainda ausentes da branch remota usada como base. **Não publique este checkout inteiro sem antes conciliar essas alterações locais com o Git.** A publicação desta entrega reutilizou a fonte operacional existente na Vercel para evitar regressões.
- A migração está aplicada no projeto Supabase `vblwuvhdqgzdjnoscyqo`, versão `20261031082447`.
- Edge Function `interesse-motoristas`, versão 1, ativa e com JWT habilitado. Somente chave pública está no navegador; a gravação usa credencial de servidor. RLS restringe a consulta e exclusão à lista explícita de responsáveis. A função SQL de gravação é invoker e somente `service_role` pode executá-la.

## Verificação

- Envio real pela API, repetição do mesmo e-mail e remoção do registro técnico: aprovados; lista final com zero cadastros fictícios.
- SQL transacional: unicidade, leitura pelo responsável, isolamento de outras contas e limite de dez tentativas por janela: aprovados; transação revertida.
- Visitante anônimo não consegue ler a tabela nem gravar diretamente.
- Origem não permitida, formulário inválido e honeypot: tratados.
- `node scripts/test_interest_form.mjs`: aprovado; validação, estados, consentimento, repetição de clique, erro e nova tentativa.
- Sintaxe JavaScript, HTML, vínculos de rótulos, identificadores únicos, JSON-LD, sitemap e `git diff --check`: aprovados.
- Publicação Vercel concluída e URLs públicas, módulos JavaScript, sitemap, privacidade e manifesto Android verificados por HTTP.
- As fontes operacionais foram comparadas por hash entre as duas publicações: idênticas.
- Navegador indisponível no ambiente (falha de socket ao iniciar Chromium); revisão visual e interação autenticada real ainda precisam ser conferidas no aparelho.

## Pendências externas

1. `www.entregacondo.com.br` já foi adicionado ao projeto, com redirecionamento 308 para `entregacondo.com.br`. O DNS permanece externo, na Locaweb, sem o registro necessário. Criar um **CNAME**, nome **www**, destino **6ec94bfd83a5db57.vercel-dns-017.com**. Preservar todos os registros de e-mail. A configuração do domínio na Vercel ainda informa `misconfigured: true`; o endereço www não está funcional na verificação.
2. A conta do Google Search Console não está acessível neste ambiente. Verificar a propriedade do domínio, enviar `https://entregacondo.com.br/sitemap.xml` e inspecionar/solicitar indexação da página inicial e da página de motoristas. Nenhuma dessas ações foi declarada como executada. Não há garantia de indexação, posição ou recomendação por IA.
3. Páginas desconhecidas ainda herdam a resposta da SPA (200 com noindex). A mudança de roteamento não foi feita porque a configuração operacional publicada contém rotas mais recentes não conciliadas no Git; deve ser tratada junto à sincronização dessa fonte.
