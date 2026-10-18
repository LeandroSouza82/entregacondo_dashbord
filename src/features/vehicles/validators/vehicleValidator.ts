import type { CadastroVeiculoInput } from '../types/vehicle';

export interface ValidacaoVeiculoResultado {
  valido: boolean;
  erros: string[];
  dadosNormalizados?: CadastroVeiculoInput;
}

export function validarCadastroVeiculo(input: Partial<CadastroVeiculoInput>): ValidacaoVeiculoResultado {
  const erros: string[] = [];

  const tipo = input.tipo_veiculo;
  if (!tipo || (tipo !== 'moto' && tipo !== 'carro')) {
    erros.push('Tipo de veículo deve ser "moto" ou "carro".');
  }

  const marca = (input.marca || '').trim();
  if (!marca) {
    erros.push('Marca do veículo é obrigatória.');
  }

  const modelo = (input.modelo || '').trim();
  if (!modelo) {
    erros.push('Modelo do veículo é obrigatório.');
  }

  const placaLimpa = (input.placa || '').replace(/[^a-zA-Z0-9]/g, '').toUpperCase();
  if (placaLimpa.length < 7 || placaLimpa.length > 8) {
    erros.push('Placa inválida (informe padrão Mercosul ou 3 letras + 4 números).');
  }

  if (tipo === 'carro') {
    // Carro não deve possuir compartimento, volume ou capacidade
    return {
      valido: erros.length === 0,
      erros,
      dadosNormalizados: erros.length === 0 ? {
        tipo_veiculo: 'carro',
        marca,
        modelo,
        placa: placaLimpa,
        compartimento: null,
        volume_litros: null,
        tamanho_compartimento: null,
        capacidade_kg: null,
      } : undefined,
    };
  }

  if (tipo === 'moto') {
    const compartimento = input.compartimento;
    if (!compartimento || !['bau', 'mochila', 'bag'].includes(compartimento)) {
      erros.push('Para moto, selecione o compartimento: baú, mochila ou bag.');
    }

    const capacidadeKg = Number(input.capacidade_kg);
    if (isNaN(capacidadeKg) || capacidadeKg <= 0 || !isFinite(capacidadeKg)) {
      erros.push('Capacidade em kg deve ser um número positivo.');
    }

    let volumeLitros: number | null = null;
    let tamanhoCompartimento: 'pequeno' | 'medio' | 'grande' | null = null;

    if (compartimento === 'bau') {
      const vol = Number(input.volume_litros);
      if (isNaN(vol) || vol <= 0 || !isFinite(vol)) {
        erros.push('Para baú, o volume em litros deve ser informado e positivo.');
      } else {
        volumeLitros = vol;
      }
    } else if (compartimento === 'mochila' || compartimento === 'bag') {
      const tam = input.tamanho_compartimento;
      if (!tam || !['pequeno', 'medio', 'grande'].includes(tam)) {
        erros.push('Para mochila/bag, selecione o tamanho: pequeno, médio ou grande.');
      } else {
        tamanhoCompartimento = tam;
      }
    }

    return {
      valido: erros.length === 0,
      erros,
      dadosNormalizados: erros.length === 0 ? {
        tipo_veiculo: 'moto',
        marca,
        modelo,
        placa: placaLimpa,
        compartimento: compartimento as 'bau' | 'mochila' | 'bag',
        volume_litros: volumeLitros,
        tamanho_compartimento: tamanhoCompartimento,
        capacidade_kg: capacidadeKg,
      } : undefined,
    };
  }

  return { valido: false, erros };
}
