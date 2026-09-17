-- Painel de Inteligência Comercial — tabelas de configuração (as únicas escritas do painel)
-- Produção (leads, hubla_invoices etc.) é somente leitura. Dias em America/Manaus (-04, sem DST).

create table if not exists public.comercial_metas (
  mes date not null,                    -- 1º dia do mês
  chave text not null,                  -- elite|upsell|recorrente|ig_delta|ig_scv|playpassei|yt_scv|yt_ef|blindado|blog|pago
  valor numeric not null default 0,
  atualizado_por text,
  updated_at timestamptz not null default now(),
  primary key (mes, chave)
);

create table if not exists public.comercial_produto_categoria (
  product_hubla_id text primary key,
  product_name text,
  categoria text not null check (categoria in ('elite','upsell','recorrente','outros')),
  nome_canonico text,
  contest_code text,
  origem text not null default 'regex',   -- regex | manual
  validado boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.comercial_produto_turma (
  product_hubla_id text primary key,
  nome_canonico text not null,
  ano int,
  turma text,
  validado boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.comercial_vendedor_codigo (
  codigo text primary key,              -- lower(hubla_invoices.utm_term)
  nome text,
  tipo text not null check (tipo in ('vendedor','cs','ia','marketing','disparo','site')),
  validado boolean not null default false,
  updated_at timestamptz not null default now()
);

create table if not exists public.comercial_estrela_snapshot (
  gerado_em timestamptz not null default now(),
  contest_code text not null,
  total_leads bigint not null,
  score_pos bigint not null,
  faixa5 bigint not null, faixa4 bigint not null, faixa3 bigint not null, faixa2 bigint not null, faixa1 bigint not null,
  primary key (gerado_em, contest_code)
);

create table if not exists public.comercial_snapshot_diario (
  dia date primary key,
  gerado_em timestamptz not null default now(),
  payload jsonb not null
);

revoke all on public.comercial_metas, public.comercial_produto_categoria, public.comercial_produto_turma,
  public.comercial_vendedor_codigo, public.comercial_estrela_snapshot, public.comercial_snapshot_diario
  from anon, authenticated;

-- Seeds -----------------------------------------------------------------------------------------
-- Categoria por regex de nome (reproduz o protótipo de 16/09 ao centavo: Elite 393 · Upsell 45 · Recorrente 60 · outros 64 = 562)
create or replace function public.fn_comercial_categoria_nome(p_name text) returns text
language sql immutable as $$
  select case
    when p_name ~* 'DIAMANTE' then 'upsell'
    when p_name ~* '^\s*ELITE' then 'elite'
    when p_name ~* 'PLAY ?PASSEI|SOU QUEST|^\s*PÓS GRADUAÇÃO' then 'recorrente'
    else 'outros' end
$$;

insert into public.comercial_produto_categoria (product_hubla_id, product_name, categoria, nome_canonico)
select product_hubla_id, max(product_name), public.fn_comercial_categoria_nome(max(product_name)),
       upper(regexp_replace(trim(max(product_name)), '\s+', ' ', 'g'))
from public.hubla_invoices where product_hubla_id is not null
group by product_hubla_id
on conflict (product_hubla_id) do nothing;

-- Único de-para de turma confirmado (briefing §5.7): ELITE PRF 2025 → ELITE PRF - ATÉ A PROVA 2026
insert into public.comercial_produto_turma (product_hubla_id, nome_canonico, ano, validado)
values ('C0E4x5MMPQrsCXQ16xA0', 'ELITE PRF - ATÉ A PROVA', 2026, true)
on conflict do nothing;

-- Códigos de utm_term observados desde jun/2026 (nome a preencher no painel; validado=false até a Mariane confirmar)
insert into public.comercial_vendedor_codigo (codigo, tipo) values
 ('tha','vendedor'),('tai','vendedor'),('lua','vendedor'),('wel','vendedor'),('kam_is','vendedor'),('leo_is','vendedor'),
 ('orl','vendedor'),('com_uni','vendedor'),('vit_is','vendedor'),
 ('mir_cs','cs'),('isa_cs','cs'),('car_cs','cs'),('ism_cs','cs'),('vit_cs','cs'),
 ('ia','ia'),('anneia','ia'),('anne-ia-recuperacao','ia'),
 ('mkt','marketing'),('desconto_alunos','marketing'),('grupo sil','marketing'),
 ('disparo_matricula','disparo'),('d_matricula1','disparo'),
 ('site','site'),('pagina_lovable','site'),('unificado','site'),('typebot','site')
on conflict do nothing;

-- canal_map: souwebinario era classificado como 'desconhecido' (850 leads em set/26)
insert into public.canal_map (prioridade, padrao_source, padrao_medium, canal, subcanal, obs)
select 5, '^souwebinario', null, 'webinario', 'sou_webinario', 'painel comercial 17/09: first_origin souwebinario'
where not exists (select 1 from public.canal_map where padrao_source = '^souwebinario');
