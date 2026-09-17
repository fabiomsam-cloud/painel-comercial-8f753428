// Painel de Inteligência Comercial — edge no SOU Data Core (dqpxugdhlgafvddavzzp)
// Token no ?k= (rotacionar = trocar aqui + no index.html do repo painel-comercial-*).
// Fuso: dias SEMPRE em America/Manaus (-04, sem DST). Receita = net_value (líquida).
// Somente leitura em produção; escreve apenas em comercial_metas (resource=metas).
// Cruzamento com a Anne: fetch na edge comercial-anne (mesmo token), chave lead_id (fallback telefone DDD+8).
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const TOKEN = "com-sou-byMernuvTjwl28hb";
const ANNE_URL = "https://blwbbdcwdcwitsnskplk.supabase.co/functions/v1/comercial-anne";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (obj: unknown, status = 200) =>
  new Response(JSON.stringify(obj), {
    status, headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" },
  });

// Dia calendário de Manaus (offset fixo -04:00)
const hojeManaus = () => new Date(Date.now() - 4 * 3600_000).toISOString().slice(0, 10);
const ymd = (d: Date) => d.toISOString().slice(0, 10);
const addMonths = (s: string, n: number) => {           // mantém o dia-do-mês, trunca ao último dia do mês-alvo
  const [y, m, d] = s.split("-").map(Number);
  const alvo = new Date(Date.UTC(y, m - 1 + n, 1));
  const ultimo = new Date(Date.UTC(alvo.getUTCFullYear(), alvo.getUTCMonth() + 1, 0)).getUTCDate();
  return ymd(new Date(Date.UTC(alvo.getUTCFullYear(), alvo.getUTCMonth(), Math.min(d, ultimo))));
};
const isYmd = (s: string | null) => !!s && /^\d{4}-\d{2}-\d{2}$/.test(s);

// PostgREST corta em 1000 linhas POR REQUISIÇÃO — paginar SEMPRE (gotcha da casa)
// deno-lint-ignore no-explicit-any
async function fetchAll(build: (from: number, to: number) => any, cap = 100000) {
  const PAGE = 1000; const rows: unknown[] = [];
  for (let from = 0; from < cap; from += PAGE) {
    const { data, error } = await build(from, from + PAGE - 1);
    if (error) throw new Error(error.message);
    rows.push(...(data ?? []));
    if (!data || data.length < PAGE) break;
  }
  return rows;
}

async function vendas(db: SupabaseClient, ini: string, fim: string, superior: boolean, contest: string | null) {
  return await fetchAll((a, b) =>
    db.rpc("fn_comercial_vendas", { p_ini: ini, p_fim: fim, p_superior: superior, p_contest: contest }).range(a, b));
}

async function leads(db: SupabaseClient, ini: string, fim: string, superior: boolean, contest: string | null) {
  return await fetchAll((a, b) =>
    db.rpc("fn_comercial_leads", { p_ini: ini, p_fim: fim, p_superior: superior, p_contest: contest, p_export: false })
      .select("lead_id, dia, first_origin, canal, subcanal, label_11, acao, contests, n_contests, escolaridade, superior, sig_score, sig_survey, sig_grupo, sig_webinar, sig_pitch, ativo_webinar_7d, ativo_grupo_7d, matriculado")
      .range(a, b));
}

// deno-lint-ignore no-explicit-any
type Row = Record<string, any>;
// Une os contatos da Anne aos leads do período por lead_id (99,8% dos contatos têm o lead do Data Core em source_first).
// Fecha "engajado" (≥1 sinal real) e "ativo 7d" (sinal nos últimos 7 dias) — definição operacional do briefing §5.2.
function fundirAnne(leads: Row[], contatos: Row[], fim: string) {
  const byLead = new Map<string, Row>();
  for (const c of contatos) if (c.lead_id) { const prev = byLead.get(c.lead_id); if (!prev || (c.msg_user ?? 0) > (prev.msg_user ?? 0)) byLead.set(c.lead_id, c); }
  const corte = Date.parse(fim + "T04:00:00.000Z") - 6 * 86400e3; // fim-6 dias, 00:00 Manaus
  let batidos = 0;
  for (const l of leads) {
    const c = byLead.get(l.lead_id);
    l.anne_msgs = c ? (c.msg_user ?? 0) : 0;
    l.anne_status = c ? (c.status ?? null) : null;
    l.anne_batido = !!c; if (c) batidos++;
    const ultima = c?.last_user_message_at ? Date.parse(c.last_user_message_at) : 0;
    l.anne_ativo_7d = !!c && ultima >= corte && !["dormant", "opted_out"].includes(c.status ?? "");
    l.engajado = !!(l.sig_score || l.sig_survey || l.sig_grupo || l.sig_webinar || l.anne_msgs >= 2);
    l.ativo_7d = !!(l.ativo_webinar_7d || l.ativo_grupo_7d || l.anne_ativo_7d);
  }
  return batidos;
}

async function anne(ini: string, fim: string) {
  try {
    const r = await fetch(`${ANNE_URL}?k=${TOKEN}&ini=${ini}&fim=${fim}`);
    if (!r.ok) return { ok: false, error: `HTTP ${r.status}` };
    return { ok: true, ...(await r.json()) };
  } catch (e) { return { ok: false, error: String(e) }; }
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const url = new URL(req.url);
  if ((url.searchParams.get("k") ?? "") !== TOKEN) return json({ error: "unauthorized" }, 401);

  const db = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);

  const hoje = hojeManaus();
  const iniQ = url.searchParams.get("ini"), fimQ = url.searchParams.get("fim");
  const ini = isYmd(iniQ) ? iniQ! : hoje.slice(0, 8) + "01";
  const fim = isYmd(fimQ) ? fimQ! : hoje;
  const superior = url.searchParams.get("superior") === "1";
  const contest = url.searchParams.get("contest") || null;
  const mes = ini.slice(0, 8) + "01";

  // ---- SEÇÃO 3: lista nominal (CSV) de engajados não matriculados — CONFIDENCIAL, só com o token ----
  if (url.searchParams.get("resource") === "lista_nao_matriculados") {
    try {
      const [ls, an] = await Promise.all([
        fetchAll((a, b) => db.rpc("fn_comercial_leads", { p_ini: ini, p_fim: fim, p_superior: superior, p_contest: contest, p_export: true }).range(a, b)),
        anne(ini, fim),
      ]);
      fundirAnne(ls as Row[], (an as Row).contatos ?? [], fim);
      const rows = (ls as Row[]).filter((l) => l.engajado && !l.matriculado);
      const esc = (v: unknown) => { const t = String(v ?? ""); return /[;"\n]/.test(t) ? '"' + t.replace(/"/g, '""') + '"' : t; };
      const head = ["nome", "telefone", "email", "concursos", "dia_cadastro", "origem", "acao", "escolaridade", "sinais", "anne_status", "anne_msgs_lead"];
      const csv = "\ufeff" + head.join(";") + "\n" + rows.map((l) => [l.nome, l.telefone, l.email, (l.contests ?? []).join("|"), l.dia, l.first_origin, l.acao, l.escolaridade,
        [l.sig_webinar && "webinar", l.sig_pitch && "pitch", l.sig_grupo && "grupo", l.sig_survey && "pesquisa", l.sig_score && "score", l.anne_msgs >= 2 && "anne"].filter(Boolean).join("|"),
        l.anne_status, l.anne_msgs].map(esc).join(";")).join("\n");
      return new Response(csv, { headers: { ...corsHeaders, "Content-Type": "text/csv; charset=utf-8", "Content-Disposition": `attachment; filename="engajados_nao_matriculados_${ini}_a_${fim}.csv"`, "Cache-Control": "no-store" } });
    } catch (e) { return json({ error: String(e) }, 500); }
  }

  // ---- CONFIG: de-paras editáveis (produto→categoria/concurso, código utm_term→vendedor). GET lista · POST atualiza e devolve a lista ----
  if (url.searchParams.get("resource") === "config") {
    try {
      if (req.method === "POST") {
        const b = await req.json().catch(() => ({}));
        const por = String(b?.por ?? "").slice(0, 80);
        if (b?.tipo === "produto") {
          const id = String(b?.product_hubla_id ?? ""); if (!id) return json({ error: "id_obrigatorio" }, 400);
          const categoria = String(b?.categoria ?? ""); if (!["elite", "upsell", "recorrente", "outros"].includes(categoria)) return json({ error: "categoria_invalida" }, 400);
          const contest = b?.contest_code ? String(b.contest_code).slice(0, 60) : null;
          const { error } = await db.from("comercial_produto_categoria")
            .update({ categoria, contest_code: contest, validado: !!b?.validado, origem: "manual:" + por, updated_at: new Date().toISOString() }).eq("product_hubla_id", id);
          if (error) return json({ error: error.message }, 400);
        } else if (b?.tipo === "codigo") {
          const codigo = String(b?.codigo ?? "").toLowerCase().trim().slice(0, 60); if (!codigo) return json({ error: "codigo_obrigatorio" }, 400);
          const tipoCod = String(b?.tipo_codigo ?? ""); if (!["vendedor", "cs", "ia", "marketing", "disparo", "site"].includes(tipoCod)) return json({ error: "tipo_invalido" }, 400);
          const { error } = await db.from("comercial_vendedor_codigo")
            .upsert({ codigo, nome: b?.nome ? String(b.nome).slice(0, 80) : null, tipo: tipoCod, validado: !!b?.validado, updated_at: new Date().toISOString() });
          if (error) return json({ error: error.message }, 400);
        } else return json({ error: "tipo_invalido" }, 400);
      }
      const [prod, cod, cont] = await Promise.all([
        fetchAll((a, b) => db.from("comercial_produto_categoria").select("product_hubla_id, product_name, categoria, nome_canonico, contest_code, origem, validado, updated_at").order("product_name").range(a, b)),
        db.from("comercial_vendedor_codigo").select("codigo, nome, tipo, validado, updated_at").order("tipo").order("codigo"),
        db.from("contests").select("code, name").order("name"),
      ]);
      if (cod.error) return json({ error: cod.error.message }, 500);
      return json({ produtos: prod, codigos: cod.data ?? [], contests: cont.data ?? [] });
    } catch (e) { return json({ error: String(e) }, 500); }
  }

  // ---- METAS compartilhadas: GET lista do mês · POST {chave, valor, por} upsert e devolve a lista ----
  if (url.searchParams.get("resource") === "metas") {
    try {
      if (req.method === "POST") {
        const b = await req.json().catch(() => ({}));
        const chave = String(b?.chave ?? "").slice(0, 40);
        if (!/^[a-z_]+$/.test(chave)) return json({ error: "chave_invalida" }, 400);
        const valor = Number(b?.valor);
        if (!isFinite(valor) || valor < 0) return json({ error: "valor_invalido" }, 400);
        const mesPost = isYmd(b?.mes) ? String(b.mes) : mes;
        const { error } = await db.from("comercial_metas")
          .upsert({ mes: mesPost, chave, valor, atualizado_por: String(b?.por ?? "").slice(0, 80), updated_at: new Date().toISOString() });
        if (error) return json({ error: error.message }, 400);
      }
      const { data, error } = await db.from("comercial_metas").select("mes, chave, valor, atualizado_por, updated_at")
        .gte("mes", addMonths(mes, -1)).lte("mes", mes);
      if (error) return json({ error: error.message }, 500);
      return json({ mes, metas: data ?? [] });
    } catch (e) { return json({ error: String(e) }, 500); }
  }

  try {
    const janelas = {
      atual: { ini, fim },
      mom: { ini: addMonths(ini, -1), fim: addMonths(fim, -1) },
      yoy: { ini: addMonths(ini, -12), fim: addMonths(fim, -12) },
    };
    const [vAtual, vMom, vYoy, metas, cfg, anneData, cupons, lAtual, lMom, lYoy, contests, meta, estrela] = await Promise.all([
      vendas(db, janelas.atual.ini, janelas.atual.fim, superior, contest),
      vendas(db, janelas.mom.ini, janelas.mom.fim, superior, contest),
      vendas(db, janelas.yoy.ini, janelas.yoy.fim, superior, contest),
      db.from("comercial_metas").select("mes, chave, valor").gte("mes", addMonths(mes, -1)).lte("mes", mes),
      db.from("comercial_produto_categoria").select("product_hubla_id, categoria, nome_canonico, validado").eq("validado", false),
      anne(ini, fim),
      db.rpc("fn_comercial_cupons_90d", { p_fim: fim }),
      leads(db, janelas.atual.ini, janelas.atual.fim, superior, contest),
      leads(db, janelas.mom.ini, janelas.mom.fim, superior, contest),
      leads(db, janelas.yoy.ini, janelas.yoy.fim, superior, contest),
      db.from("contests").select("code, name").order("name"),
      fetchAll((a, b) => db.rpc("fn_comercial_meta_spend", { p_ini: ini, p_fim: fim }).range(a, b)),
      db.rpc("fn_comercial_estrela"),
    ]);
    if (metas.error) throw new Error(metas.error.message);
    // Anne × leads (só a janela atual tem contatos da Anne; MoM/YoY ficam só com sinais do Data Core)
    const anneOk = !!(anneData as Row).ok;
    const contatos: Row[] = anneOk ? ((anneData as Row).contatos ?? []) : [];
    const batidos = fundirAnne(lAtual as Row[], contatos, fim);
    fundirAnne(lMom as Row[], [], janelas.mom.fim); fundirAnne(lYoy as Row[], [], janelas.yoy.fim);
    const anneResumo = { ok: anneOk, contatos: contatos.length, batidos, com_2_msgs: contatos.filter((c) => (c.msg_user ?? 0) >= 2).length };
    if (anneOk) delete (anneData as Row).contatos;   // não mandar phone_norm ao navegador

    return json({
      generated_at: new Date().toISOString(),
      hoje, filtros: { ini, fim, superior, contest }, janelas,
      vendas: { atual: vAtual, mom: vMom, yoy: vYoy },
      leads: { atual: lAtual, mom: lMom, yoy: lYoy },
      anne_resumo: anneResumo,
      estrela: estrela.error ? { error: estrela.error.message } : (estrela.data ?? []),
      contests: contests.data ?? [],
      meta_spend: meta,
      metas: metas.data ?? [],
      cupons_90d: cupons.error ? { error: cupons.error.message } : ((cupons.data as unknown[])?.[0] ?? null),
      avisos: {
        produtos_nao_validados: (cfg.data ?? []).length,
      },
      anne: anneData,
    });
  } catch (e) {
    return json({ error: String(e) }, 500);
  }
});
