# Aviso ao cliente e apresentação pública — 23/10/2026

## Diagnóstico
O erro no atendimento Vogue (EC-204965) ocorria porque ele era a segunda parada e a anterior ainda estava pendente. O servidor retornava 42501: avise somente o próximo atendimento liberado da rota ativa. O aplicativo oferecia o botão em paradas futuras e escondia o motivo com uma mensagem genérica.

## Ajuste
- A interface acompanha a elegibilidade da próxima parada, dependências e sincronização. Telefone ausente na primeira parada não libera a segunda.
- O botão explica quando o aviso está indisponível. As validações do servidor continuam obrigatórias.
- Erros conhecidos têm explicações específicas; detalhes internos não são exibidos.
- Página pública de apresentação em https://entregacondo.com.br/#/conheca e rodapé discreto na página de acompanhamento. O link de divulgação não inclui o token do atendimento.
- Sem alteração de políticas, tabelas ou regras de autorização nesta correção.

## Verificação
- Flutter analyze sem problemas; suíte completa: 180 testes aprovados.
- Build web, lint dos componentes alterados e testes de interface no Chrome aprovados.
- Produção verificada nos dois domínios; arquivos publicados conferidos contra o build local.
- APK 0.1.27 (28) instalado por USB. SHA256: 3C12214095843EF9112F5C49F2CC82F52AEDD1B0E5BB73844727C894B6A3B2E9.
- Teste real no celular: Vogue passou a aparecer como primeira parada; o botão abriu o WhatsApp com saudação sem nome do cliente, motorista, empresa, tipo entrega e link exclusivo. Nenhuma mensagem foi enviada pelo agente.
- O link real foi aberto no Chrome sem autenticação: acompanhamento ativo, mapa com motorista e destino, previsão de chegada, última atualização e divulgação discreta; sem corte horizontal.
- Não foi concluído um atendimento real para testar o encerramento do link; esse cenário permanece coberto pelos testes anteriores de acompanhamento.

## Preservação e Git
Branch local nos dois repositórios: codex/fix-aviso-whatsapp. Nenhum commit, merge ou push nesta correção. A publicação web foi feita no projeto existente, com arquivos públicos do build.
Conferência de hashes: 305 arquivos anteriores do aplicativo e 240 do dashboard, fora dos arquivos intencionalmente alterados, permaneceram idênticos. Trabalho anterior do dashboard continua local e preservado.

## Pendência de uso
O motorista deve revisar e enviar a mensagem no WhatsApp. O teste não enviou uma mensagem real ao cliente.
