-- Synthetic fixtures in a disposable PostgreSQL only.
BEGIN;
CREATE TEMP TABLE receipt_checks(label text);
CREATE FUNCTION pg_temp.assert_receipt(ok boolean,label text) RETURNS void LANGUAGE plpgsql AS $$
BEGIN IF ok IS DISTINCT FROM true THEN RAISE EXCEPTION 'Receipt sharing: %',label; END IF; INSERT INTO receipt_checks VALUES(label); END $$;
CREATE FUNCTION pg_temp.reject_receipt(statement text,expected text,label text) RETURNS void LANGUAGE plpgsql AS $$
DECLARE blocked boolean:=false;
BEGIN
 BEGIN EXECUTE statement; EXCEPTION WHEN OTHERS THEN
  IF SQLERRM !~* expected THEN RAISE EXCEPTION 'Unexpected failure in %: %',label,SQLERRM; END IF;blocked:=true;
 END;
 PERFORM pg_temp.assert_receipt(blocked,label);
END $$;
DO $$
DECLARE company uuid:='11111111-1111-1111-1111-111111111111'; driver uuid:='c1000000-0000-0000-0000-000000000001';
 p uuid:='da100000-0000-0000-0000-000000000001'; q uuid:='da200000-0000-0000-0000-000000000001'; foreign_task uuid:=gen_random_uuid(); addr uuid;
 photo text; signature text; photo_url text; signature_url text; result jsonb;
 car uuid; angle text; reservation jsonb; rev int;
BEGIN
 -- Same real authorization prerequisites as the operational receipt tests.
 PERFORM set_config('request.jwt.claim.sub','cccccccc-cccc-cccc-cccc-cccccccccccc',true);
 SELECT id INTO car FROM public.veiculos_motoristas WHERE user_id=auth.uid();
 FOREACH angle IN ARRAY ARRAY['frente','lado_direito','lado_esquerdo','traseira'] LOOP
  reservation:=public.reservar_upload_evidencia(company,'foto_veiculo',angle||'.jpg',angle);
  INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('veiculos-documentos',reservation->>'storage_path','{"size":500,"mimetype":"image/jpeg"}');
  PERFORM public.anexar_documento_veiculo(car,'foto_veiculo',angle||'.jpg',reservation->>'storage_path',500,angle);
 END LOOP;
 reservation:=public.reservar_upload_evidencia(company,'crlv','crlv.pdf');
 INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('veiculos-documentos',reservation->>'storage_path','{"size":500,"mimetype":"application/pdf"}');
 PERFORM public.anexar_documento_veiculo(car,'crlv','crlv.pdf',reservation->>'storage_path',500);
 PERFORM set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',true);
 SELECT revisao INTO rev FROM public.veiculos_motoristas WHERE id=car;PERFORM public.analisar_veiculo_motorista(car,true,rev);
 INSERT INTO public.clientes_enderecos(empresa_id,nome_identificador,endereco_completo,numero,bairro,cidade,cep,latitude,longitude)
 VALUES(company,'Receipt fixture','Rua teste','1','Centro','Palhoça','88132292',-27.63,-48.68) RETURNING id INTO addr;
 INSERT INTO public.entregas(id,empresa_id,motorista_id,cliente_endereco_id,codigo_rastreio,destinatario_nome,status)
 VALUES(p,company,driver,addr,'SHARE-P','CLIENT-A','entregue'),(q,company,driver,addr,'SHARE-Q','CLIENT-B','entregue');
 photo:=company::text||'/cccccccc-cccc-cccc-cccc-cccccccccccc/'||p::text||'/foto.jpg';
 signature:=company::text||'/cccccccc-cccc-cccc-cccc-cccccccccccc/'||p::text||'/assinatura.png';
 INSERT INTO storage.objects(bucket_id,name,metadata) VALUES('entregas-comprovantes',photo,'{"mimetype":"image/jpeg"}'),('entregas-comprovantes',signature,'{"mimetype":"image/png"}');
 INSERT INTO public.entrega_comprovantes(entrega_id,empresa_id,registrado_por,recebedor_tipo,recebedor_nome,foto_path,assinatura_path,chegada_em,concluida_em,duracao_segundos)
 VALUES(p,company,'cccccccc-cccc-cccc-cccc-cccccccccccc','porteiro','Pessoa A',photo,signature,now()-interval '2 minutes',now(),120),
 (q,company,'cccccccc-cccc-cccc-cccc-cccccccccccc','zelador','Pessoa B',NULL,NULL,now()-interval '3 minutes',now(),180);
 photo_url:='https://test.supabase.co/storage/v1/object/sign/entregas-comprovantes/'||photo||'?token=synthetic.photo';
 signature_url:='https://test.supabase.co/storage/v1/object/sign/entregas-comprovantes/'||signature||'?token=synthetic.signature';
 PERFORM pg_temp.assert_receipt((SELECT public=false FROM storage.buckets WHERE id='entregas-comprovantes'),'bucket is private');
 PERFORM pg_temp.assert_receipt(NOT EXISTS(SELECT FROM pg_policies WHERE schemaname='storage' AND policyname='comprovante_publico_download'),'no public bucket policy');
 PERFORM pg_temp.assert_receipt(NOT has_function_privilege('anon','public.obter_comprovante_publico(uuid)','EXECUTE'),'UUID endpoint is not anonymous');
 PERFORM pg_temp.assert_receipt(NOT has_schema_privilege('authenticated','ec_private','USAGE') AND NOT has_table_privilege('anon','ec_private.receipt_shares','SELECT'),'share secrets are private');
 result:=public.criar_compartilhamento_comprovante(p,repeat('a',64),photo_url,signature_url);
 PERFORM pg_temp.assert_receipt(result->>'sucesso'='true' AND (result->>'expira_em')::timestamptz BETWEEN now()+interval '54 minutes' AND now()+interval '56 minutes','manager creates limited lifetime share');
 PERFORM pg_temp.assert_receipt((SELECT token_hash=sha256(convert_to(repeat('a',64),'UTF8')) AND octet_length(token_hash)=32 FROM ec_private.receipt_shares WHERE entrega_id=p),'only token hash is persisted');
 result:=public.obter_comprovante_compartilhado(repeat('a',64));
 PERFORM pg_temp.assert_receipt(result->>'destinatario_nome'='CLIENT-A' AND result->>'recebedor_nome'='Pessoa A' AND result->>'foto_url'=photo_url AND result->>'assinatura_url'=signature_url,'share returns chosen receipt and exact media');
 PERFORM pg_temp.assert_receipt(NOT (result ?| ARRAY['motorista_id','registrado_por','token_hash','latitude','longitude','paradas','foto_path','assinatura_path']) AND result::text NOT LIKE '%CLIENT-B%','no unrelated operational or storage payload');
 PERFORM pg_temp.assert_receipt(public.obter_comprovante_compartilhado(p::text)->>'sucesso'='false' AND public.obter_comprovante_compartilhado(repeat('0',64))->>'sucesso'='false','UUID and guessed token expose nothing');
 PERFORM pg_temp.reject_receipt(format('SELECT public.criar_compartilhamento_comprovante(%L,%L,%L,%L)',p,'short',photo_url,signature_url),'Token inválido','short token rejected');
 PERFORM pg_temp.reject_receipt(format('SELECT public.criar_compartilhamento_comprovante(%L,%L,NULL,%L)',p,repeat('b',64),signature_url),'imagens temporárias','missing image URL rejected');
 PERFORM pg_temp.reject_receipt(format('SELECT public.criar_compartilhamento_comprovante(%L,%L,%L,%L)',p,repeat('b',64),replace(photo_url,p::text,q::text),signature_url),'imagens temporárias','another receipt image rejected');
 PERFORM pg_temp.reject_receipt(format('SELECT public.criar_compartilhamento_comprovante(%L,%L,%L,%L)',p,repeat('b',64),'https://test.supabase.co/storage/v1/object/public/entregas-comprovantes/'||photo,signature_url),'imagens temporárias','public object URL rejected');
 PERFORM pg_temp.reject_receipt(format('SELECT public.criar_compartilhamento_comprovante(%L,%L,%L,%L)',p,repeat('b',64),'javascript:alert(1)',signature_url),'imagens temporárias','unsafe URL rejected');
 PERFORM public.criar_compartilhamento_comprovante(q,repeat('b',64),NULL,NULL);
 PERFORM pg_temp.reject_receipt(format('SELECT public.criar_compartilhamento_comprovante(%L,%L,%L,%L)',p,repeat('b',64),photo_url,signature_url),'unique constraint','token collision rolls back atomically');
 PERFORM pg_temp.assert_receipt(public.obter_comprovante_compartilhado(repeat('a',64))->>'destinatario_nome'='CLIENT-A' AND public.obter_comprovante_compartilhado(repeat('b',64))->>'destinatario_nome'='CLIENT-B','collision preserves both previous shares');
 PERFORM set_config('request.jwt.claim.sub','bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb',true);
 PERFORM pg_temp.reject_receipt(format('SELECT public.criar_compartilhamento_comprovante(%L,%L,%L,%L)',p,repeat('c',64),photo_url,signature_url),'gestão da empresa','other company cannot create share');
 PERFORM pg_temp.reject_receipt(format('SELECT public.revogar_compartilhamento_comprovante(%L)',p),'gestão obrigatório','other company cannot revoke share');
 PERFORM pg_temp.assert_receipt(public.obter_comprovante_publico(p)->>'sucesso'='false','authenticated UUID lookup remains company scoped');
 PERFORM set_config('request.jwt.claim.sub','cccccccc-cccc-cccc-cccc-cccccccccccc',true);
 PERFORM pg_temp.reject_receipt(format('SELECT public.criar_compartilhamento_comprovante(%L,%L,%L,%L)',p,repeat('c',64),photo_url,signature_url),'gestão da empresa','driver cannot issue public shares');
 PERFORM set_config('request.jwt.claim.sub','',true);
 PERFORM pg_temp.reject_receipt(format('SELECT public.criar_compartilhamento_comprovante(%L,%L,%L,%L)',p,repeat('c',64),photo_url,signature_url),'gestão da empresa','anonymous cannot issue share');
 PERFORM pg_temp.reject_receipt(format('SELECT public.obter_comprovante_publico(%L)',p),'Entre na sua conta','no-auth UUID lookup blocked even as privileged connection');
 PERFORM set_config('request.jwt.claim.sub','aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',true);
 PERFORM public.criar_compartilhamento_comprovante(p,repeat('c',64),photo_url,signature_url);
 PERFORM pg_temp.assert_receipt(public.obter_comprovante_compartilhado(repeat('a',64))->>'sucesso'='false' AND public.obter_comprovante_compartilhado(repeat('c',64))->>'sucesso'='true','new share revokes old token');
 UPDATE ec_private.receipt_shares SET expires_at=now()-interval '1 second' WHERE entrega_id=p;
 PERFORM pg_temp.assert_receipt(public.obter_comprovante_compartilhado(repeat('c',64))->>'sucesso'='false','expired token exposes no receipt');
 UPDATE ec_private.receipt_shares SET expires_at=now()+interval '55 minutes' WHERE entrega_id=p;
 UPDATE public.empresas SET ativa=false WHERE id=company;
 PERFORM pg_temp.assert_receipt(public.obter_comprovante_compartilhado(repeat('c',64))->>'sucesso'='false','inactive company blocks sharing');
 UPDATE public.empresas SET ativa=true WHERE id=company;
 UPDATE public.empresa_membros SET status='suspenso' WHERE empresa_id=company AND user_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
 PERFORM pg_temp.assert_receipt(public.obter_comprovante_compartilhado(repeat('c',64))->>'sucesso'='false','suspended issuer cannot keep a public share');
 UPDATE public.empresa_membros SET status='aprovado' WHERE empresa_id=company AND user_id='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';
 UPDATE public.entrega_comprovantes SET foto_path=replace(photo,'foto.jpg','outra.jpg') WHERE entrega_id=p;
 PERFORM pg_temp.assert_receipt(public.obter_comprovante_compartilhado(repeat('c',64))->>'sucesso'='false','changed receipt media invalidates old share');
 UPDATE public.entrega_comprovantes SET foto_path=photo WHERE entrega_id=p;
 PERFORM public.revogar_compartilhamento_comprovante(p);
 PERFORM pg_temp.assert_receipt(public.obter_comprovante_compartilhado(repeat('c',64))->>'sucesso'='false' AND public.obter_comprovante_compartilhado(repeat('b',64))->>'sucesso'='true','revocation is limited to chosen receipt');
 -- Fresh token for the actual anonymous-role check below.
 PERFORM public.criar_compartilhamento_comprovante(p,repeat('d',64),photo_url,signature_url);
END $$;
GRANT SELECT ON storage.objects TO anon; -- Test RLS even if Storage grants table access.
SELECT set_config('request.jwt.claim.sub','',true);
SET LOCAL ROLE anon;
DO $$ BEGIN
 IF public.obter_comprovante_compartilhado(repeat('d',64))->>'destinatario_nome'<>'CLIENT-A' THEN RAISE EXCEPTION 'Anonymous token reader failed';END IF;
 IF EXISTS(SELECT FROM storage.objects WHERE bucket_id='entregas-comprovantes') THEN RAISE EXCEPTION 'Anonymous can list receipt images';END IF;
 BEGIN PERFORM public.obter_comprovante_publico('da100000-0000-0000-0000-000000000001');RAISE EXCEPTION 'Anonymous UUID endpoint executed'; EXCEPTION WHEN insufficient_privilege THEN NULL; END;
END $$;
RESET ROLE;
SELECT pg_temp.assert_receipt(true,'real anon role reads only token RPC, not object list or UUID endpoint');
SELECT count(*) AS receipt_sharing_passed FROM receipt_checks;
ROLLBACK;
