-- fn_canal_utm devolve json {canal, subcanal}: expor os dois como texto; códigos de site que faltavam
insert into public.comercial_vendedor_codigo (codigo, tipo) values ('plataforma','site'),('checkout','site'),('upsell','site') on conflict do nothing;

drop function if exists public.fn_comercial_vendas(date,date,boolean,text);
create or replace function public.fn_comercial_vendas(p_ini date, p_fim date, p_superior boolean default false, p_contest text default null)
returns table (
  invoice_id text, dia date, tipo_fatura text, categoria text, product_hubla_id text, product_name text, nome_canonico text,
  net_value numeric, total_value numeric, product_value numeric, discount_value numeric, coupon text,
  lead_id uuid, first_origin text, canal_entrada text, canal_lead text, subcanal_lead text, placement_meta boolean,
  utm_term text, utm_source text, utm_campaign text, canal_venda_codigo text, sinal_disparo boolean
) language sql stable as $$
  with f as (
    select i.*, (i.paid_at at time zone 'America/Manaus')::date as dia_manaus
    from public.hubla_invoices i
    where i.status = 'Paga'
      and (i.paid_at at time zone 'America/Manaus')::date between p_ini and p_fim
  ), x as (
    select f.*, l.first_origin as l_origin, l.first_utm_source as l_source,
           public.fn_canal_utm(l.first_utm_source, l.first_utm_medium, l.first_origin)::jsonb as cj
    from f left join public.leads l on l.id = f.lead_id
  )
  select x.invoice_id, x.dia_manaus,
         public.fn_comercial_tipo_fatura(x.original_invoice_id, x.smart_installment_current, x.refunded_at, x.invoice_type),
         coalesce(c.categoria, public.fn_comercial_categoria_nome(x.product_name)),
         x.product_hubla_id, x.product_name, coalesce(c.nome_canonico, upper(trim(x.product_name))),
         x.net_value, x.total_value, x.product_value, x.discount_value, x.coupon,
         x.lead_id, x.l_origin,
         case when x.lead_id is null then 'sem_lead'
              when x.l_origin like 'import%' then 'base_historica'
              when x.l_origin = 'hubla' then 'nasceu_na_compra'
              else coalesce(x.l_origin, 'desconhecido') end,
         case when x.lead_id is null then 'sem_lead' else coalesce(x.cj->>'canal', 'desconhecido') end,
         x.cj->>'subcanal',
         coalesce(x.l_source ~* '^(instagram|facebook)_|leadads', false),
         x.utm_term, x.utm_source, x.utm_campaign,
         case when v.tipo = 'ia' then 'anne_ia'
              when v.tipo = 'cs' then 'atendente_cs'
              when v.tipo = 'vendedor' then 'vendedor'
              when v.tipo = 'marketing' then 'marketing'
              when v.tipo = 'disparo' then 'disparo'
              when v.tipo = 'site' then 'site'
              when x.utm_term is null or x.utm_term ~* '^(instagram|facebook)_|typebot|others|^pv\d|^\[vd\]|undefined' then 'venda_direta_checkout'
              else 'codigo_desconhecido' end,
         coalesce(x.utm_source ~* 'ataque|disparo', false)
  from x
  left join public.comercial_produto_categoria c on c.product_hubla_id = x.product_hubla_id
  left join public.comercial_vendedor_codigo v on v.codigo = lower(x.utm_term)
  where (p_contest is null or c.contest_code = p_contest)
$$;
revoke all on function public.fn_comercial_vendas(date,date,boolean,text) from anon, authenticated;
