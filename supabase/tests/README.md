# Testes locais do backend

Execute na raiz do dashboard:

~~~powershell
npm ci
npm run build:sql
npm run build:migration:security
npm run verify:sql
npm run test:db
npm run build
~~~

test:db inicia PostgreSQL 17 em uma porta livre apenas em 127.0.0.1, cria bancos e credenciais sintéticos numa pasta temporária e encerra/remove o cluster no final. Não lê .env, não recebe URL de banco e não se conecta ao Supabase remoto. Não instala serviço do Windows.

A dependência embedded-postgres é fixada no lockfile. O primeiro npm ci baixa os binários para o sistema suportado.

## O que é executado

- Instalação nova de schema.sql e cadeia de migrações desde o início.
- Regressões de RPCs, isolamento de empresas, revisão obrigatória, preservação de evidências, tokens, prazo e autorização operacional.
- Políticas de INSERT/UPDATE/DELETE de storage.objects sob authenticated.
- Comparação dos catálogos vivos das RPCs canônicas, privilégios, políticas efetivas e constraints da fila. Colunas legadas adicionais são preservadas; não se afirma identidade integral de todos os objetos históricos.
- Concorrência com conexões e transações independentes: anexação/descarte nas duas ordens, SKIP LOCKED, confirmação atrasada após recuperação e aprovação concorrente com remoção.
- Atualização de veículo/foto legados, repetição da migração, duplicidades e órfãos exigindo interrupção sem exclusão.

## Limites

local_bootstrap.sql fornece contratos mínimos de auth e storage. As fixtures em storage.objects são apenas metadados SQL.

Estes testes não validam OAuth/Google, JWTs reais, PostgREST, upload/download/remoção de binários via HTTP, webhooks, Flutter ou integração de ponta a ponta. Antes de produção, executar esses fluxos numa instância Supabase isolada completa.

Não executar fixtures em produção. A suíte SQL usa ROLLBACK, mas o mecanismo recomendado é npm run test:db, que controla os bancos temporários.