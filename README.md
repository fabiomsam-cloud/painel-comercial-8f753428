# Painel de Inteligência Comercial · Grupo SOU

Painel vivo construído a partir do protótipo da Head do Comercial (`../index.html` + `../BRIEFING-PLATAFORMA.md`).
Padrão da casa: `index.html` único no GitHub Pages + edge function no SOU Data Core + token `?k=` na URL.

## Acesso
Central de Operações (hub-sou): card 07 aponta para este painel; publicar a Central é decisão do Fábio.

`https://fabiomsam-cloud.github.io/painel-comercial-8f753428/?k=<token>` — o token está em `.token.local` (não versionado).
Sem token a página mostra "Acesso restrito". Rotacionar = trocar a constante `TOKEN` nas duas edges (`dashboard-comercial`
no Data Core e `comercial-anne` na Anne), redeployar e passar o link novo.

## Arquitetura
```
index.html ── GET ?k=&ini=&fim=&superior=&contest= ──▶ dashboard-comercial (Data Core, service role)
                                                         ├─ rpc fn_comercial_vendas (3 janelas: atual, MoM, YoY — mesmo recorte de dias)
                                                         ├─ comercial_metas / comercial_produto_categoria (config do painel)
                                                         └─ fetch comercial-anne?k= (projeto Anne) — cruzamento por lead_id
index.html ── POST ?k=&resource=metas {mes, chave, valor, por} ──▶ upsert comercial_metas (única escrita)
```
- Filtro **Total / Venda Nova / Parcela** é aplicado no front sobre linhas taggeadas `tipo_fatura` (regra em `fn_comercial_tipo_fatura`).
- Filtros de período, escolaridade e concurso vão ao servidor. Dias em `America/Manaus` (−04).
- Receita = `net_value` (líquida). Produto agrupado por `product_hubla_id`; categoria em `comercial_produto_categoria` (editável).

## Pastas
- `supabase/migrations/` — SQL versionado aplicado no Data Core (tabelas `comercial_*`, `fn_comercial_*`).
- `edge/supabase/functions/dashboard-comercial/` — edge do Data Core (deploy: MCP `deploy_edge_function` ou `supabase functions deploy` de dentro de `edge/`).
- `anne/functions/comercial-anne/` e `anne/migrations/` — lado Anne.

## Deploy do front
`git push origin main` → GitHub Pages publica em ~1 min.

## Fases
1. ✅ Fundação (16/09/2026): repo, tabelas de config, edges, navegação, filtros, KPIs, ritmo por categoria, metas compartilhadas.
2. ✅ Receita (16/09): seções 4, 5, 6 (matriculados; inscritos/engajados nas fases 3–4), 7B, 8, 10; CSV em toda tabela; cupons 90d (`fn_comercial_cupons_90d`); seção 5 usa `sales.attribution` da Anne quando existe.
3. ✅ Demanda (16/09): `fn_comercial_leads` (1 linha por lead: rótulo 1.1, ação 1.2, concursos, escolaridade, sinais de engajamento do Data Core, matriculado) + `fn_comercial_meta_spend`; tela Demanda (1.1 com metas/MoM/gráfico da mesma query, 1.2 com alerta VSL vivo, 1.3), KPI de inscritos, filtro ensino superior (pesquisa → campaign_events → cadastro; só completo/pós), seletor de concurso, seção 6 com inscritos e engajados parciais.
4. ✅ Engajamento + Anne (16/09): `fn_comercial_anne_contatos` (Anne) → `comercial-anne` devolve contatos dos leads do período; a edge do Data Core une por `lead_id` (`fundirAnne`), fecha engajado/ativo 7d e NÃO manda telefone ao navegador; `resource=lista_nao_matriculados` = CSV nominal (confidencial); ref. A via `comercial_estrela_snapshot` (pg_cron `comercial-estrela-diario` 07:00 UTC = 03:00 Manaus, dedup por lead → PRF 34% na faixa máxima); seção 6 completa.
5. ✅ Time comercial + financeiro (16/09): `fn_comercial_anne_comercial(p_ini,p_fim)` (Anne, jsonb único: 9A por vendedor, 9B fora do pipeline, 9C escalations.claimed_by, motivos de perda, broadcast + vendas ≤10d pós-disparo); telas Time comercial e Financeiro (Meta por conta, CAC piso, ROAS, CPL, disparos). 6. ✅ Acabamento (16/09): tela Configuração com de-paras editáveis (`resource=config` GET/POST: produto→categoria/concurso/validado, código utm_term→nome/tipo), glossário completo, números com separador, ids únicos. Card 07 adicionado ao hub-sou LOCAL (a Central ainda não está publicada — repo `sou-central-7b3e91d4` não existe no GitHub).

## Validação (janela fechada 01–15/09/2026 × 2025)
Total 562 faturas / R$ 178.014,19 · 2025: 419 / R$ 298.401,52 · Elite/Upsell/Recorrente nova 132/1/39 e parcela 261/44/21 (iguais ao protótipo).
Seção 4: 97/84/20/17/8/2/1 = 229 (exato). Seção 5: Anne IA 57 · Vendedor 49 · Marketing 47 · CS 6 · Blindado 3 · Disparo 1 (exato); os códigos `plataforma`/`checkout` foram para Site (protótipo somava em Venda Direta) — ajustável em `comercial_vendedor_codigo`. 7B: produto a produto igual ao protótipo.
Inscritos 01–15/09 = 1.593 (exato). 1.1: @souconcurseiro 75 · @deltafabio 16 · pago 180 · blindado 146 · YouTube 33 (protótipo 75/16/179/149/30). Engajados Data Core 753 (protótipo 754). Fase 4 (01–16/09): engajados 826 (protótipo 813/869), ativos 7d 406 (protótipo 440), estrela PRF 2.591 pontuados / 875 (34%) na faixa máxima — o 54% do protótipo era dupla contagem.
Vendas novas 220 vs 221 do protótipo: a diferença é 1 fatura `invoice_type = 'Renovação'` (R$ 7,05) que a regra do briefing exclui.
