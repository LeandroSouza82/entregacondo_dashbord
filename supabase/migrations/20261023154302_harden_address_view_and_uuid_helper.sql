-- Preserve every address and dependent object; enforce the caller's existing RLS.
BEGIN;
ALTER VIEW public.saved_addresses SET (security_invoker=true);
REVOKE ALL ON public.saved_addresses FROM anon;
GRANT SELECT ON public.saved_addresses TO authenticated;
ALTER FUNCTION public.fn_safe_uuid(text) SET search_path='';
NOTIFY pgrst, 'reload schema';
COMMIT;
