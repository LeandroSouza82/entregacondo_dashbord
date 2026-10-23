import { useEffect, useState } from 'react';
import { requireCompanyId } from './company';
import { supabase } from './supabase';

const companyNameChanged = 'entregacondo:company-name-changed';
export function notifyCompanyNameChanged(companyId: string, name: string) {
  window.dispatchEvent(new CustomEvent(companyNameChanged, { detail: { companyId, name: name.trim() } }));
}

/** Display identity only; never used to grant access or select another company. */
export function useCompanyIdentity() {
  const [identity, setIdentity] = useState({ id: '', name: '' });
  useEffect(() => {
    let active = true;
    void (async () => {
      try {
        const id = await requireCompanyId();
        const { data, error } = await supabase.from('empresas').select('nome').eq('id', id).single();
        if (active && !error && data?.nome) setIdentity({ id, name: data.nome });
      } catch { /* Keep the neutral placeholder when offline or unavailable. */ }
    })();
    const changed = (event: Event) => {
      const { companyId, name } = (event as CustomEvent<{ companyId: string; name: string }>).detail;
      setIdentity(current => current.id === companyId ? { ...current, name } : current);
    };
    window.addEventListener(companyNameChanged, changed);
    return () => { active = false; window.removeEventListener(companyNameChanged, changed); };
  }, []);
  return identity;
}
