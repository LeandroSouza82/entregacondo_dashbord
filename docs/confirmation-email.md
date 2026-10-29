# E-mail de confirmação EntregaCondo

Assunto: **Confirme seu e-mail | EntregaCondo**.
Fonte: `supabase/templates/confirmation.html`.

O modelo usa o logo atual, azul escuro e laranja da marca, botão de confirmação,
link alternativo e explicação sobre o início do teste. Utiliza tabelas e estilos
inline para clientes de e-mail. O texto continua identificando a marca mesmo
quando imagens externas estão desabilitadas. Não contém scripts, formulários,
fontes remotas, CPF/CNPJ, variáveis de perfil ou prazo de expiração fixo.

O botão e o link alternativo usam `{{ .ConfirmationURL }}` gerado pelo Supabase.
Não substitua pelo domínio do painel nem por um link da prévia. É confirmação
por link, compatível com o fluxo atual; não é uma tela para digitar OTP.

## Configuração hospedada

No projeto EntregaCondo (`vblwuvhdqgzdjnoscyqo`), acessar **Authentication > Email
Templates > Confirm sign up**, definir o assunto e o conteúdo do arquivo e salvar.
Validar o estado de confirmação de e-mail e as URLs de redirecionamento antes
de enviar um cadastro de teste. `config.toml` apenas prepara o ambiente local;
commits e migrações SQL não publicam modelos no Supabase hospedado.

O nome visível **EntregaCondo** e um endereço de remetente próprio dependem do
SMTP configurado. Não substituir credenciais ou habilitar SMTP sem provedor e
remetente verificados. As credenciais não pertencem ao repositório.

Imagem atual verificada em 29/10/2026:
https://entregacondo-dashboard-leandros-projects-8cb07f1f.vercel.app/app-logo.png
Se o domínio do painel mudar, conservar a URL antiga ou atualizar o modelo
antes de removê-la. Não usar uma URL de prévia protegida no e-mail.

## Verificação

- Renderizar com uma URL fictícia no lugar de `{{ .ConfirmationURL }}`.
- Conferir 360 px e desktop, botão, link longo e imagens bloqueadas.
- Conferir com um e-mail real após salvar o modelo hospedado e configurar o
  remetente. Renderização local não prova entrega, SMTP ou autenticação real.

Referências oficiais:
https://supabase.com/docs/guides/auth/auth-email-templates
https://supabase.com/docs/guides/auth/auth-smtp
