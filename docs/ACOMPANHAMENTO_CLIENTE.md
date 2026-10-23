> Atualização posterior: Supabase e dashboard ativados em 23/10/2026, com autorização do usuário. Este documento preserva o relato da preparação; consulte [ATIVACAO_2026_10_23.md](ATIVACAO_2026_10_23.md) para o estado remoto, domínio, APK e pendências atuais.

# EntregaCondo — aviso ao cliente e acompanhamento

Estado em 22/10/2026. Implementação local, sem commit, push, merge, migração remota, instalação ou publicação nesta etapa.
Branch dos dois projetos: `fix/conclusao-falha-metricas-20261019`. As muitas alterações locais anteriores foram preservadas. Não foram encontrados arquivos AGENTS.md nos diretórios de projeto examinados.

## Comportamento implementado

- Dashboard: WhatsApp do cliente com DDD substitui o campo de apartamento. Número opcional, validado e normalizado para formato internacional. Reutiliza `entregas.destinatario_telefone`; `clientes_enderecos.whatsapp_cliente` permite reutilizar o contato de um endereço salvo.
- Nenhum apartamento antigo é convertido em telefone. As colunas antigas ficam intactas. Ao selecionar um cadastro antigo, o complemento é incluído nas Observações. Rascunhos antigos conservam a unidade original.
- Configurações: nome compartilhado da empresa em `empresas.nome`, alterado somente por gestor/admin autorizado daquela empresa.
- App: botão “Avisar que estou a caminho” quando há contato e antes de Cheguei. Servidor valida que é o próximo atendimento liberado da rota ativa, pertencente ao motorista autenticado.
- Saudação SEM nome do cliente e SEM acesso à agenda: “Olá! Sou [motorista], da [empresa]. Estou a caminho para realizar sua [entrega/coleta]. Acompanhe minha chegada: [link]”. Para outros serviços: “realizar seu atendimento”. Nome do motorista vem do perfil; nome da empresa vem do banco.
- Abre `wa.me` com a mensagem para conferência e envio pelo motorista. Não envia automaticamente nem registra abertura como mensagem enviada.
- Link aleatório de 256 bits, guardado no app por usuário/empresa/atendimento. No banco fica apenas seu SHA-256. O token fica no fragmento `#/acompanhar/...`, evitando sua inclusão no caminho enviado ao servidor web. Página sem indexação, sem referrer, sem consulta pública a tabelas.
- Página pública: empresa responsável, apenas destino e posição daquele atendimento, previsão pelas ruas quando disponível, horário da última atualização e marca discreta EntregaCondo. Consulta limitada por token a cada 15 s. Não retorna nome/telefone de cliente, lista de paradas, comprovantes ou identificadores operacionais.
- Reaproveita a assinatura de GPS da rota; atualizações do acompanhamento são isoladas do mapa de gestão. GPS velho não é apresentado como recente; ETA deixa de aparecer quando os dados ficam antigos. Falha de ETA não inventa valores. Não depende de envio automático de WhatsApp.
- Token vale até 8 h e é revalidado em cada leitura/publicação. Conclusão, falha, cancelamento, rota encerrada, mudança de motorista/rota, perda de vínculo e alteração de telefone/endereço impedem a exposição anterior. Conclusão é refletida na página na próxima consulta; erro de conexão também remove os dados exibidos.
- Offline: não cria aviso de acompanhamento sem confirmação online. Comprovantes e fila offline anteriores continuam separados e preservados.

## Organização

SQL: `supabase/modules-sql/09_customer_tracking.sql`, RPC de endereço existente e migração `supabase/migrations/20261022153822_customer_arrival_tracking.sql`. Schema gerado pelo script existente.
Dashboard: `CompanySettings.tsx`, `components/public/CustomerTrackingView.tsx`, `ArrivalTrackingMap.tsx`, `arrivalTracking.ts`, serviço `customerContact.ts`; alterações pontuais no formulário, tipos e entrada pública em App.tsx.
Mobile: `customer_arrival.dart`, `customer_position_publisher.dart`; integrações pontuais na tela de detalhes e no tracker existente. Fluxo Detalhes → Cheguei → cronômetro → Finalizar permanece.

## Validação realizada

- `flutter analyze --no-pub`: sem problemas.
- `flutter test --no-pub`: 105 testes passaram, incluindo clique no botão, autorização → início do acompanhamento → abertura simulada de WhatsApp, saudação sem nome, coleta/entrega/outros, falha ao abrir, renovação de token, GPS medido, ETA e indisponibilidade viária.
- APK debug compilado localmente; não instalado. Build usa o arquivo local de configuração existente sem expor seu conteúdo.
- `npm run build`: passou. Há aviso de tamanho de bundles, já presentes no dashboard com mapas.
- Lint dos novos componentes/serviços: sem avisos após a revisão React. O lint geral mantém avisos anteriores em outros componentes.
- `node scripts/test_database.js --tracking-only`: passou em instalação nova e atualização por todas as migrações. Inclui despacho com telefone, preservação de apartamentos, reutilização/remoção de contato, gestor da empresa, motorista do perfil, retirada, próxima parada, tokens, GPS fora de ordem/antigo, isolamento entre empresas e encerramento. Também executa a leitura como papel anon real.
- `node scripts/test_customer_tracking_ui.mjs`: passou em Chrome com componentes reais e RPC externo simulado. Verifica página sem login, ETA, transição para encerrado, horário de GPS antigo, link inválido, falha de conexão e campo real do dashboard. Serviços externos, incluindo tiles do mapa, não foram validados em produção. Prévia local em `docs/previews/customer-tracking-stale.png` mostra o estado sem configuração de mapa.
- A suíte completa `npm run test:db` passou pelas regressões funcionais em ambos os bancos, mas falhou na comparação de políticas: a migração anterior `20261021210000_public_receipt_rpc.sql` cria `comprovante_publico_download` em storage.objects com leitura pública do bucket de comprovantes, ausente no schema de instalação nova. Essa divergência e o alcance da política precisam de revisão separada antes de qualquer implantação conjunta. A política não foi alterada nesta tarefa. Não se deve reportar a suíte geral como totalmente aprovada.
- As credenciais, o banco de produção e os dados reais de clientes não foram modificados nesta etapa. Não houve envio real de mensagem.

## Antes de ativar em ambiente real

1. Revisar a migração e a divergência preexistente dos comprovantes públicos. Testar advisors e concessões no ambiente de homologação.
2. Com autorização de publicação, aplicar a migração no projeto correto e disponibilizar a versão web com `VITE_SUPABASE_URL`, chave pública e `VITE_MAPBOX_TOKEN` configurados (nunca usar service_role no navegador).
3. Configurar o build mobile com `CUSTOMER_TRACKING_BASE_URL` apontando para a URL HTTPS publicada do dashboard. Sem esse endereço, o botão informa indisponibilidade; não emite links fictícios.
4. Conferir nome da empresa em Configurações e WhatsApp no pedido.
5. Validar em celular físico: permissão GPS, app em primeiro plano/WhatsApp aberto/tela bloqueada, atualização no navegador do destinatário, estimativa viária, retorno ao app e encerramento após confirmação no servidor. A política de bateria do Android pode interromper atualizações; a página deve continuar mostrando a última medição, sem simular movimento.

## Outras pendências — ordem preservada

| Ordem | Item | Estado encontrado / próximo trabalho |
|---|---|---|
| 1 | Distância e tempo restantes | Corrigido no aplicativo em etapa posterior de 22/10/2026: cálculo desde GPS recente, pendentes e retorno configurado; cabeçalho e mapa compartilham a estimativa. Relatório completo em C:/Src/EntregaCondo/docs/DISTANCIA_TEMPO_RESTANTES.md. Validação física ainda pendente. |
| 2 | Novos pedidos sem trocar de aba | Corrigido localmente em 22/10/2026: controlador persistente, aviso também no Mapa, atualização na retomada/push e proteção contra leituras antigas após ações. Suíte mobile: 125 testes. Relatório em C:/Src/EntregaCondo/docs/PEDIDOS_ATUALIZACAO_AUTOMATICA.md. FCM e celular físico pendentes. |
| 3 | Offline e sincronização | Corrigido e ampliado localmente em 22/10/2026: fila durável sem substituição de comprovantes, falhas com motivo, revisão de recusas, cache com horário/validade e isolamento por conta. Suíte mobile: 139 testes. Relatório em C:/Src/EntregaCondo/docs/OFFLINE_SINCRONIZACAO.md. Validação física ainda pendente. |
| 4 | Cheguei e tempo | Já implementados; preservados e cobertos por regressões. |
| 5 | Conclusão com foto e recebedor | Já existe foto opcional, seleção/nome e assinatura; preservar e revisar rapidez com usuário. Ajustado somente o scroll de um teste que clicava sob o rodapé. |
| 6 | Falha com motivos prontos | Implementado localmente em 22/10/2026: seletor com busca, 28 opções para entrega/coleta e 27 para outros serviços, detalhes opcionais e Outro obrigatório. Sucesso também usa lista de recebedores. Suíte mobile: 147 testes. Relatório em C:/Src/EntregaCondo/docs/MOTIVOS_E_SELETORES.md. APK anterior instalado pelo cabo; usuário confirmou teste físico dos motivos de falha. |
| 7 | Ligação e WhatsApp | Controles condicionais ao contato já existem; Mensagem agora abre WhatsApp. Validar aparelho real. |
| 8 | Próxima parada em destaque | Accordion e destaque já existem; preservados. |
| 9 | Horários e dependências | Implementado localmente em 22/10/2026: duas opções facultativas, planejamento com deslocamento/atendimento/espera, vínculo coleta→entrega, bloqueio até confirmação no servidor e proteção do atendimento em andamento. 161 testes mobile; relatório HORARIOS_E_COLETAS_OPCIONAIS.md. Migração, publicação e teste físico desta função pendentes. |
| 10 | Resumo do dia | Há Histórico com filtros por dia/semana/mês; conferir a composição do resumo desejado antes de duplicar telas. |

## Atualização de 23/10/2026 — permissões e preparação

A divergência local de políticas dos comprovantes foi corrigida e a suíte geral do banco passou por completo em instalação nova e por migrações. Preparados compartilhamento restrito por token e correção incremental da view de endereços. Supabase remoto foi apenas consultado; alterações e publicação continuam pendentes. A Vercel conectada contém o site de apresentação; a proposta é hospedar o dashboard em projeto separado. Consulte COMPROVANTES_E_PREPARACAO_DA_ATIVACAO.md para testes, limites e sequência de ativação.
