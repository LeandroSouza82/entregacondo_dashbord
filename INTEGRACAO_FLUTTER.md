# Contrato Canônico de Integração Mobile (Flutter) x Backend EntregaCondo
**Projeto Supabase:** `vblwuvhdqgzdjnoscyqo`  
**URL:** `https://vblwuvhdqgzdjnoscyqo.supabase.co`  
**Versão do Contrato:** 5.0.0 (Coordenação de Ciclo de Vida do Storage, Aprovações Atômicas e Revisão Estrita)  
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
[4. Análise Humana da Gestão (Conferência Documental com Revisão)] 
       ↓ 
[5. Acesso Operacional Totalmente Liberado às Rotas]
```

### Os 5 Níveis Explicados:
1. **Conta Autenticada:** O condutor realizou login via Supabase Auth (`auth.uid()`). Não possui acesso a nenhuma rota, condomínio ou cliente.
2. **Vínculo Solicitado:** O condutor enviou o código de convite da empresa (ex: `EC-FLN-01`) via `solicitar_acesso_empresa`. Solicitação registrada com status `pendente`.
3. **Veículo Declarado e Evidências Vinculadas:**
   - O condutor salvou os dados cadastrais via `cadastrar_meu_veiculo` (regras alinhadas ao `VEICULO_MOBILE.md`).
   - O condutor fez o upload das **4 fotos obrigatórias** (`frente`, `lado_direito`, `lado_esquerdo`, `traseira`) e do **CRLV** para o bucket privado `veiculos-documentos`, confirmando cada anexo via `anexar_documento_veiculo`.
4. **Análise Humana pela Gestão com Controle de Revisão:**
   - O gestor analisa no dashboard os dados cadastrais, as 4 fotos identificadas por ângulo e o documento CRLV.
   - O backend **rejeita aprovação** se faltar qualquer um dos 4 ângulos ou o CRLV.
   - A aprovação do veículo exige **obrigatoriamente** o envio do número da revisão visualizada pelo gestor (`p_revisao_esperada_veiculo`). Se omitida (`NULL`) ou desatualizada, a transação recusa a aprovação **sem qualquer mutação parcial**.
   - A aprovação do vínculo pode ocorrer separadamente da aprovação técnica do veículo. Se o gestor aprovar apenas o vínculo (`p_aprovar_veiculo = FALSE`), o veículo permanece em status `pendente`.
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

> ⚠️ **Comportamento de Substituição Coordenada:** O envio de uma nova foto com o ângulo `'frente'` desvincula a foto anterior da frente e enfileira o caminho antigo na tabela `public.storage_limpeza_fila`, **preservando intactas** as fotos de lado direito, lado esquerdo e traseira. Fotos legadas sem ângulo são mantidas no histórico, mas não contabilizam como fotos dos 4 ângulos requeridos.

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

---

### 3.4 Upload, Vinculação e Limpeza de Evidências

O ciclo de vida de arquivos segue protocolo coordenado:

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
    await supabase.storage.from('veiculos-documentos').remove([storagePath]);
    throw Exception(res['mensagem'] ?? 'Falha ao vincular foto do veículo.');
  }

  // 3. Se uma foto antiga foi substituída, ela foi enfileirada para limpeza física
  final arquivoSubstituido = res['arquivo_substituido_path'] as String?;
  final filaId = res['limpeza_fila_id'] as String?;
  if (arquivoSubstituido != null && filaId != null) {
    try {
      await supabase.storage.from('veiculos-documentos').remove([arquivoSubstituido]);
      await supabase.rpc('registrar_limpeza_storage_executada', params: {
        'p_fila_id': filaId,
        'p_sucesso': true,
        'p_erro': null,
      });
    } catch (e) {
      await supabase.rpc('registrar_limpeza_storage_executada', params: {
        'p_fila_id': filaId,
        'p_sucesso': false,
        'p_erro': e.toString(),
      });
    }
  }
}

Future<void> removerDocumento({
  required String documentoId,
}) async {
  final supabase = Supabase.instance.client;

  // 1. RPC atômica: desvincula o documento, invalida a aprovação e enfileira em storage_limpeza_fila
  final res = await supabase.rpc('remover_documento_veiculo', params: {
    'p_documento_id': documentoId,
  });

  if (res['sucesso'] != true) {
    throw Exception(res['mensagem'] ?? 'Falha ao desvincular evidência.');
  }

  final storagePath = res['storage_path'] as String?;
  final filaId = res['fila_id'] as String?;

  // 2. Limpeza física no Supabase Storage via API oficial
  if (storagePath != null && filaId != null) {
    try {
      await supabase.storage.from('veiculos-documentos').remove([storagePath]);
      await supabase.rpc('registrar_limpeza_storage_executada', params: {
        'p_fila_id': filaId,
        'p_sucesso': true,
        'p_erro': null,
      });
    } catch (e) {
      await supabase.rpc('registrar_limpeza_storage_executada', params: {
        'p_fila_id': filaId,
        'p_sucesso': false,
        'p_erro': e.toString(),
      });
    }
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
| `ARQUIVO_FISICO_AUSENTE` | Arquivo vinculado foi deletado do Storage | O condutor deve reenviar a foto ou CRLV ausente |
| `ARQUIVO_EM_LIMPEZA` | O objeto está enfileirado para limpeza | O aplicativo deve gerar um caminho novo com timestamp atual |
| `REVISAO_OBRIGATORIA` | Revisão esperada é obrigatória para aprovação do veículo | Fornecer a revisão atual do veículo |
| `REVISAO_DESATUALIZADA` | O veículo foi alterado durante a análise | Recarregar dados e atualizar a visualização antes de decidir |
| `EMPRESA_STORAGE_DIVERGENTE` | Caminho do arquivo tem prefixo de outra empresa | Utilizar a `empresa_id` correta do condutor |
| `USUARIO_STORAGE_DIVERGENTE` | Caminho do arquivo tem UUID de outro usuário | Utilizar o `auth.uid()` da sessão atual |
| `TAMANHO_EXCEDIDO` | Arquivo maior que 10 MB | Comprimir a imagem ou solicitar arquivo menor |
| `FOTO_NAO_ACEITA_PDF` | Foto do veículo enviada em PDF | Permitir apenas JPG ou PNG para fotos |
| `LIMITE_DOCUMENTOS_EXCEDIDO` | Mais de 5 documentos complementares | Informar limite máximo atingido |
| `USUARIO_SUSPENSO` | Usuário suspenso tentando alterar documentos | Exibir tela de suspensão da gestão |

---

## 5. Garantias e Limitações Reais de Concorrência

1. **Garantias Fornecidas:**
   - Toda evidência vinculada a um veículo está protegida no banco contra exclusão e sobrescrita direta pelo RLS de `storage.objects`.
   - Uma aprovação com revisão ausente ou desatualizada é recusada **antes de qualquer mutação**, garantindo zero escritas parciais.
   - Chamadas subsequentes ou retentativas não duplicam registros na frota de motoristas.
   - Objetos desvinculados entram na tabela auditável `storage_limpeza_fila`, garantindo rastreabilidade e recuperação em caso de falha de rede na API de Storage.
2. **Limitações Técnicas Reais:**
   - PostgreSQL e a API de Supabase Storage não possuem transação distribuída de duas fases (2PC). A sincronização entre metadados e arquivos de bloco apoia-se no protocolo de duas etapas com fila recuperável.
   - Chamadas administrativas executadas com a chave mestre `service_role` contornam o motor de RLS.
