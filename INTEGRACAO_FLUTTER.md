# Contrato Canônico de Integração Mobile (Flutter) x Backend EntregaCondo
**Projeto Supabase:** `vblwuvhdqgzdjnoscyqo`  
**URL:** `https://vblwuvhdqgzdjnoscyqo.supabase.co`  
**Versão do Contrato:** 7.0.0 — tentativas identificadas e autorização operacional.
**Data:** 18/10/2026  
**Documento de Origem Mobile:** `C:\Src\EntregaCondo\docs\VEICULO_MOBILE.md`  
**Público-alvo:** Desenvolvedor / Agente IA responsável pelo aplicativo Flutter (`C:\Src\EntregaCondo\apps\mobile`).

---

## 1. Princípios de Segurança e os 5 Níveis de Estado

O aplicativo móvel **NUNCA DEVE DEDUZIR ACESSO OPERACIONAL** a partir de validações locais ou preferências offline do aparelho. A validação do Flutter organiza a experiência do condutor, mas a autorização real reside exclusivamente no PostgreSQL.

Existem 5 níveis de estado sequenciais e estritamente auditados:

```
[1. Conta Autenticada] 
       ↓ 
[2. Vínculo Solicitado (Código de Convite)] 
       ↓ 
[3. Veículo Declarado & Reserva Explícita + 4 Fotos + CRLV Enviados]
       ↓ 
[4. Análise Humana da Gestão (Conferência Documental com Revisão e Isolamento de Empresa)]
       ↓ 
[5. Acesso Operacional Totalmente Liberado às Rotas]
```

### Os 5 Níveis Explicados:
1. **Conta Autenticada:** O condutor realizou login via Supabase Auth (`auth.uid()`). Não possui acesso a nenhuma rota, condomínio ou cliente.
2. **Vínculo Solicitado:** O condutor enviou o código de convite da empresa (ex: `EC-FLN-01`) via `solicitar_acesso_empresa`. Solicitação registrada com status `pendente`.
3. **Veículo Declarado e Evidências Vinculadas (Coordenação por Reserva Explícita):**
   - O condutor salva os dados cadastrais via `cadastrar_meu_veiculo` (regras alinhadas ao `VEICULO_MOBILE.md`). O veículo fica associado estritamente à empresa do condutor.
   - **Protocolo de Reserva de Evidência:** Antes de qualquer upload no Storage, o cliente chama `reservar_upload_evidencia`. O backend gera um caminho único e insere a linha na fila com status `reservado`.
   - O condutor faz o upload do arquivo binário para o bucket privado `veiculos-documentos`.
   - O condutor vincula o arquivo ao veículo via `anexar_documento_veiculo`, que faz lock da reserva e transiciona atomicamente para `vinculado`.
   - São necessárias as **4 fotos obrigatórias** (`frente`, `lado_direito`, `lado_esquerdo`, `traseira`) e o **CRLV**.
4. **Análise Humana pela Gestão com Controle de Revisão e Isolamento Estrito de Empresa:**
   - O gestor analisa no dashboard os dados cadastrais, as 4 fotos identificadas por ângulo e o documento CRLV.
   - **Isolamento de Empresa:** A busca do veículo exige estritamente `empresa_id = solicitacao.empresa_id`. Se o condutor tiver veículo cadastrado em outra empresa, a aprovação é rejeitada com código `VEICULO_OUTRA_EMPRESA`, impedindo aprovação indevida ou vazamento de dados de veículos entre empresas.
   - O backend **rejeita aprovação** se faltar qualquer um dos 4 ângulos ou o CRLV.
   - A aprovação do veículo exige **obrigatoriamente** o envio do número da revisão visualizada pelo gestor (`p_revisao_esperada_veiculo`). Se omitida (`NULL`) ou desatualizada, a transação recusa a aprovação **sem qualquer mutação parcial**.
   - A aprovação do vínculo pode ocorrer separadamente da aprovação técnica do veículo. Se o gestor aprovar apenas o vínculo (`p_aprovar_veiculo = FALSE`), o veículo permanece em status `pendente`.
5. **Acesso Operacional Liberado:** Condutor aprovado e veículo aprovado na mesma empresa. Apenas neste estágio o motorista recebe rotas atribuídas.

---

## 2. Nomenclatura Canônica de Documentos e Ângulos

Para eliminar divergências entre cliente e servidor, a tabela e as RPCs utilizam os seguintes identificadores canônicos:

### 2.1 Tipos de Documento (`tipo_documento`):
- `'foto_veiculo'`: Foto do veículo físico (exige ângulo obrigatório; aceita apenas `image/jpeg` ou `image/png`; máx 10 MB).
- `'crlv'`: Certificado de Registro e Licenciamento de Veículo (obrigatório para aprovação; aceita `image/jpeg`, `image/png` ou `application/pdf`; máx 10 MB).
- `'complementar'`: Documentos adicionais (CNH, apólice, etc.; até 5 documentos; aceita JPG, PNG ou PDF; máx 10 MB).

### 2.2 Ângulos da Foto do Veículo (`angulo_foto`):
Exclusivo para `tipo_documento = 'foto_veiculo'`. O aplicativo deve enviar exatamente um dos 4 valores canônicos:
- `'frente'`
- `'lado_direito'`
- `'lado_esquerdo'`
- `'traseira'`

---

## 3. Catálogo de RPCs do Aplicativo Móvel

### 3.1 Consulta de Acesso: `obter_meu_status_acesso()`
Chamada obrigatória ao abrir o aplicativo ou ao retornar do segundo plano (`AppLifecycleState.resumed`).

```dart
final status = Map<String, dynamic>.from(
  await Supabase.instance.client.rpc('obter_meu_status_acesso') as Map,
);
// Conferir operacional_liberado; vínculo aprovado não basta para operar.
```

---

### 3.2 Solicitar Vínculo com Empresa: `solicitar_acesso_empresa(p_codigo_convite)`

```dart
Future<Map<String, dynamic>> solicitarAcesso(String codigoConvite) async {
  final response = await supabase.rpc('solicitar_acesso_empresa', params: {
    'p_codigo_convite': codigoConvite.trim().toUpperCase(),
  });
  return Map<String, dynamic>.from(response);
}
```

---

### 3.3 Cadastro e Edição de Veículo: `cadastrar_meu_veiculo(p_dados)`

Regras obrigatórias de `VEICULO_MOBILE.md`:
- **Carro:** Apenas `tipo_veiculo: 'carro'`, `marca`, `modelo` e `placa`. Não enviar peso, volume, compartimento ou dimensões.
- **Moto com Baú:** `tipo_veiculo: 'moto'`, `compartimento: 'bau'`, `volume_litros: > 0` e `capacidade_kg: > 0`. Opções sugeridas no app: 20, 30, 50, 80, 100 e 120 litros (aceita digitação livre). Não enviar dimensões.
- **Moto com Mochila ou Bag:** `tipo_veiculo: 'moto'`, `compartimento: 'mochila' | 'bag'`, `tamanho_compartimento: 'pequeno' | 'medio' | 'grande'` e `capacidade_kg: > 0`. Não enviar litros ou dimensões.
- **Isolamento de Empresa:** O veículo é salvo associado à `empresa_id` ativa do condutor.
- **Reversão de Status:** Se um veículo já aprovado for editado, o status de análise no servidor **retorna imediatamente para `'pendente'`**, exigindo nova validação da gestão.

---

### 3.4 Ciclo Coordenado de Upload: Reserva, Envio, Vinculação e Descarte

O ciclo de vida de arquivos segue o protocolo estrito de reserva e transição de estados:

```
[Cliente]  -- 1. reservar_upload_evidencia() -->  [DB: cria fila status 'reservado']
[Cliente]  -- 2. Storage.upload(caminho_unico) --> [Storage: RLS valida status = 'reservado']
[Cliente]  -- 3. anexar_documento_veiculo() -----> [DB: lock FOR UPDATE, transição para 'vinculado']
                                                   [Se substituído: transiciona antigo para 'pendente']
```

#### Exemplo em Dart:

~~~dart
// Requer sessão autenticada e supabase_flutter.
// A conclusão local do formulário não equivale a envio ou aprovação.
Future<Map<String, dynamic>> limparEvidencia(String filaId) async {
  final client = Supabase.instance.client;
  final itens = await client.rpc('reivindicar_itens_limpeza_storage', params: {
    'p_limite': 1,
    'p_fila_id': filaId,
  }) as List;
  if (itens.isEmpty) {
    return {'removido': false, 'confirmado': false, 'estado': 'aguardando_fila'};
  }
  final item = Map<String, dynamic>.from(itens.single as Map);
  final prazo = DateTime.parse(item['lease_expires_at'] as String);
  if (!prazo.isAfter(DateTime.now().toUtc())) {
    return {'removido': false, 'confirmado': false, 'estado': 'claim_expirado'};
  }
  var removido = false;
  String? erroFisico;
  try {
    await client.storage
        .from(item['bucket_id'] as String)
        .remove([item['storage_path'] as String]);
    removido = true;
  } catch (e) {
    erroFisico = e.toString();
  }
  // Confirmação separada: uma falha aqui não desfaz a remoção.
  try {
    final resposta = Map<String, dynamic>.from(
      await client.rpc('registrar_limpeza_storage_executada', params: {
        'p_fila_id': filaId,
        'p_claim_token': item['claim_token'],
        'p_sucesso': removido,
        'p_erro': erroFisico,
      }) as Map,
    );
    return {
      'removido': removido,
      'confirmado': resposta['sucesso'] == true &&
          resposta['status'] == 'concluido',
      'estado': resposta['status'] ?? resposta['codigo'],
    };
  } catch (_) {
    return {
      'removido': removido,
      'confirmado': false,
      'estado': 'confirmacao_pendente',
    };
  }
}
~~~

Para envio: reservar_upload_evidencia → upload no caminho reservado, com upsert:false → anexar_documento_veiculo. Conferir sucesso da RPC de vinculação antes de confirmar envio. O CRLV usa tipo crlv; documentos complementares usam complementar. O aplicativo atual ainda mantém rascunho local.

Para remoção: remover_documento_veiculo → obter fila_id → limparEvidencia(fila_id). Após substituição, aplicar o mesmo processamento à limpeza_fila_id retornada. Não excluir diretamente um arquivo apenas pendente.

Falha ou timeout exige reconciliar a reserva e o vínculo antes de repetir. Para abandonar uma reserva ainda não vinculada, usar descartar_evidencia_temporaria e depois processar o item da fila.


---

## 4. Tabela de Códigos de Erro Tratáveis pelo Mobile

| Código | Descrição | Ação Esperada no Flutter |
| :--- | :--- | :--- |
| `RESERVA_OBRIGATORIA` | Upload sem reserva prévia ou caminho não registrado | Executar `reservar_upload_evidencia` antes do upload |
| `ARQUIVO_DESCARTADO` | Caminho já descartado ou com falha prévia de limpeza | Nunca reutilizar caminhos; gerar nova reserva |
| `ARQUIVO_JA_VINCULADO` | Tentativa de revincular objeto já anexado a outro documento | Gerar novo upload com caminho exclusivo |
| `ARQUIVO_EM_LIMPEZA` | O objeto está enfileirado para limpeza | Gerar nova reserva com caminho exclusivo |
| `VEICULO_OUTRA_EMPRESA` | Veículo do condutor cadastrado sob outra empresa | Solicitar recadastro do veículo na empresa correta |
| `ANGULO_INVALIDO` | Ângulo ausente ou diferente dos 4 permitidos | Corrigir parâmetro `p_angulo_foto` |
| `FOTOS_INCOMPLETAS` | Menos de 4 fotos cadastradas na aprovação | Notificar o condutor sobre os ângulos faltantes |
| `CRLV_AUSENTE` | Documento CRLV ausente na aprovação | Solicitar envio do documento CRLV |
| `ARQUIVO_STORAGE_NAO_ENCONTRADO` | O arquivo físico não existe no bucket | Repetir o upload binário antes de chamar a vinculação |
| `ARQUIVO_FISICO_AUSENTE` | Arquivo vinculado foi deletado do Storage | O condutor deve reenviar a foto ou CRLV ausente |
| `REVISAO_OBRIGATORIA` | Revisão esperada é obrigatória para aprovação do veículo | Fornecer a revisão atual do veículo visualizada |
| `REVISAO_DESATUALIZADA` | O veículo foi alterado durante a análise do gestor | Recarregar dados e atualizar a visualização antes de decidir |
| `EMPRESA_STORAGE_DIVERGENTE` | Caminho do arquivo tem prefixo de outra empresa | Utilizar a `empresa_id` correta do condutor |
| `USUARIO_STORAGE_DIVERGENTE` | Caminho do arquivo tem UUID de outro usuário | Utilizar o `auth.uid()` da sessão atual |
| `TAMANHO_EXCEDIDO` | Arquivo maior que 10 MB | Comprimir a imagem ou solicitar arquivo menor |
| `FOTO_NAO_ACEITA_PDF` | Foto do veículo enviada em PDF | Permitir apenas JPG ou PNG para fotos |
| `LIMITE_DOCUMENTOS_EXCEDIDO` | Mais de 5 documentos complementares | Informar limite máximo atingido |
| `USUARIO_SUSPENSO` | Usuário suspenso tentando alterar documentos | Exibir tela de suspensão da gestão |

---

## 5. Garantias e Limitações Reais de Concorrência

1. **Garantias Fornecidas:**
   - **Coordenação Explícita por Reserva:** Todo arquivo requer reserva atômica no banco antes do upload. O RLS do bucket `veiculos-documentos` restringe `INSERT` estritamente a caminhos com status `'reservado'`.
   - **Imutabilidade de Objetos:** O RLS proíbe `UPDATE` em `storage.objects` (`USING (false)`), impedindo sobrescrita concorrente.
   - **Proteção Contra Deleção Indevida:** a API só autoriza itens em processamento, pelo responsável atual e dentro do prazo da tentativa.
   - **Bloqueio Permanente de Caminhos com Falha:** Itens no estado `'falhou'` nunca podem ser reutilizados em novos uploads ou vinculações; a retomada de limpeza física requer autorização explícita (`retomar_limpeza_falha`).
   - **Isolamento Estrito Multi-Empresa:** A busca e aprovação de veículos valida estritamente `empresa_id = solicitacao.empresa_id`. Nenhuma mutação parcial ocorre em caso de divergência.
   - **Processamento Atômico da Fila:** reivindicação com SKIP LOCKED e lease de cinco minutos; a confirmação exige o token atual. Respostas de tentativas anteriores não modificam a fila. Remoções HTTP permanecem idempotentes sobre caminhos descartados e nunca reutilizados.

2. **Limitações Técnicas Reais:**
   - **Ausência de 2PC (Two-Phase Commit):** PostgreSQL e o serviço de Storage Supabase são sistemas autônomos. A coerência depende do protocolo de reserva + fila compensatória recuperável.
   - **Contorno por Chave Mestra:** Chamadas executadas com `service_role` contornam as políticas de RLS do Storage. O aplicativo mobile deve sempre operar sob credenciais de `authenticated`.

## 7. Contrato de atualização local — versão 7

Estas mudanças estão no código local. Não representam aplicação no projeto remoto.

- cadastrar_meu_veiculo(p_dados): incluir empresa_id no JSON. Com mais de um vínculo, a ausência retorna EMPRESA_OBRIGATORIA. O modelo mantém um veículo por usuário; trocar a empresa retorna VEICULO_OUTRA_EMPRESA, preservando veículo e anexos. Transferência exige um processo separado.
- Candidato com membro pendente só prepara cadastro se a solicitação atual também estiver pendente. Suspensão, rejeição e empresa inativa não autorizam alterações.
- reivindicar_itens_limpeza_storage(p_limite INT DEFAULT 10, p_fila_id UUID DEFAULT NULL): limite de 1 a 100; filtro opcional de item. Retorna claim_token e lease_expires_at. A reivindicação conta uma tentativa e registra auditoria.
- registrar_limpeza_storage_executada(p_fila_id UUID, p_claim_token UUID, p_sucesso BOOLEAN, p_erro TEXT DEFAULT NULL): exige o responsável, token atual e prazo válido. Não aceita reservas, vínculos nem respostas de tentativas anteriores. O sucesso exige ausência do metadado do objeto no Storage.
- DELETE no Storage exige item em processamento, responsável atual e prazo ativo.
- Retomada de falha invalida tokens anteriores. O histórico permanece em auditoria_acessos.
- Novos códigos: CLAIM_INVALIDO, CLAIM_EXPIRADO, ESTADO_INVALIDO, OBJETO_AINDA_PRESENTE, CICLO_EVIDENCIA_INCONSISTENTE, EMPRESA_OBRIGATORIA.
- iniciar_rota, concluir_rota e registrar_conclusao_entrega conferem empresa, atribuição, membro ativo e veículo aprovado/completo. Identificadores nulos não liberam operações.
- obter_meu_status_acesso distingue vínculo aprovado de operacional_liberado. Não liberar operações somente porque status=aprovado.
- Caminhos descartados são imutáveis. Exclusão física e confirmação no banco são etapas diferentes. Se a confirmação falhar, mostrar pendência e recuperar a fila.
- A consulta SQL verifica metadados, não comprova isoladamente o binário no provedor. Testes locais não substituem HTTP com Auth, PostgREST e Storage reais.

Validação reproduzível e limites: supabase/tests/README.md.