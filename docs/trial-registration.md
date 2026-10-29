# Cadastro de teste por CPF/CNPJ

O teste só começa depois da confirmação do e-mail e da conclusão do cadastro.
Pessoa física informa CPF, nome e celular brasileiro com DDD. Pessoa jurídica
informa CNPJ, razão social, responsável e celular. Nome do negócio/fantasia é
opcional. O e-mail é obtido do usuário autenticado, sem aceitar identidade,
papel, empresa ou prazo enviados pelo cliente.

`public.registrar_teste_empresa(jsonb)` valida o CPF/CNPJ, normaliza a pontuação
e a caixa e cria empresa, membro administrador, assinatura e cadastro na mesma
transação. CNPJ numérico e alfanumérico são aceitos. Dígitos verificadores
validam a estrutura do documento; não comprovam titularidade ou situação cadastral.
O celular é coletado e validado no formato, sem confirmação por SMS.

`ec_private.cadastros_empresas` armazena os dados cadastrais. O registro único em
`ec_private.documentos_teste` impede novo teste do mesmo documento e mantém as
datas originais. Ao excluir conta e empresa, os vínculos ficam nulos e o registro
de uso do documento permanece. Não há vínculo automático de outra conta a uma
empresa existente: o usuário deve entrar na conta original ou procurar suporte.
As tabelas têm RLS, sem grants nem políticas para clientes. Documento e celular
não são copiados para JWT/user_metadata, localStorage ou empresas públicas.

O bloqueio usa unicidade no banco e lock da conta, inclusive para pedidos
simultâneos. A RPC antiga `iniciar_teste_empresa(text)` permite apenas retorno
idempotente de vínculos gestores existentes, sem criar novos testes. Os triggers
de expiração, cotas e o pagamento permanecem inalterados.

## Compatibilidade e ativação

- Empresas e testes existentes mantêm os prazos e o acesso. Não se exige cadastro
  retroativo, não se reinicia o teste e não se modifica a assinatura anterior.
- Sem documentos históricos, não é possível identificar por CPF/CNPJ quem já
  usou o teste antes desta mudança. O controle documental começa nos novos cadastros.
- Publicar a interface e aplicar `20261029084824_trial_document_registration.sql`
  em uma janela coordenada. A interface nova exige a RPC nova; a migração fecha
  a criação pela interface antiga. Evitar ativar apenas um dos dois componentes.
- Uma reversão da interface não deve restaurar a criação de testes sem documento.
  Preservar o registro de uso. A liberação deve ser corrigida sem apagar a tabela.

## Verificação

- `npm run build`, `npm run lint`, `npm run verify:sql`.
- `npm run test:db` em ambiente que permita PostgreSQL com usuário sem privilégios.
  Inclui `company_trial_tests.sql`, `trial_registration_tests.sql` e concorrência
  entre duas contas usando o mesmo CNPJ em `subscription_regressions.js`.
- `CHROME_PATH=/caminho/do/chrome node scripts/test_company_trial_ui.mjs`:
  duas etapas, ausência de documento no Auth, CPF, CNPJ no celular, documento
  inválido/repetido, gestores existentes, expiração, cobrança e autorização.

Nesta execução, o PostgreSQL nativo não iniciou porque o ambiente só mapeia UID 0.
As suítes SQL foram executadas com PostgreSQL WASM (PGlite 0.3.15 e extensões
uuid-ossp/pgcrypto) em bancos isolados, para instalação nova e cadeia de migrações.
Passaram 21 verificações documentais explícitas, mais os blocos de rejeição e as
suítes existentes de assinatura, isolamento, rotas, comprovantes e notificações.
O catálogo das RPCs públicas de teste/assinatura e as políticas foram comparados
entre as duas instalações. O teste com conexões nativas concorrentes foi
adicionado, mas não foi executado neste ambiente. A interface foi exercitada em
Chromium, com Supabase simulado; o fluxo de e-mail real não foi exercitado.

Não há serviço externo de comprovação de identidade nesta alteração. Documentos
diferentes e válidos ainda podem obter testes independentes.
