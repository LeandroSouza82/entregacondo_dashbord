> Atualização posterior: Supabase e dashboard ativados em 23/10/2026, com autorização do usuário. Este documento preserva o relato da preparação; consulte [ATIVACAO_2026_10_23.md](ATIVACAO_2026_10_23.md) para o estado remoto, domínio, APK e pendências atuais.

# Comprovantes privados e preparação da ativação

Estado em **23/10/2026**. Implementação e testes locais concluídos na branch existente `fix/conclusao-falha-metricas-20261019`. Trabalhos anteriores preservados. Sem commit, push, merge, publicação, alteração remota de schema ou nova instalação no celular nesta etapa.

## Correção concluída localmente

O teste geral do banco apontava uma diferença entre instalação nova e migrações: a migração antiga de comprovantes criava `comprovante_publico_download`, com SELECT amplo no bucket. A correção não reproduz essa abertura no schema novo.

- O bucket `entregas-comprovantes` permanece privado. Upload e leitura autenticada da operação continuam sob as políticas existentes.
- A consulta legada por UUID exige autenticação e autorização para a operação. O identificador de uma entrega não autoriza acesso público. Corrigida também a referência antiga a uma coluna `id` inexistente no registro do comprovante.
- O dashboard cria um link somente após assinar as imagens daquele comprovante com as permissões do gestor. Um erro de assinatura impede criar/copiar o link. Não usa `getPublicUrl`, não consulta tabelas como visitante e não gera link com UUID como alternativa.
- Cada link tem um segredo aleatório de 256 bits no fragmento `#/comprovante/...`, com validade de **55 minutos**. O banco guarda apenas SHA-256 do segredo. Criar outro link do mesmo comprovante substitui o anterior. Há botão para revogar o link escolhido.
- A leitura pública devolve somente o comprovante escolhido, após conferir validade, empresa ativa, autorização atual de quem compartilhou, estado do atendimento e correspondência das imagens.
- As imagens recebem URLs assinadas de **1 hora**; a validade do link é menor para acomodar a preparação e as chamadas. Revogar o link corta a consulta do comprovante. Uma URL de imagem já obtida ou uma imagem já baixada não é apagada do aparelho do destinatário; a URL assinada pode continuar acessível até o próprio vencimento. Não se promete revogação instantânea de cópias/imagens previamente recebidas.
- Página pública sem indexação e sem referrer. Revalida a cada 15 segundos e ao voltar à aba; remove dados e zoom em expiração, revogação ou falha de rede. Respostas antigas não substituem outro link aberto. O cache antigo do mesmo navegador deixou de ser fonte do comprovante público.
- Apenas URLs assinadas do Storage do próprio projeto podem ser exibidas. Não carrega imagens de um domínio arbitrário recebido no resultado.
- Nenhuma mensagem real foi enviada; o botão continua copiando o texto para o gestor usar onde desejar.

Arquivos principais: `src/features/receipts/receiptSharing.ts`, `components/public/PublicReceiptView.tsx`, `components/dashboard/ReceiptsView.tsx`, `supabase/modules-sql/10_receipt_sharing.sql` e `functions-sql/obter_comprovante_publico.sql`.

## Migrações preparadas

- `20261022205137_secure_receipt_sharing.sql`: corrige o endpoint legado, remove a política ampla, mantém o bucket privado e cria as funções de compartilhamento/revogação e sua tabela privada com RLS e índices.
- `20261023154302_harden_address_view_and_uuid_helper.sql`: faz a view `saved_addresses` usar as permissões/RLS de quem consulta e fixa o `search_path` do conversor de UUID, preservando endereços, IDs e objetos dependentes. Corresponde a um erro e um aviso concretos dos advisors consultados no projeto remoto.
- A migração local **ainda não aplicada nesse projeto** `20261021210000_public_receipt_rpc.sql` também foi reforçada: não cria a abertura do bucket nem a consulta pública por UUID. Assim, sua aplicação futura não abre acesso amplo temporariamente antes da migração corretiva. A migração corretiva posterior continua reparando ambientes que tenham recebido a versão antiga.
- SQL canônico atualizado e `schema.sql` regenerado pelo script existente. Snapshots anteriores preservados em `C:/Src/NewV10/receipt-sharing-backup`.

## Testes concluídos

- `npm run build`: passou. Permanece o aviso anterior do tamanho dos bundles dos mapas.
- Lint dos componentes/serviço alterados, App e módulo de configuração do cliente: sem avisos.
- `node --experimental-strip-types --test scripts/test_receipt_sharing.mjs scripts/test_route_schedule.mjs`: **19 testes passaram**, 9 novos para compartilhamento. Incluem token, prazo, origem das imagens, assinatura antes de registro, falta de sessão, troca de conta, imagem de outro comprovante e servidor sem a atualização.
- `node scripts/test_receipt_sharing_ui.mjs`: componentes reais e App em Chrome, com APIs/transportes simulados. Passaram cópia, revogação, erros de assinatura/clipboard, link antigo/cache ignorado, leitura sem login só por token, remoção do zoom, expiração, erro de rede, resposta atrasada e bloqueio de imagens externas. Sem exceções no navegador. Prévia: `docs/previews/secure-receipt-mobile.png`.
- Regressões de navegador `test_customer_tracking_ui.mjs` e `test_route_rules_ui.mjs` passaram, preservando acompanhamento, WhatsApp/apartamentos e horários/coletas opcionais.
- `node scripts/test_database.js`: **suíte geral aprovada** em PostgreSQL 17 temporário local, tanto em instalação nova quanto por todas as migrações. Por banco: 29 verificações novas de compartilhamento; 6 verificações da view/helper; 43 das condições opcionais; 99 regressões gerais; 15 de push; além das suítes de acompanhamento e aceite/retirada. Catálogos equivalentes: **52 funções, 23 políticas e 6 constraints da fila**. Passaram 7 cenários com conexões independentes por banco e 3 verificações de preservação/falha segura de migração.
- Os testes locais não simulam a implementação HTTP real do Storage/GoTrue/PostgREST nem validam DNS/certificado de um dashboard publicado. A assinatura HTTP real e o fluxo em outro aparelho precisam ser conferidos depois da ativação autorizada.
- Nenhum código Flutter foi alterado nesta etapa; a última suíte mobile continua sendo a de **161 testes** e o APK **0.1.22 (23)** instalado pelo cabo em 22/10/2026.

## Estado remoto verificado — somente leitura

Projeto Supabase confirmado: `vblwuvhdqgzdjnoscyqo`, PostgreSQL 17, ativo. Foram consultados metadados, migrações e advisors; não foram lidos dados de clientes nem alteradas tabelas, arquivos ou políticas remotas.

- O bucket remoto já está privado e não possui a política ampla local. Portanto não se deve afirmar que as fotos remotas estavam públicas com base apenas naquela divergência local.
- Os novos endpoints de compartilhamento, acompanhamento e capacidades de rota ainda não existem no remoto. Os campos de WhatsApp do cliente e condições opcionais ainda não foram ativados.
- A view remota de endereços está sem `security_invoker`; a correção está na migração incremental preparada, ainda não aplicada.
- O histórico remoto registra apenas parte das migrações que existem localmente, incluindo as operacionais de 19–20/10 e encerrando em `driver_order_inbox`. Há estrutura antiga instalada por outros caminhos. **Não executar `db push --include-all`, schema completo ou migrações iniciais sobre o banco existente.** Reconciliar versões e aplicar somente as alterações incrementais necessárias, conferindo as pré-condições e registrando os resultados.
- Outros avisos anteriores dos advisors foram inventariados, incluindo funções SECURITY DEFINER de operação e configuração de Auth. Funções com tabela privada/RLS sem políticas e acesso apenas por RPC são intencionais; a mera presença de uma RPC SECURITY DEFINER não comprova falha de autorização. Os demais avisos não foram apresentados como resolvidos remotamente nesta etapa.

## Hospedagem e próxima ativação

Na conta Vercel conectada foi encontrado o projeto `entregacondo-site` (`prj_xj3xPXcaYPowhoKwxs2jPQUq9h1w`), equipe `Leandro's projects`. O deploy inspecionado responde com a página de apresentação **“EntregaCondo · Cada entrega aproxima”**, não com o dashboard desta pasta. Os domínios cadastrados incluem `app.entregacondo.com.br` e os aliases do site. A consulta via web ao domínio personalizado não confirmou acesso público; ele não deve ser assumido como endereço válido do acompanhamento nesta etapa.

**Proposta de ativação:** manter o site de apresentação e usar um projeto separado para o dashboard, em vez de sobrescrever a publicação existente.

Após autorização de alteração do banco/publicação:

1. Revalidar projeto Supabase e estado remoto, reconciliar o histórico parcial e verificar previamente as dependências das migrações de endereço, acompanhamento, condições opcionais, compartilhamento e compatibilidade. Aplicar as atualizações incrementais selecionadas; preservar todos os registros e arquivos.
2. Conferir permissões com advisors e testes autenticados/visitante, especialmente leitura dos comprovantes e isolamento dos endereços entre empresas. Não usar chaves secretas no navegador.
3. Disponibilizar o dashboard em projeto de hospedagem separado, usando a configuração pública existente. Registrar a URL HTTPS real retornada e validar que a página pública abre sem login somente com o link válido. Não inventar hostname nem substituir o site de apresentação.
4. Configurar `CUSTOMER_TRACKING_BASE_URL` com essa URL real, gerar o APK e atualizar o celular pelo cabo quando solicitado. Validar coleta/entrega com WhatsApp, GPS recente, encerramento do acompanhamento e comprovantes temporários em outro navegador.
5. Testar no aparelho as condições opcionais, pedidos novos, distância/tempo restante e sincronização offline. A função seguinte da lista continua sendo o resumo do dia.

O pedido anterior do usuário foi: **“Não faça merge ou publicação nesta etapa.”** A autorização para instalar o APK foi executada; esta preparação não a trata como autorização para alterar o Supabase ou publicar o dashboard.

## Fontes consultadas

- [Supabase: buckets privados e URLs assinadas](https://supabase.com/docs/guides/storage/buckets/fundamentals).
- [Supabase: controle de acesso do Storage](https://supabase.com/docs/guides/storage/security/access-control).
- [Supabase: view executada com as permissões do proprietário](https://supabase.com/docs/guides/database/database-linter?lint=0010_security_definer_view).
- [Supabase: search_path mutável](https://supabase.com/docs/guides/database/database-linter?lint=0011_function_search_path_mutable).
