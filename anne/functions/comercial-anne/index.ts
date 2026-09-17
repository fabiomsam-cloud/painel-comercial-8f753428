// Painel de Inteligência Comercial — lado Anne (blwbbdcwdcwitsnskplk). Mesmo token ?k= da edge dashboard-comercial.
// Devolve: vendedores ativos, sales do período (seção 5), contatos dos leads do período (seções 2/3).
import { createClient } from "jsr:@supabase/supabase-js@2";

const TOKEN = "com-sou-byMernuvTjwl28hb";
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};
const json = (obj: unknown, status = 200) =>
  new Response(JSON.stringify(obj), { status, headers: { ...corsHeaders, "Content-Type": "application/json", "Cache-Control": "no-store" } });

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  const url = new URL(req.url);
  if ((url.searchParams.get("k") ?? "") !== TOKEN) return json({ error: "unauthorized" }, 401);
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!);
  try {
    // janela em dia Manaus (-04): [ini 00:00, fim 23:59:59]
    const ini = url.searchParams.get("ini") ?? "", fim = url.searchParams.get("fim") ?? "";
    const okYmd = (x: string) => /^\d{4}-\d{2}-\d{2}$/.test(x);
    const tIni = okYmd(ini) ? ini + "T04:00:00.000Z" : new Date(Date.now() - 45 * 86400e3).toISOString();
    const tFim = okYmd(fim) ? new Date(Date.parse(fim + "T04:00:00.000Z") + 86400e3 - 1).toISOString() : new Date().toISOString();
    // PostgREST corta em 1000 linhas por requisição — paginar
    // deno-lint-ignore no-explicit-any
    const fetchAll = async (build: (a: number, b: number) => any) => { const out: unknown[] = []; for (let f = 0; f < 50000; f += 1000) { const { data, error } = await build(f, f + 999); if (error) throw new Error(error.message); out.push(...(data ?? [])); if (!data || data.length < 1000) break; } return out; };
    const [conv, vend, sales, contatos] = await Promise.all([
      sb.from("conversations").select("status", { count: "exact", head: true }).eq("status", "humano_comercial"),
      sb.from("vendedores").select("id, nome, tipo, ativo").eq("ativo", true),
      // atribuição oficial da Anne (seção 5): quando existe linha em sales, ela vence o código do utm_term
      sb.from("sales").select("hubla_transaction_id, attribution, matched_by, agent_slug, paid_at, amount")
        .gte("paid_at", tIni).lte("paid_at", tFim).range(0, 4999),
      // contatos ligados aos leads do período (chave lead_id; phone_norm só para fallback no servidor) + sinais de conversa real
      okYmd(ini) && okYmd(fim) ? fetchAll((a, b) => sb.rpc("fn_comercial_anne_contatos", { p_ini: ini, p_fim: fim }).range(a, b)) : Promise.resolve([]),
    ]);
    if (vend.error) throw new Error(vend.error.message);
    if (sales.error) throw new Error(sales.error.message);
    return json({ generated_at: new Date().toISOString(), janela: { ini: tIni, fim: tFim },
      humano_comercial: conv.count ?? null, vendedores: vend.data ?? [], sales: sales.data ?? [], contatos });
  } catch (e) { return json({ error: String(e) }, 500); }
});
