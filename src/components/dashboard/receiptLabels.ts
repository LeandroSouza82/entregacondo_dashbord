const labels: Record<string, string> = {
  sindico: "Síndico",
  zelador: "Zelador",
  faxineiro: "Faxineiro(a)",
  porteiro: "Porteiro",
  vizinho: "Vizinho",
  proprio_cliente: "O próprio cliente",
  familiar: "Familiar",
  funcionario: "Funcionário",
  recepcao: "Recepção",
  seguranca: "Segurança",
  responsavel_coleta: "Responsável pela coleta",
  outro: "Outra pessoa",
  tentativa_falha: "Ocorrência",
};
export const receiptLabel = (value: string) =>
  labels[value] || value.replaceAll("_", " ");
