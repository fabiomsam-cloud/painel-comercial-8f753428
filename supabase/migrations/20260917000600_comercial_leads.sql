-- Fase 3: leads do período (1 linha por lead) — alimenta 1.1, 1.2, 1.3, 2, 3, 6 e o KPI de inscritos.
-- Universo oficial de "inscritos": leads.created_at em dia-calendário Manaus, excluindo importações (first_origin like 'import%').

-- Escolaridade: pesquisa (survey_answers) → campaign_events.raw_payload.escolaridade → leads.raw_payload.escolaridade
create or replace function public.fn_comercial_escolaridade(p_txt text) returns text language sql immutable as $$
  select case when p_txt is null or btrim(p_txt) = '' then null
              when p_txt ~* 'p[oó]s' then 'pos'
              when p_txt ~* 'superior' and p_txt ~* 'curs' then 'superior_cursando'
              when p_txt ~* 'superior' then 'superior_completo'
              when p_txt ~* 'm[eé]dio' then 'medio'
              when p_txt ~* 'fundamental' then 'fundamental'
              else 'outro' end
$$;

-- Ação/evento de entrada (1.2) — ordem EXCLUDENTE definida pela Head; sem join com funnels (fan-out).
-- Direct Response = a palavra VSL na campanha ([VD] NÃO significa venda direta). Venda Direta = tráfego pago sem VSL.
create or replace function public.fn_comercial_acao(p_origin text, p_campaign text, p_canal text) returns text language sql immutable as $$
  select case
    when p_origin in ('souwebinario','hotwebinar') or p_campaign ~* 'web[ie]?n[aá]rio' then 'webinario'
    when p_campaign ~* 'estudecomigo|estude-comigo|_ec_|nutricao-.*-aula' or p_origin = 'sendflow_grupo' then 'estude_comigo'
    when p_campaign ~* 'lan[cç]amento' then 'lancamento'
    when p_campaign ~* 'vsl' then 'direct_response'
    when p_canal in ('meta_ads','google_ads','youtube_ads') then 'venda_direta'
    when p_origin in ('checkout_blindado','redirect_anne') then 'site_direto'
    else 'outro_nao_mapeado' end
$$;

-- Rótulos fixos da 1.1 (8 canais); null = fora dos 8 (conta só no total de inscritos)
create or replace function public.fn_comercial_label_11(p_origin text, p_source text, p_canal text, p_subcanal text) returns text language sql immutable as $$
  select case
    when p_source ~* 'playpassei' then 'playpassei'
    when p_source ~* 'elite.?federal' then 'yt_ef'
    when p_source ~* '^instagram-souconcurseiro' then 'ig_scv'
    when p_origin = 'bio_deltafabiosilva' or p_subcanal in ('bio_delta','dm_delta') then 'ig_delta'
    when p_source ~* '^youtube' then 'yt_scv'
    when p_subcanal ~* 'blog' then 'blog'
    when p_origin = 'checkout_blindado' then 'blindado'
    when p_canal in ('meta_ads','google_ads','youtube_ads') then 'pago'
    else null end
$$;

create or replace function public.fn_comercial_leads(p_ini date, p_fim date, p_superior boolean default false, p_contest text default null, p_export boolean default false)
returns table (
  lead_id uuid, dia date, first_origin text, canal text, subcanal text, label_11 text, acao text,
  contests text[], n_contests int, escolaridade text, superior boolean,
  sig_score boolean, sig_survey boolean, sig_grupo boolean, sig_webinar boolean, sig_pitch boolean,
  ativo_webinar_7d boolean, ativo_grupo_7d boolean, matriculado boolean,
  nome text, telefone text, email text
) language sql stable as $$
  with l as (
    select l.id, (l.created_at at time zone 'America/Manaus')::date as dia, l.first_origin, l.first_utm_source, l.first_utm_campaign,
           l.name, l.phone, l.email, l.raw_payload,
           public.fn_canal_utm(l.first_utm_source, l.first_utm_medium, l.first_origin)::jsonb as cj
    from public.leads l
    where l.created_at >= (p_ini::timestamp at time zone 'America/Manaus')
      and l.created_at <  ((p_fim + 1)::timestamp at time zone 'America/Manaus')
      and coalesce(l.first_origin,'') not like 'import%'
  ), ct as (
    select x.lead_id, array_agg(distinct c.code order by c.code) as codes
    from (select li.lead_id, li.contest_id from public.lead_interests li join l on l.id = li.lead_id
          union select w.lead_id, w.contest_id from public.webinar_events w join l on l.id = w.lead_id) x
    join public.contests c on c.id = x.contest_id
    group by x.lead_id
  ), esc as (
    select l.id,
      coalesce(
        (select case when bool_or(sa.has_higher_education) then 'superior_completo' when bool_and(sa.has_higher_education = false) then 'medio' end
           from public.survey_answers sa where sa.lead_id = l.id and sa.has_higher_education is not null),
        (select public.fn_comercial_escolaridade(max(ce.raw_payload->>'escolaridade')) from public.campaign_events ce
           where ce.lead_id = l.id and coalesce(ce.raw_payload->>'escolaridade','') <> ''),
        public.fn_comercial_escolaridade(coalesce(l.raw_payload->>'escolaridade', l.raw_payload->>'ESCOLARIDADE'))
      ) as escolaridade
    from l
  ), sig as (
    select l.id,
      exists (select 1 from public.lead_interests li where li.lead_id = l.id and li.score > 0) as sig_score,
      exists (select 1 from public.survey_answers sa where sa.lead_id = l.id) as sig_survey,
      exists (select 1 from public.group_events ge where ge.lead_id = l.id and (ge.entered or ge.answered_survey)) as sig_grupo,
      exists (select 1 from public.webinar_events w where w.lead_id = l.id and (w.attended or w.clicked_link)) as sig_webinar,
      exists (select 1 from public.webinar_events w where w.lead_id = l.id and w.reached_pitch) as sig_pitch,
      exists (select 1 from public.webinar_events w where w.lead_id = l.id
              and ((w.entered_at at time zone 'America/Manaus')::date >= p_fim - 6 or (w.clicked_checkout_at at time zone 'America/Manaus')::date >= p_fim - 6)) as ativo_webinar_7d,
      exists (select 1 from public.group_events ge where ge.lead_id = l.id and ge.left_at is null
              and (ge.entered_at at time zone 'America/Manaus')::date >= p_fim - 6) as ativo_grupo_7d,
      (exists (select 1 from public.hubla_invoices i where i.lead_id = l.id and i.status = 'Paga'
               and public.fn_comercial_tipo_fatura(i.original_invoice_id, i.smart_installment_current, i.refunded_at, i.invoice_type) = 'nova'
               and (i.paid_at at time zone 'America/Manaus')::date <= p_fim)
       or (l.email is not null and exists (select 1 from public.hubla_invoices i where lower(i.customer_email) = lower(l.email) and i.status = 'Paga'
               and public.fn_comercial_tipo_fatura(i.original_invoice_id, i.smart_installment_current, i.refunded_at, i.invoice_type) = 'nova'
               and (i.paid_at at time zone 'America/Manaus')::date <= p_fim))
       or exists (select 1 from public.orders_elite oe where oe.lead_id = l.id and oe.payment_status = 'paid')) as matriculado
    from l
  )
  select l.id, l.dia, l.first_origin, l.cj->>'canal', l.cj->>'subcanal',
         public.fn_comercial_label_11(l.first_origin, l.first_utm_source, l.cj->>'canal', l.cj->>'subcanal'),
         public.fn_comercial_acao(l.first_origin, l.first_utm_campaign, l.cj->>'canal'),
         coalesce(ct.codes, '{}'::text[]), coalesce(array_length(ct.codes, 1), 0),
         esc.escolaridade, case when esc.escolaridade is null then null else esc.escolaridade in ('superior_completo','pos') end,
         sig.sig_score, sig.sig_survey, sig.sig_grupo, sig.sig_webinar, sig.sig_pitch, sig.ativo_webinar_7d, sig.ativo_grupo_7d, sig.matriculado,
         case when p_export then l.name end, case when p_export then l.phone end, case when p_export then l.email end
  from l
  left join ct on ct.lead_id = l.id
  join esc on esc.id = l.id
  join sig on sig.id = l.id
  where (not p_superior or esc.escolaridade in ('superior_completo','pos'))
    and (p_contest is null or p_contest = any(coalesce(ct.codes, '{}'::text[])))
$$;
revoke all on function public.fn_comercial_leads(date,date,boolean,text,boolean) from anon, authenticated;

-- Gasto Meta por campanha × dia (seção 11 e alerta da VSL na 1.2)
create or replace function public.fn_comercial_meta_spend(p_ini date, p_fim date)
returns table (dia date, ad_account_name text, campaign_id text, campaign_name text, spend numeric, clicks bigint, impressions bigint)
language sql stable as $$
  select period_start, ad_account_name, campaign_id, max(campaign_name), sum(spend), sum(clicks), sum(impressions)
  from public.meta_ads_insights
  where granularity = 'daily' and period_start between p_ini and p_fim
  group by period_start, ad_account_name, campaign_id
$$;
revoke all on function public.fn_comercial_meta_spend(date,date) from anon, authenticated;
