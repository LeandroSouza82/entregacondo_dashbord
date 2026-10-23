# Identidade da empresa — 23/10/2026

## Comportamento
- O cadastro já enviava empresa_nome nos metadados da conta. O campo agora se chama Nome da sua empresa, orienta sobre o uso público do nome e valida de 2 a 120 caracteres.
- O login de contas existentes continua solicitando e-mail e senha. Não é necessário redigitar o nome a cada acesso.
- O painel mostra o nome da empresa selecionada, consultado em empresas.nome. Após salvar em Configurações, o cabeçalho acompanha a alteração confirmada. Uma prévia não salva ou atualização de outra empresa não renomeia o painel.
- A página pública do comprovante destaca a empresa responsável. O EntregaCondo permanece no rodapé.
- O menu da rota no aplicativo destaca a empresa; Tecnologia EntregaCondo aparece no rodapé.
- Os novos resumos de conclusão registram o nome empresarial junto ao comprovante. O cache de apresentação fica separado por usuário e empresa; não concede acesso. Comprovantes antigos continuam compatíveis e não são reescritos.
- O aviso de chegada e a página de acompanhamento já recebem empresas.nome do servidor. Nenhuma empresa real foi renomeada nesta tarefa. O cadastro atual ainda tem o nome EntregaCondo; o gestor pode substituí-lo em Configurações.

## Verificação
- flutter analyze --no-pub: sem problemas.
- flutter test --no-pub: 180 testes aprovados, incluindo isolamento do nome por usuário/empresa e preservação do nome original nos resumos já registrados.
- npm run build e lint dos arquivos alterados: aprovados.
- scripts/test_company_identity_ui.mjs: cadastro, metadados do nome, login sem campo empresarial, prévia, persistência confirmada via RPC, atualização do painel, falhas e eventos de outra empresa.
- scripts/test_receipt_sharing_ui.mjs e scripts/test_customer_tracking_ui.mjs aprovados. A prévia gerada docs/previews/secure-receipt-mobile.png foi atualizada para refletir o novo cabeçalho.
- Publicação READY no projeto existente, ambos os domínios. Deployment: dpl_CDXbRzCmYs932ccT9LWXTuKJnEHu. HTTPS, arquivos publicados, cadastro e páginas públicas verificados no Chrome real; nenhuma conta ou mensagem real criada pelo teste.
- APK 0.1.29 (30) instalado por USB e menu conferido no celular. SHA256 F2A31DD342A10F115ED5453AAF256423CCB5CFC9BB291EF4DF43CE6F28686D05.

## Escopo e pendências
Não foram alterados schema, políticas de autorização, preços ou cadastro de empresas reais. As mudanças de código permanecem na branch local codex/fix-aviso-whatsapp, sem commit, merge ou push.
O teste comercial de 30 dias, limites de assinatura e pagamento automático continuam pendentes. Antes de abrir cadastro comercial automático, revisar o provisionamento legado de empresas e vínculos: ele contém fallback para a primeira empresa visível quando a inserção falha, e as políticas remotas consultadas incluem permissões amplas. Essa revisão deve ser uma etapa própria, com criação transacional e autorização por empresa; os testes desta tarefa verificam identidade de apresentação e não certificam isolamento de segurança do onboarding.
