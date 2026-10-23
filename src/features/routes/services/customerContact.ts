/** Brazilian DDD by default; explicit + supports international numbers. Empty is optional. */
export function normalizeCustomerWhatsApp(input: string): string {
  const value = input.trim();
  if (!value) return '';
  const digits = value.replace(/\D/g, '');
  if (!value.startsWith('+') && /^\d{10,11}$/.test(digits) && !digits.startsWith('0')) return `55${digits}`;
  if ((value.startsWith('+') || digits.startsWith('55')) && /^[1-9]\d{9,14}$/.test(digits)) return digits;
  throw new Error('Informe o WhatsApp com DDD. Para outro país, use + e o código do país.');
}

/** Legacy apartments are observations, never phone numbers, even if only digits. */
export function legacyAddressNotes(notes?: string | null, apartment?: string | null): string {
  const text = notes?.trim() || '';
  const old = apartment?.trim() || '';
  return old && !text.includes(old) ? [text, `Apartamento/complemento: ${old}`].filter(Boolean).join('\n') : text;
}
