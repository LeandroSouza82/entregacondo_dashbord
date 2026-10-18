# Contrato Canônico de Integração Mobile (Flutter) x Backend EntregaCondo
**Projeto Supabase:** `vblwuvhdqgzdjnoscyqo`  
**URL:** `https://vblwuvhdqgzdjnoscyqo.supabase.co`  
**Versão do Contrato:** 4.1.0 (Canônico: 4 Fotos por Ângulo, CRLV, Storage Privado & RPCs Auditadas)  
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
[3. Veículo Declarado & 4 Fotos + CRLV Enviados] 
       ↓ 
[4. Análise Humana da Gestão (Conferência Documental)] 
       ↓ 
[5. Acesso Operacional Totalmente Liberado às Rotas]
```

### Os 5 Níveis Explicados:
1. **Conta Autenticada:** O condutor realizou login via Supabase Auth (`auth.uid()`). Não possui acesso a nenhuma rota, condomínio ou cliente.
2. **Vínculo Solicitado:** O condutor enviou o código de convite da empresa (ex: `EC-FLN-01`) via `solicitar_acesso_empresa`. Solicitação registrada com status `pendente`.
3. **Veículo Declarado e Evidências Vinculadas:**
   - O condutor salvou os dados cadastrais via `cadastrar_meu_veiculo` (regras alinhadas ao `VEICULO_MOBILE.md`).
   - O condutor fez o upload das **4 fotos obrigatórias** (`frente`, `lado_direito`, `lado_esquerdo`, `traseira`) e do **CRLV** para o bucket privado `veiculos-documentos`, confirmando cada anexo via `anexar_documento_veiculo`.
4. **Análise Humana pela Gestão:** O gestor analisa no dashboard os dados cadastrais, as 4 fotos identificadas por ângulo e o documento CRLV.
   - O backend **rejeita aprovação** se faltar qualquer um dos 4 ângulos ou o CRLV.
   - O gestor pode aprovar criando um novo cadastro de motorista operacional (**Opção A**) ou vinculando a um motorista desocupado (**Opção B**).
5. **Acesso Operacional Liberado:** Condutor aprovado e veículo aprovado. Apenas neste estágio o motorista recebe rotas atribuídas.

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

> ⚠️ **Comportamento de Substituição:** O envio de uma nova foto com o ângulo `'frente'` substitui **apenas** a foto anterior da frente, **preservando intactas** as fotos de lado direito, lado esquerdo e traseira. Fotos legadas sem ângulo são mantidas no histórico, mas não contabilizam como fotos dos 4 ângulos requeridos.

---

## 3. Catálogo de RPCs do Aplicativo Móvel

### 3.1 Consulta de Acesso: `obter_meu_status_acesso()`

Chamada obrigatória ao abrir o aplicativo ou ao retornar do segundo plano (`AppLifecycleState.resumed`).

```dart
final response = await supabase.rpc('obter_meu_status_acesso');
final statusData = Map<String, dynamic>.from(response);
```

**Retorno com Acesso Liberado:**
```json
{
  "autenticado": true,
  "user_id": "cccccccc-cccc-cccc-cccc-cccccccccccc",
  "status": "aprovado",
  "papel": "motorista",
  "empresa_id": "11111111-1111-1111-1111-111111111111",
  "empresa_nome": "EntregaCondo Logística Matriz",
  "motorista_id": "33333333-3333-3333-3333-333333333333",
  "motorista_nome": "Marcos Silva",
  "veiculo": "Honda CG 160 Fan (BRA3G44)",
  "veiculo_status": "aprovado",
  "veiculo_tipo": "moto",
  "motivo": null,
  "mensagem": "Acesso operacional liberado com sucesso."
}
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

Alinhado estritamente às regras de negócio de `VEICULO_MOBILE.md`:

#### Regras:
- **Carro:** Apenas `tipo_veiculo: 'carro'`, `marca`, `modelo` e `placa`. Não enviar peso, volume, compartimento ou dimensões.
- **Moto com Baú:** `tipo_veiculo: 'moto'`, `compartimento: 'bau'`, `volume_litros: > 0` e `capacidade_kg: > 0`. Opções sugeridas no app: 20, 30, 50, 80, 100 e 120 litros (aceita digitação livre). Não enviar dimensões.
- **Moto com Mochila ou Bag:** `tipo_veiculo: 'moto'`, `compartimento: 'mochila' | 'bag'`, `tamanho_compartimento: 'pequeno' | 'medio' | 'grande'` e `capacidade_kg: > 0`. Não enviar litros ou dimensões.
- **Reversão de Status:** Se um veículo já aprovado for editado, o status de análise no servidor **retorna imediatamente para `'pendente'`**, exigindo nova validação da gestão.

**Exemplo Dart — Cadastro de Carro:**
```dart
Future<void> cadastrarCarro({
  required String marca,
  required String modelo,
  required String placa,
}) async {
  final payload = {
    'tipo_veiculo': 'carro',
    'marca': marca.trim(),
    'modelo': modelo.trim(),
    'placa': placa.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase(),
  };

  final res = await supabase.rpc('cadastrar_meu_veiculo', params: {
    'p_dados': payload,
  });

  if (res['sucesso'] != true) {
    throw Exception(res['mensagem'] ?? 'Falha ao cadastrar veículo');
  }
}
```

**Exemplo Dart — Cadastro de Moto (Baú):**
```dart
Future<void> cadastrarMotoBau({
  required String marca,
  required String modelo,
  required String placa,
  required double volumeLitros,
  required double capacidadeKg,
}) async {
  final payload = {
    'tipo_veiculo': 'moto',
    'marca': marca.trim(),
    'modelo': modelo.trim(),
    'placa': placa.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '').toUpperCase(),
    'compartimento': 'bau',
    'volume_litros': volumeLitros,
    'capacidade_kg': capacidadeKg,
  };

  final res = await supabase.rpc('cadastrar_meu_veiculo', params: {
    'p_dados': payload,
  });

  if (res['sucesso'] != true) {
    throw Exception(res['mensagem'] ?? 'Falha ao cadastrar moto com baú');
  }
}
```

---

### 3.4 Upload e Vinculação de Fotos e Documentos: `anexar_documento_veiculo(...)`

O fluxo ocorre em **duas etapas atômicas**:
1. Upload binário no bucket privado `veiculos-documentos`.
2. Chamada à RPC `anexar_documento_veiculo` para validação e persistência dos metadados.

#### Padrão Obrigatório de Caminho (Zero PII):
`{empresa_id}/{auth.uid()}/{timestamp}_{tipo}.{ext}`  
*(Nunca incluir nome, e-mail ou placa no caminho do arquivo).*

#### Assinatura da RPC:
| Parâmetro | Tipo | Descrição |
| :--- | :--- | :--- |
| `p_veiculo_id` | `UUID` | ID do veículo retornado no cadastro |
| `p_tipo_documento` | `TEXT` | `'foto_veiculo'` \| `'crlv'` \| `'complementar'` |
| `p_nome_arquivo` | `TEXT` | Nome original do arquivo (ex: `frente.jpg`) |
| `p_storage_path` | `TEXT` | Caminho salvo no bucket privado |
| `p_tamanho_bytes` | `INT` | Tamanho em bytes (máx 10.485.760) |
| `p_angulo_foto` | `TEXT?` | Obrigatório para `foto_veiculo`: `'frente'`, `'lado_direito'`, `'lado_esquerdo'` ou `'traseira'` |

**Implementação Completa em Dart (Flutter):**
```dart
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> enviarFotoVeiculo({
  required String veiculoId,
  required String empresaId,
  required File arquivoFoto,
  required String angulo, // 'frente' | 'lado_direito' | 'lado_esquerdo' | 'traseira'
}) async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) throw Exception('Condutor não autenticado');

  final tamanho = await arquivoFoto.length();
  if (tamanho > 10 * 1024 * 1024) {
    throw Exception('A foto excede o limite de 10 MB.');
  }

  final ext = p.extension(arquivoFoto.path).toLowerCase();
  if (!['.jpg', '.jpeg', '.png'].contains(ext)) {
    throw Exception('Fotos do veículo devem estar no formato JPG ou PNG.');
  }

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final storagePath = '$empresaId/${user.id}/foto_${angulo}_$timestamp$ext';

  // 1. Upload binário no bucket privado
  await supabase.storage.from('veiculos-documentos').upload(
    storagePath,
    arquivoFoto,
    fileOptions: FileOptions(
      contentType: ext == '.png' ? 'image/png' : 'image/jpeg',
      upsert: true,
    ),
  );

  // 2. Confirmação dos metadados no Postgres
  final res = await supabase.rpc('anexar_documento_veiculo', params: {
    'p_veiculo_id': veiculoId,
    'p_tipo_documento': 'foto_veiculo',
    'p_nome_arquivo': 'foto_$angulo$ext',
    'p_storage_path': storagePath,
    'p_tamanho_bytes': tamanho,
    'p_angulo_foto': angulo,
  });

  if (res['sucesso'] != true) {
    // Limpeza de arquivo órfão no storage em caso de erro de validação
    await supabase.storage.from('veiculos-documentos').remove([storagePath]);
    throw Exception(res['mensagem'] ?? 'Falha ao vincular foto do veículo.');
  }
}

Future<void> enviarCrlv({
  required String veiculoId,
  required String empresaId,
  required File arquivoCrlv,
}) async {
  final supabase = Supabase.instance.client;
  final user = supabase.auth.currentUser;
  if (user == null) throw Exception('Condutor não autenticado');

  final tamanho = await arquivoCrlv.length();
  if (tamanho > 10 * 1024 * 1024) {
    throw Exception('O arquivo do CRLV excede o limite de 10 MB.');
  }

  final ext = p.extension(arquivoCrlv.path).toLowerCase();
  String mimeType = 'application/pdf';
  if (ext == '.png') mimeType = 'image/png';
  if (ext == '.jpg' || ext == '.jpeg') mimeType = 'image/jpeg';

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final storagePath = '$empresaId/${user.id}/crlv_$timestamp$ext';

  await supabase.storage.from('veiculos-documentos').upload(
    storagePath,
    arquivoCrlv,
    fileOptions: FileOptions(contentType: mimeType, upsert: true),
  );

  final res = await supabase.rpc('anexar_documento_veiculo', params: {
    'p_veiculo_id': veiculoId,
    'p_tipo_documento': 'crlv',
    'p_nome_arquivo': p.basename(arquivoCrlv.path),
    'p_storage_path': storagePath,
    'p_tamanho_bytes': tamanho,
    'p_angulo_foto': null,
  });

  if (res['sucesso'] != true) {
    await supabase.storage.from('veiculos-documentos').remove([storagePath]);
    throw Exception(res['mensagem'] ?? 'Falha ao registrar CRLV.');
  }
}

Future<void> removerDocumento({
  required String documentoId,
}) async {
  final supabase = Supabase.instance.client;

  // 1. Invoca a RPC que desvincula o documento e invalida a aprovação do veículo
  final res = await supabase.rpc('remover_documento_veiculo', params: {
    'p_documento_id': documentoId,
  });

  if (res['sucesso'] != true) {
    throw Exception(res['mensagem'] ?? 'Falha ao remover documento.');
  }

  // 2. Remove o arquivo físico do bucket privado
  final storagePath = res['storage_path'] as String?;
  if (storagePath != null && storagePath.isNotEmpty) {
    await supabase.storage.from('veiculos-documentos').remove([storagePath]);
  }
}
```

---

## 4. Tabela de Códigos de Erro Tratáveis pelo Mobile

| Código | Descrição | Ação Esperada no Flutter |
| :--- | :--- | :--- |
| `ANGULO_INVALIDO` | Ângulo ausente ou diferente dos 4 permitidos | Corrigir parâmetro `p_angulo_foto` |
| `FOTOS_INCOMPLETAS` | Menos de 4 fotos cadastradas na aprovação | Notificar o condutor sobre os ângulos faltantes |
| `CRLV_AUSENTE` | Documento CRLV ausente na aprovação | Solicitar envio do documento CRLV |
| `ARQUIVO_STORAGE_NAO_ENCONTRADO` | O arquivo físico não existe no bucket | Repetir o upload binário antes de chamar a RPC |
| `ARQUIVO_FISICO_AUSENTE` | Um arquivo previamente vinculado foi deletado do Storage | O condutor deve reenviar a foto ou CRLV ausente |
| `EMPRESA_STORAGE_DIVERGENTE` | Caminho do arquivo tem prefixo de outra empresa | Utilizar a `empresa_id` correta do condutor |
| `USUARIO_STORAGE_DIVERGENTE` | Caminho do arquivo tem UUID de outro usuário | Utilizar o `auth.uid()` da sessão atual |
| `TAMANHO_EXCEDIDO` | Arquivo maior que 10 MB | Comprimir a imagem ou solicitar arquivo menor |
| `FOTO_NAO_ACEITA_PDF` | Foto do veículo enviada em PDF | Permitir apenas JPG ou PNG para fotos |
| `LIMITE_DOCUMENTOS_EXCEDIDO` | Mais de 5 documentos complementares | Informar limite máximo atingido |
| `USUARIO_SUSPENSO` | Usuário suspenso tentando alterar documentos | Exibir tela de suspensão da gestão |

### 4.1 Sequência Segura de Upload, Substituição e Remoção (Coordenação sem 2PC)

Como o Supabase Storage e o PostgreSQL operam de forma assíncrona e não compartilham transação de duas fases (2PC):

1. **Upload Inicial e Vinculação:**
   - 1º: Aplicativo envia o arquivo binário para o Storage (`storage.from('veiculos-documentos').upload(path, file)`).
   - 2º: Aplicativo chama `anexar_documento_veiculo(...)` registrando metadados, incrementando a `revisao` do veículo e invalidando aprovação anterior.
   - *Proteção Ativa no Banco:* Assim que o metadado é gravado em `veiculos_documentos`, as políticas RLS `DELETE` e `UPDATE` em `storage.objects` **bloqueiam imediatamente qualquer exclusão ou alteração direta do arquivo** via Storage API, mesmo se o veículo ainda estiver com status `'pendente'`.
   - *Falha parcial no passo 2:* Se a RPC falhar (ex: usuário suspenso, ângulo inválido), o arquivo ainda não está vinculado em `veiculos_documentos`, permitindo que o aplicativo faça a limpeza física imediata (`remove([path])`).

2. **Substituição de Evidência:**
   - O aplicativo envia a nova foto para o Storage com novo timestamp.
   - Ao chamar `anexar_documento_veiculo(...)` com o mesmo `angulo_foto`, o backend:
     - Remove atomicamente o vínculo do registro anterior em `veiculos_documentos`;
     - Vincula o novo arquivo;
     - Retorna o status do veículo para `'pendente'`;
     - Incrementa a `revisao` do veículo.
   - Com o arquivo antigo agora desvinculado de `veiculos_documentos`, o RLS do Storage passa a permitir que o cliente o remova fisicamente da API do Storage.

3. **Remoção de Evidência:**
   - 1º: Aplicativo invoca a RPC `remover_documento_veiculo(documentoId)`. A RPC valida a autorização do condutor (bloqueia suspensos), remove o registro de `veiculos_documentos`, retorna o veículo para `'pendente'` e incrementa a `revisao`.
   - 2º: A RPC retorna o campo `storage_path`.
   - 3º: O aplicativo executa `storage.from('veiculos-documentos').remove([storage_path])`. Como o arquivo foi desvinculado no banco, a política de exclusão autoriza a deleção física.
   - *Proteção Contra Bypass:* Qualquer tentativa do cliente de invocar `storage.remove()` diretamente sem passar pela RPC é rejeitada com erro de permissão RLS pelo PostgreSQL (`NOT EXISTS (SELECT 1 FROM veiculos_documentos ...)`).

4. **Concorrência e Decisão Vinculada à Revisão:**
   - As RPCs de análise (`analisar_veiculo_motorista` e `aprovar_solicitacao_motorista`) exigem `p_revisao_esperada`.
   - O backend obtém `SELECT ... FOR UPDATE` sobre o veículo. Se a `revisao` atual diferir de `p_revisao_esperada` (porque o motorista anexou, substituiu ou removeu uma evidência enquanto o gestor olhava a tela), a aprovação é rejeitada com o código `REVISAO_DESATUALIZADA`.
   - O gestor é obrigado a recarregar a visualização antes de homologar.
   - A validação de completude `fn_validar_completude_veiculo` confere os metadados de Storage no momento do lock. Se a infraestrutura de Storage estiver inacessível, a transação aborta explicitamente com `INFRAESTRUTURA_STORAGE_INDISPONIVEL`.

---

## 5. Operações de Rota (Idempotentes)

1. **`iniciar_rota(p_rota_id)`**: Marca rota como `em_execucao`.
2. **`registrar_conclusao_entrega(...)`**: Registra baixa de entrega com tempos de portaria e deslocamento.
3. **`concluir_rota(p_rota_id)`**: Finaliza a rota após conclusão de todas as paradas.
