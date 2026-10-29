export function normalizeDocument(value: string): string {
  return value.replace(/[./\s-]/g, '').toUpperCase();
}

// Check digits only; this does not verify ownership or registration status.
export function isValidDocument(kind: 'pf' | 'pj', value: string): boolean {
  const doc = normalizeDocument(value);
  if (/^(.)\1+$/.test(doc)) return false;
  if (!(kind === 'pf' ? /^\d{11}$/ : /^[A-Z0-9]{12}\d{2}$/).test(doc)) return false;
  for (let pass = 0; pass < 2; pass++) {
    const base = (kind === 'pf' ? 9 : 12) + pass;
    const weights = pass === 0 ? [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2] : [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2];
    let sum = 0;
    for (let i = 0; i < base; i++) sum += (doc.charCodeAt(i) - 48) * (kind === 'pf' ? base + 1 - i : weights[i]);
    const digit = kind === 'pf' ? (sum * 10 % 11) % 10 : sum % 11 < 2 ? 0 : 11 - sum % 11;
    if (digit !== Number(doc[base])) return false;
  }
  return true;
}
