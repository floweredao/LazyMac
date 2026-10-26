#!/usr/bin/env bun
// lazymac omo-anthropic: one omo provider, "anthropic-api", that uses every Anthropic Console
// API key kept in the Keychain under service "omo-anthropic-api" (one item per account; the
// account name is the item's account). Order: "main" first, then the rest by name. The first one is
// pinned, so omo always uses it first and moves to the next one only when it fails (auth error,
// rate limit, credit). Without the pin omo picks among the keys on its own.
//
//   bun bin/omo-anthropic.ts sync          put the provider into ~/.omo/agent/models.json and the
//                                          keys into ~/.omo/agent/auth.json
//   bun bin/omo-anthropic.ts add <name>    read a key from stdin (`pbpaste | bun bin/omo-anthropic.ts add main`),
//                                          save it in the Keychain, then sync
//   bun bin/omo-anthropic.ts list          account names in the Keychain (never values)
//   bun bin/omo-anthropic.ts check         ask Anthropic whether each key works (GET /v1/models, costs nothing)
//
// Keys are never printed. auth.json stays mode 600. A file that changes is first copied to
// <file>.bak-lazymac-<time>. Restart omo afterwards so it reads the new provider.
// Test hooks: LAZYMAC_KEYCHAIN=<keychain file>  LAZYMAC_OMO_AGENT=<omo agent folder>
import { chmodSync, copyFileSync, existsSync, mkdirSync, readFileSync, renameSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";

const SERVICE = "omo-anthropic-api";
const PROVIDER = "anthropic-api";
const KEYCHAIN = process.env.LAZYMAC_KEYCHAIN ?? join(homedir(), "Library/Keychains/login.keychain-db");
const AGENT = process.env.LAZYMAC_OMO_AGENT ?? join(homedir(), ".omo/agent");
const KEY_SHAPE = /^sk-ant-[A-Za-z0-9_-]{20,300}$/;
const NAME_SHAPE = /^[A-Za-z0-9._-]{1,64}$/;

const model = (id: string) => ({ id, name: id, reasoning: true, input: ["text", "image"], contextWindow: 1000000, maxTokens: 128000 });
const PROVIDER_CONFIG = {
  baseUrl: "https://api.anthropic.com",
  api: "anthropic-messages",
  compat: { forceAdaptiveThinking: true, supportsMidConvoEffort: true },
  models: ["claude-fable-5-1", "claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5"].map(model),
};

async function run(cmd: string[], stdin?: string): Promise<{ code: number; out: string; err: string }> {
  const p = Bun.spawn(cmd, { stdin: stdin === undefined ? "ignore" : new TextEncoder().encode(stdin), stdout: "pipe", stderr: "pipe" });
  const [out, err, code] = await Promise.all([new Response(p.stdout).text(), new Response(p.stderr).text(), p.exited]);
  return { code, out, err };
}

// Account names of the generic-password items with our service. dump-keychain without -d prints attributes only.
export function parseAccounts(dump: string): string[] {
  const names = new Set<string>();
  let cls = "", svc = "", acct = "";
  const flush = () => { if (cls === "genp" && svc === SERVICE && acct) names.add(acct); cls = svc = acct = ""; };
  for (const line of dump.split("\n")) {
    if (line.startsWith("keychain: ")) flush();
    else if (line.startsWith("class: ")) cls = line.slice(7).replaceAll('"', "");
    else if (line.startsWith('    "svce"<blob>="')) svc = line.slice(18, -1);
    else if (line.startsWith('    "acct"<blob>="')) acct = line.slice(18, -1);
  }
  flush();
  return [...names].sort((a, b) => (a === "main" ? -1 : b === "main" ? 1 : a.localeCompare(b)));
}

async function accounts(): Promise<string[]> {
  const r = await run(["/usr/bin/security", "dump-keychain", KEYCHAIN]);
  if (r.code !== 0) throw new Error(`could not list the Keychain ${KEYCHAIN}`);
  return parseAccounts(r.out);
}

async function readKey(name: string): Promise<string> {
  const r = await run(["/usr/bin/security", "find-generic-password", "-s", SERVICE, "-a", name, "-w", KEYCHAIN]);
  const key = r.out.trim();
  if (r.code !== 0 || !KEY_SHAPE.test(key)) throw new Error(`Keychain item ${SERVICE}/${name} is missing, locked or not an Anthropic key`);
  return key;
}

function readJson(file: string): Record<string, any> {
  return existsSync(file) ? JSON.parse(readFileSync(file, "utf8")) : {};
}

function writeJson(file: string, data: unknown, mode?: number): boolean {
  const text = JSON.stringify(data, null, 2) + "\n";
  if (existsSync(file) && readFileSync(file, "utf8") === text) return false;
  mkdirSync(AGENT, { recursive: true });
  if (existsSync(file)) {
    const stamp = new Date().toISOString().replace(/[-:]/g, "").replace(/\..*/, "");
    copyFileSync(file, `${file}.bak-lazymac-${stamp}`);
    if (mode !== undefined) chmodSync(`${file}.bak-lazymac-${stamp}`, mode);
  }
  const tmp = `${file}.lazymac-tmp`;
  writeFileSync(tmp, text, mode === undefined ? undefined : { mode });
  if (mode !== undefined) chmodSync(tmp, mode);
  renameSync(tmp, file);
  return true;
}

async function sync(): Promise<number> {
  const names = await accounts();
  if (names.length === 0) {
    console.error(`No Keychain items with service ${SERVICE}. Add one: pbpaste | bun bin/omo-anthropic.ts add main`);
    return 1;
  }
  const list = [];
  for (const name of names) list.push({ name, key: await readKey(name) });

  const modelsFile = join(AGENT, "models.json");
  const models = readJson(modelsFile);
  models.providers = { ...(models.providers ?? {}), [PROVIDER]: PROVIDER_CONFIG };
  const m = writeJson(modelsFile, models);

  const authFile = join(AGENT, "auth.json");
  const auth = readJson(authFile);
  auth[PROVIDER] = { type: "api_key", key: list[0].key, accounts: list, pinned: list[0].name };
  const a = writeJson(authFile, auth, 0o600);

  console.log(`${PROVIDER}: ${names.length} account(s) in this order: ${names.join(", ")}`);
  console.log(`models.json ${m ? "updated" : "already up to date"}, auth.json ${a ? "updated" : "already up to date"}.`);
  if (m || a) console.log("Restart omo so it reads the change.");
  return 0;
}

async function add(name: string | undefined): Promise<number> {
  if (!name || !NAME_SHAPE.test(name)) { console.error("usage: <key on stdin> | bun bin/omo-anthropic.ts add <name>  (name: letters, digits, . _ -)"); return 2; }
  const key = (await new Response(Bun.stdin.stream()).text()).trim();
  if (!KEY_SHAPE.test(key)) { console.error("stdin does not hold an Anthropic API key (sk-ant-...). Nothing was stored."); return 1; }
  // security -i reads the command from stdin, so the key never shows up in the process list.
  const r = await run(["/usr/bin/security", "-i"], `add-generic-password -U -a "${name}" -s "${SERVICE}" -l "${SERVICE}" -w "${key}" "${KEYCHAIN}"\n`);
  if (r.code !== 0 || (await readKey(name)) !== key) { console.error(`could not store ${SERVICE}/${name} in the Keychain`); return 1; }
  console.log(`Stored ${SERVICE}/${name} in the Keychain.`);
  return sync();
}

async function check(): Promise<number> {
  const names = await accounts();
  let bad = 0;
  for (const name of names) {
    const res = await fetch("https://api.anthropic.com/v1/models", { headers: { "x-api-key": await readKey(name), "anthropic-version": "2023-06-01" } });
    const body = res.ok ? "" : ` ${((await res.json().catch(() => ({}))) as any)?.error?.type ?? ""}`;
    console.log(`${name.padEnd(16)} ${res.status}${res.ok ? " ok" : body}`);
    if (!res.ok) bad++;
  }
  if (names.length === 0) console.log(`No Keychain items with service ${SERVICE}.`);
  return bad ? 1 : 0;
}

if (import.meta.main) {
  const [cmd = "sync", arg] = process.argv.slice(2);
  const code = cmd === "sync" ? await sync()
    : cmd === "add" ? await add(arg)
    : cmd === "list" ? (console.log((await accounts()).join("\n")), 0)
    : cmd === "check" ? await check()
    : (console.error("usage: bun bin/omo-anthropic.ts [sync | add <name> | list | check]"), 2);
  process.exit(code);
}
