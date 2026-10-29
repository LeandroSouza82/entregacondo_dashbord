# Assinatura antecipada e acesso por e-mail — 27/10/2026

## Comportamento

- O gestor pode contratar durante o teste de 30 dias. A reserva usa a data original do servidor para `auto_recurring.start_date`; o handler confere se o provedor preservou essa data antes de disponibilizar o checkout. O cadastro do meio de pagamento não antecipa a mensalidade.
- Chamadas repetidas reutilizam a contratação. Uma assinatura autorizada não oferece novo checkout. Cancelamento confirmado permite uma nova tentativa, preservando o histórico dos pagamentos antigos. Suspensão e cobertura paga impedem checkout indevido.
- A confirmação da recorrência é separada da confirmação de pagamento: webhook autenticado e consulta ao provedor conferem empresa, vendedor, plano e ambiente. Autorização de cartão/assinatura não cria cobertura paga. O retorno do navegador também não cria cobertura.
- A tela mostra teste, prazo em Brasília, contratação pendente/confirmada, assinatura ativa, suspensão, cancelamento e bloqueio após vencimento. A oferta pública e o cadastro explicam a assinatura antecipada e a preservação dos dias grátis.
- O cadastro trata a resposta de usuário já existente (`identities: []`) com mensagem explícita e caminhos de entrada. Não troca a senha de uma conta existente nem promete um e-mail de confirmação que não foi enviado.
- Login oferece Google, reenvio de confirmação e definição/recuperação de senha, com espera de 60 segundos entre solicitações de e-mail. A ativação volta ao login, sem criar a empresa antes do primeiro acesso confirmado.
- Os templates usam `{{ .ConfirmationURL }}`, a variável nativa do Supabase. Os retornos de cadastro e recuperação usam os parâmetros `auth_action=signup` e `auth_action=recovery`, tratados antes da tela operacional. A recuperação exige salvar a nova senha e encerra a sessão local antes de voltar ao login.

## Publicação e configuração

- Produção: https://entregacondo.com.br/.
- Dashboard publicado: `dpl_7qXXJs32V6mhhL2DTPQ5vU9xxDSH`, READY, apenas pacote estático testado.
- Supabase: `vblwuvhdqgzdjnoscyqo`, migração incremental `allow_early_subscription`. Não foi executado reset, schema completo ou reenvio de migrações anteriores. Guardas de autorização mantidas; as novas funções de sincronização só podem ser executadas pelo servidor.
- `assinatura-checkout`: versão 3 ACTIVE. `assinatura-webhook`: versão 2 ACTIVE. O diagnóstico seguro de falhas já existente foi preservado.
- Cobrança permanece no ambiente de teste existente. Nenhuma compra, pagamento, troca de credenciais financeiras ou ativação de cobrança real foi realizada nesta correção.
- Site URL de Auth atualizado de localhost para `https://entregacondo.com.br`. Foram adicionados retornos exatos dos domínios publicados, preservando os retornos locais e mobile; sem curingas.
- Resend reaproveitado. Domínio `entregacondo.com.br` verificado, região São Paulo. DNS: um TXT DKIM e os CNAMEs `rsend` e `send`, sem substituir registros do site ou ativar recebimento de e-mail. Chave própria com Sending access restrita ao domínio, salva apenas no SMTP do Supabase. Nenhuma credencial está neste repositório.
- Remetente: `EntregaCondo Gestão <acesso@entregacondo.com.br>`, SMTP `smtp.resend.com`, TLS na porta 465. Templates de confirmação e recuperação em `supabase/templates/`. Marca vetorial em `public/email-brand.svg` e PNG derivado para compatibilidade com clientes de e-mail.

## Verificações

- PostgreSQL 17 temporário: instalação nova e atualização passaram. Por caminho: 38 verificações de cadastro/isolamento/teste, 12 de compatibilidade, 29 de comprovantes, 43 de regras, 99 regressões gerais, 15 de push e demais suítes existentes. Catálogos equivalentes: 60 funções, 24 políticas e 6 constraints. Concorrência: sete casos operacionais e três comerciais por banco; três cenários de preservação de migrações.
- Testes Node de cobrança existentes, novos cenários de antecipação e 11 testes de sigilo/diagnóstico passaram, sem chamadas externas de pagamento.
- Navegador com APIs simuladas: contratação antes do vencimento, retorno seguro, estados pendente/confirmado/pago e modo de validação; cadastro repetido, reenvio, cooldown, ativação, expiração de link e recuperação. Inclui callback nativo do Supabase.
- TypeScript e lint dos componentes alterados passaram. Build de produção passou, mantendo o aviso anterior de bundles dos mapas acima de 500 kB.
- Domínio publicado respondeu HTTP 200, com o bundle da correção; tela de login em produção conferida.
- SMTP real: recuperação solicitada pelo formulário publicado e entrega ao Gmail confirmada no Resend. O botão entregue aponta ao endpoint nativo de verificação do projeto e retorna para `https://entregacondo.com.br/?auth_action=recovery`. O link não foi consumido pelo agente; definir a senha é uma ação do titular.
- Ajuste após validação em celular: o link secundário mantém o destino nativo, mas mostra um rótulo curto em vez de expor o endereço completo com o token. Aplicado à ativação e à recuperação.

As cópias originais em C:/Src continham alterações locais de revisão de veículos. A implementação foi feita em cópia isolada e essas alterações foram preservadas. Os testes não equivalem a uma compra real nem dispensam o titular de abrir o e-mail e definir sua própria senha.
