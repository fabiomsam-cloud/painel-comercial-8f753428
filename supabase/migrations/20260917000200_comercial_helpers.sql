-- Helpers do painel comercial (todos stable/immutable, somente leitura)

-- Venda nova × parcela — a regra mais importante (briefing §4.1)
create or replace function public.fn_comercial_tipo_fatura(
  p_original_invoice_id text, p_smart_installment_current int, p_refunded_at timestamptz, p_invoice_type text
) returns text language sql immutable as $$
  select case when p_original_invoice_id is null
               and coalesce(p_smart_installment_current, 1) = 1
               and p_refunded_at is null
               and p_invoice_type = 'Compra' then 'nova' else 'parcela' end
$$;

-- Faturas pagas do período, 1 linha por fatura (alimenta KPIs, 4, 5, 7, 8, 10, 11)
create or replace function public.fn_comercial_vendas(p_ini date, p_fim date, p_superior boolean default false, p_contest text default null)
returns table (
  invoice_id text, dia date, tipo_fatura text, categoria text, product_hubla_id text, product_name text, nome_canonico text,
  net_value numeric, total_value numeric, product_value numeric, discount_value numeric, coupon text,
  lead_id uuid, first_origin text, canal_entrada text, canal_lead text, placement_meta boolean,
  utm_term text, utm_source text, utm_campaign text, canal_venda_codigo text, sinal_disparo boolean
) language sql stable as $$
  with f as (
    select i.*, (i.paid_at at time zone 'America/Manaus')::date as dia_manaus
    from public.hubla_invoices i
    where i.status = 'Paga'
      and (i.paid_at at time zone 'America/Manaus')::date between p_ini and p_fim
  )
  select f.invoice_id, f.dia_manaus,
         public.fn_comercial_tipo_fatura(f.original_invoice_id, f.smart_installment_current, f.refunded_at, f.invoice_type),
         coalesce(c.categoria, public.fn_comercial_categoria_nome(f.product_name)),
         f.product_hubla_id, f.product_name, coalesce(c.nome_canonico, upper(trim(f.product_name))),
         f.net_value, f.total_value, f.product_value, f.discount_value, f.coupon,
         f.lead_id, l.first_origin,
         case when f.lead_id is null then 'sem_lead'
              when l.first_origin like 'import%' then 'base_historica'
              when l.first_origin = 'hubla' then 'nasceu_na_compra'
              else coalesce(l.first_origin, 'desconhecido') end,
         public.fn_canal_utm(l.first_utm_source, l.first_utm_medium, l.first_origin),
         coalesce(l.first_utm_source ~* '^(instagram|facebook)_|leadads', false),
         f.utm_term, f.utm_source, f.utm_campaign,
         case when v.tipo = 'ia' then 'anne_ia'
              when v.tipo = 'cs' then 'atendente_cs'
              when v.tipo = 'vendedor' then 'vendedor'
              when v.tipo = 'marketing' then 'marketing'
              when v.tipo = 'disparo' then 'disparo'
              when v.tipo = 'site' then 'site'
              when f.utm_term is null or f.utm_term ~* '^(instagram|facebook)_|typebot|others|^pv\d|^\[vd\]|undefined' then 'venda_direta_checkout'
              else 'codigo_desconhecido' end,
         coalesce(f.utm_source ~* 'ataque|disparo', false)
  from f
  left join public.leads l on l.id = f.lead_id
  left join public.comercial_produto_categoria c on c.product_hubla_id = f.product_hubla_id
  left join public.comercial_vendedor_codigo v on v.codigo = lower(f.utm_term)
  where (p_contest is null or c.contest_code = p_contest)
$$;
revoke all on function public.fn_comercial_vendas(date,date,boolean,text) from anon, authenticated;
