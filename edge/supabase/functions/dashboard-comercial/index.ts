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
    const [vAtual, vMom, vYoy, metas, cfg, anneData, cupons] = await Promise.all([
      vendas(db, janelas.atual.ini, janelas.atual.fim, superior, contest),
      vendas(db, janelas.mom.ini, janelas.mom.fim, superior, contest),
      vendas(db, janelas.yoy.ini, janelas.yoy.fim, superior, contest),
      db.from("comercial_metas").select("mes, chave, valor").gte("mes", addMonths(mes, -1)).lte("mes", mes),
      db.from("comercial_produto_categoria").select("product_hubla_id, categoria, nome_canonico, validado").eq("validado", false),
      anne(ini, fim),
      db.rpc("fn_comercial_cupons_90d", { p_fim: fim }),
    ]);
    if (metas.error) throw new Error(metas.error.message);

    return json({
      generated_at: new Date().toISOString(),
      hoje, filtros: { ini, fim, superior, contest }, janelas,
      vendas: { atual: vAtual, mom: vMom, yoy: vYoy },
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
