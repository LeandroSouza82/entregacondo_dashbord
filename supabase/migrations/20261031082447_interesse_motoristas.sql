-- Separate marketing interest from operational driver accounts and approvals.
create table public.interesse_motoristas_admins (
  user_id uuid primary key references auth.users(id) on delete cascade
);
alter table public.interesse_motoristas_admins enable row level security;
revoke all on public.interesse_motoristas_admins from anon, authenticated;
grant select on public.interesse_motoristas_admins to authenticated;
create policy interesse_admin_self on public.interesse_motoristas_admins
  for select to authenticated using (user_id = (select auth.uid()));
insert into public.interesse_motoristas_admins(user_id)
select id from auth.users where email in ('leandro_ditamar@yahoo.com.br','leandrinhoditamar@gmail.com');

create table public.interesse_motoristas (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (char_length(nome) between 2 and 100),
  email text not null unique check (email = lower(btrim(email)) and char_length(email) <= 254 and email ~ '^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$'),
  cidade text not null check (char_length(cidade) between 2 and 100),
  uf text not null check (uf in ('AC','AL','AP','AM','BA','CE','DF','ES','GO','MA','MT','MS','MG','PA','PB','PR','PE','PI','RJ','RN','RS','RO','RR','SC','SP','SE','TO')),
  veiculo text check (veiculo is null or veiculo in ('moto','carro','bicicleta','van','outro')),
  consentimento boolean not null check (consentimento),
  consentimento_versao text not null default '2026-10-31',
  origem text not null default 'site-motoristas',
  email_confirmado boolean not null default false,
  created_at timestamptz not null default now()
);
create index interesse_motoristas_created_idx on public.interesse_motoristas(created_at desc);
alter table public.interesse_motoristas enable row level security;
revoke all on public.interesse_motoristas from anon, authenticated;
grant select, delete on public.interesse_motoristas to authenticated;
create policy interesse_owner_read on public.interesse_motoristas for select to authenticated
using (exists(select 1 from public.interesse_motoristas_admins a where a.user_id=(select auth.uid())));
create policy interesse_owner_delete on public.interesse_motoristas for delete to authenticated
using (exists(select 1 from public.interesse_motoristas_admins a where a.user_id=(select auth.uid())));

create table public.interesse_motoristas_limites (
  chave text primary key,
  janela timestamptz not null,
  tentativas integer not null check (tentativas > 0)
);
alter table public.interesse_motoristas_limites enable row level security;
revoke all on public.interesse_motoristas_limites from anon, authenticated;
grant all on public.interesse_motoristas, public.interesse_motoristas_admins, public.interesse_motoristas_limites to service_role;

-- Called only by the Edge Function with its server credential. No definer bypass.
create function public.registrar_interesse_motorista(
 p_nome text,p_email text,p_cidade text,p_uf text,p_veiculo text,p_chave text
) returns void language plpgsql security invoker set search_path='' as $$
declare v_tentativas integer;
begin
 if p_chave !~ '^[0-9a-f]{64}$' then raise exception 'invalid_key'; end if;
 delete from public.interesse_motoristas_limites where janela < now()-interval '2 days';
 insert into public.interesse_motoristas_limites as l(chave,janela,tentativas)
 values(p_chave,now(),1)
 on conflict(chave) do update set
 tentativas=case when l.janela < now()-interval '1 hour' then 1 else l.tentativas+1 end,
 janela=case when l.janela < now()-interval '1 hour' then now() else l.janela end
 returning tentativas into v_tentativas;
 if v_tentativas > 10 then raise exception 'rate_limit'; end if;
 insert into public.interesse_motoristas(nome,email,cidade,uf,veiculo,consentimento)
 values(btrim(p_nome),lower(btrim(p_email)),btrim(p_cidade),upper(p_uf),p_veiculo,true)
 on conflict(email) do nothing;
end; $$;
revoke all on function public.registrar_interesse_motorista(text,text,text,text,text,text) from public,anon,authenticated;
grant execute on function public.registrar_interesse_motorista(text,text,text,text,text,text) to service_role;
