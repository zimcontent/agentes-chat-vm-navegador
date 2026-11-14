/**
 * Mede quanto o navegador do agente demora para clicar, preencher e abrir uma janela nova, usando o
 * BrowserManager de verdade de um checkout do agentes.chat contra um Chrome de verdade.
 *
 *   bun repro/medir.ts /caminho/do/agentes-chat [pasta-de-estado]
 *
 * Rode uma vez no código sem os consertos e outra no código com eles, cada uma com a sua pasta de
 * estado. O defeito da aba escondida só aparece quando o Chrome volta com abas de uma sessão
 * anterior, então o script abre o navegador mais de uma vez na mesma pasta.
 */
import { mkdirSync } from "node:fs";
import path from "node:path";

const repo = process.argv[2];
if (!repo) {
  console.error("uso: bun repro/medir.ts /caminho/do/agentes-chat [pasta-de-estado]");
  process.exit(2);
}
const state = path.resolve(process.argv[3] ?? "./estado-medir");
const rounds = Number(process.env.RODADAS ?? 3);
mkdirSync(`${state}/runner`, { recursive: true });
mkdirSync(`${state}/agente`, { recursive: true });

const { BrowserManager } = await import(path.resolve(repo, "apps/server/runner/browser.ts"));
const { LOOK } = await import(path.resolve(repo, "packages/engine/src/browser/surface.ts"));

const PAGE = `<!doctype html><title>medir</title><body style="margin:0;font:16px sans-serif">
<button id=b style="position:absolute;left:100px;top:100px;width:220px;height:40px" onclick="document.title='clicou'">Botao comum</button>
<input id=f aria-label="Campo de texto" style="position:absolute;left:100px;top:200px;width:320px;height:30px">
<button id=p style="position:absolute;left:100px;top:300px;width:220px;height:40px" onclick="window.open('/dois','_blank','width=300,height=200')">Abrir janela nova</button>`;
const server = Bun.serve({
  port: 0,
  hostname: "127.0.0.1",
  fetch: (req) =>
    new Response(new URL(req.url).pathname === "/dois" ? "<!doctype html><title>dois</title>ok" : PAGE, {
      headers: { "content-type": "text/html" },
    }),
});
const url = `http://127.0.0.1:${server.port}/`;

const agent = { id: "11111111-1111-1111-1111-111111111111", handle: "medir" };
const b64 = (s: string) => Buffer.from(s).toString("base64");
const settle = { command: "eval", args: ["-b", b64("new Promise(r=>setTimeout(()=>r(true),300))")], timeoutSeconds: 5, tolerate: true };
const open = { command: "open", args: [url], timeoutSeconds: 60 };
const cmd = (command: string, ...args: string[]) => ({ command, args, timeoutSeconds: 40 });
const ref = (snap: any, re: RegExp) =>
  Object.entries(snap?.refs ?? {}).find(([, v]: any) => re.test(`${v.role} ${v.name}`))?.[0];

const rows: Array<Record<string, string>> = [];
for (let round = 1; round <= rounds; round++) {
  const manager: any = new BrowserManager({
    home: `${state}/runner`,
    log: (line: string) => process.env.VER_LOG && console.log("   log:", line),
    send: () => true,
    secret: async () => null,
  });
  const act = async (label: string, commands: any[]) => {
    const started = Date.now();
    const out = await manager.batch(agent, `${state}/agente`, { op: "browser.batch", commands: [...commands, settle, LOOK] });
    const first = out.answers[0];
    const last = out.answers[out.answers.length - 1];
    if (label) {
      rows.push({
        rodada: String(round),
        acao: label,
        tempo: `${((Date.now() - started) / 1000).toFixed(1)} s`,
        resultado: first?.success ? "ok" : `falhou: ${String(first?.error ?? "").slice(0, 60)}`,
      });
    }
    return last?.success ? last.data : null;
  };
  let snap = await act("", [open]);
  const visible = await manager.batch(agent, `${state}/agente`, {
    op: "browser.batch",
    commands: [cmd("eval", "document.visibilityState")],
  });
  console.log(`rodada ${round}: a aba do agente está ${visible.answers[0]?.data?.result ?? "?"} logo depois de abrir`);
  const button = ref(snap, /button Botao comum/);
  if (button) snap = (await act("clique num botão", [cmd("click", `@${button}`)])) ?? snap;
  const field = ref(snap, /textbox/);
  if (field) snap = (await act("preencher 30 letras", [cmd("fill", `@${field}`, "abcdefghij abcdefghij abcdefgh")])) ?? snap;
  snap = (await act("", [open])) ?? snap;
  const popup = ref(snap, /button Abrir janela nova/);
  if (popup) await act("clique que abre janela nova", [cmd("click", `@${popup}`)]);
  await manager.closeAll();
  await Bun.sleep(1500);
}
console.table(rows);
server.stop(true);
process.exit(0);
