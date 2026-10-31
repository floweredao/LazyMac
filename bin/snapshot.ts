#!/usr/bin/env bun
// lazymac snapshots: the catalog list as it was on each day, and the public history page built from them.
//
//   bun bin/snapshot.ts take [YYYY-MM-DD]   write snapshots/<date>.tsv from catalog.tsv (default: today, local time)
//   bun bin/snapshot.ts build <dir>         write the history site (index.html + data/*.json) into <dir>
//   bun bin/snapshot.ts deploy              build into .work/history-site and publish it to Cloudflare Pages
//                                           (the project in $LAZYMAC_CF_PROJECT), then wait until the live page shows the newest day
//
// The page is public, so build leaves out rows that say what secrets exist (section secret) and data that
// lives only on this Mac (group data), and only publishes names, groups, decisions and the one-line description.
// It refuses (exit 5) when a private word, a mail address, a home path or an IP address would be published.
// Token: macOS Keychain service $LAZYMAC_CF_KEYCHAIN (default lazymac-cloudflare), accounts api-token / account-id (falls back to wrangler login).
// LAZYMAC_SNAPSHOT_DIR overrides snapshots/ (tests).
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { parseGroups, thisHost } from "./catalog.ts";

import { dataRoot, requireMain, syncData } from "./storage.ts";
const ROOT = dataRoot;
const SNAP_DIR = process.env.LAZYMAC_SNAPSHOT_DIR ?? join(ROOT, "snapshots");
// A *.pages.dev address belongs to whichever Cloudflare account registered it, so one fixed name
// can only ever serve one person: set LAZYMAC_CF_PROJECT to a Pages project of your own.
export const PROJECT = process.env.LAZYMAC_CF_PROJECT ?? "lazymac-history";
export const SITE_URL = `https://${PROJECT}.pages.dev`;
const WRANGLER = "wrangler@4.152.0";
const COLS = ["section", "group", "id", "name", "name_ko", "decision", "what_en", "what_ko"] as const;
type Item = Record<(typeof COLS)[number], string>;
// Generic patterns (home paths, e-mail, IPv4) plus the user's own words, one per line, in
// ~/.config/lazymac/private-words (LAZYMAC_PRIVATE_WORDS overrides the path).
const WORDS_FILE = process.env.LAZYMAC_PRIVATE_WORDS ?? join(homedir(), ".config/lazymac/private-words");
const words = existsSync(WORDS_FILE)
  ? readFileSync(WORDS_FILE, "utf8").split("\n").map((w) => w.trim()).filter((w) => w && !w.startsWith("#"))
  : [];
const escape = (w: string) => w.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
export const PRIVATE = new RegExp(
  [...words.map(escape), String.raw`\/Users\/`, String.raw`[\w.+-]+@[\w-]+\.[\w.]+`, String.raw`\b\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\b`].join("|"),
  "g",
);

class SnapError extends Error {
  constructor(readonly code: number, message: string) {
    super(message);
  }
}

const today = () => new Date().toLocaleDateString("sv-SE");
// Date.parse rolls 2026-02-31 over to March 3, so the parsed date must read back as the same day.
const validDate = (d: string) => /^\d{4}-\d{2}-\d{2}$/.test(d) && !Number.isNaN(Date.parse(d)) && new Date(d).toISOString().slice(0, 10) === d;

// catalog.tsv by header name, so older catalogs from git history with other columns still read.
export function catalogItems(text: string): Item[] {
  const lines = text.split("\n").filter((l) => l.trim() && !l.startsWith("#"));
  const head = lines[0].split("\t");
  return lines.slice(1).map((l) => {
    const c = l.split("\t");
    return Object.fromEntries(COLS.map((k) => [k, (c[head.indexOf(k)] ?? "").trim()])) as Item;
  });
}

export const snapshotText = (items: Item[]) => [COLS.join("\t"), ...items.map((i) => COLS.map((k) => i[k]).join("\t"))].join("\n") + "\n";

const writeSnapshot = (date: string, catalog: string) => {
  mkdirSync(SNAP_DIR, { recursive: true });
  writeFileSync(join(SNAP_DIR, `${date}.tsv`), snapshotText(catalogItems(catalog)));
};

function take(date = today()) {
  if (!validDate(date)) throw new SnapError(2, `bad date: ${date}`);
  writeSnapshot(date, readFileSync(join(ROOT, "catalog.tsv"), "utf8"));
  console.log(`SNAPSHOT ${date}`);
}

type Pub = { s: string; g: string; n: string; k: string; d: string; we: string; wk: string };
const isPublic = (i: Item) => i.section !== "secret" && i.group !== "data" && i.section !== "section";
const pub = (i: Item): Pub => ({ s: i.section, g: i.group, n: i.name, k: i.name_ko, d: i.decision, we: i.what_en, wk: i.what_ko });
const key = (i: Item) => `${i.section}\t${i.id}`;

export function siteData(snapshots: { date: string; items: Item[] }[]) {
  const days: { date: string; counts: Record<string, number>; added: number; removed: number; changed: number }[] = [];
  const files: Record<string, unknown> = {};
  let prev: Map<string, Item> | undefined;
  for (const { date, items } of snapshots.sort((a, b) => a.date.localeCompare(b.date))) {
    const now = new Map(items.filter(isPublic).map((i) => [key(i), i]));
    const added: Pub[] = [], removed: Pub[] = [], changed: (Pub & { from: string })[] = [];
    if (prev) {
      for (const [k, i] of now) {
        const p = prev.get(k);
        if (!p) added.push(pub(i));
        else if (p.decision !== i.decision) changed.push({ ...pub(i), from: p.decision });
      }
      for (const [k, p] of prev) if (!now.has(k)) removed.push(pub(p));
    }
    const list = [...now.values()];
    const counts = { total: list.length, keep: 0, drop: 0, ask: 0 } as Record<string, number>;
    for (const i of list) counts[i.decision] = (counts[i.decision] ?? 0) + 1;
    days.push({ date, counts, added: added.length, removed: removed.length, changed: changed.length });
    files[date] = { date, first: !prev, counts, added, removed, changed, items: list.map(pub) };
    prev = now;
  }
  return { index: { updated: new Date().toISOString(), groups: publicGroups(), days: days.reverse() }, files };
}

// Subcategory titles in display order: [section, group, title_en, title_ko], without the rows the page leaves out.
function publicGroups(): string[][] {
  const all = parseGroups(readFileSync(join(ROOT, "groups.tsv"), "utf8"));
  return Object.entries(all).flatMap(([s, gs]) => Object.entries(gs).map(([g, t]) => [s, g, t.en, t.ko]))
    .filter(([s, g]) => isPublic({ section: s, group: g } as Item));
}

export function privacyHits(text: string): string[] {
  return [...new Set(text.match(PRIVATE) ?? [])];
}

function readSnapshots() {
  if (!existsSync(SNAP_DIR)) return [];
  return readdirSync(SNAP_DIR)
    .filter((f) => /^\d{4}-\d{2}-\d{2}\.tsv$/.test(f))
    .map((f) => ({ date: f.slice(0, 10), items: catalogItems(readFileSync(join(SNAP_DIR, f), "utf8")) }));
}

function build(out: string) {
  const snaps = readSnapshots();
  if (!snaps.length) throw new SnapError(1, `no snapshots in ${SNAP_DIR}`);
  const { index, files } = siteData(snaps);
  const out_ = { "data/index.json": JSON.stringify(index) } as Record<string, string>;
  for (const [date, f] of Object.entries(files)) out_[`data/${date}.json`] = JSON.stringify(f);
  const hits = privacyHits(Object.values(out_).join("\n"));
  if (hits.length) throw new SnapError(5, `REFUSED_PRIVATE ${hits.join(",")}`);
  rmSync(out, { recursive: true, force: true });
  mkdirSync(join(out, "data"), { recursive: true });
  for (const [p, body] of Object.entries(out_)) writeFileSync(join(out, p), body);
  writeFileSync(join(out, "index.html"), readFileSync(join(import.meta.dir, "history.html"), "utf8"));
  writeFileSync(join(out, "_headers"), "/*\n  X-Robots-Tag: noindex, nofollow\n  Referrer-Policy: no-referrer\n/data/*\n  Cache-Control: no-cache\n");
  console.log(`BUILT ${out} (${snaps.length} days, newest ${index.days[0].date})`);
  return index.days[0].date;
}

const keychain = (account: string) => {
  const r = Bun.spawnSync(["security", "find-generic-password", "-s", process.env.LAZYMAC_CF_KEYCHAIN ?? "lazymac-cloudflare", "-a", account, "-w"]);
  return r.exitCode === 0 ? r.stdout.toString().trim() : undefined;
};

async function deploy() {
  const out = join(ROOT, ".work", "history-site");
  const newest = build(out);
  const env: Record<string, string> = { ...(process.env as Record<string, string>) };
  const token = keychain("api-token"), account = keychain("account-id");
  if (token) env.CLOUDFLARE_API_TOKEN = token;
  if (account) env.CLOUDFLARE_ACCOUNT_ID = account;
  const wrangler = (...a: string[]) => Bun.spawnSync(["bunx", WRANGLER, ...a], { env, stdout: "pipe", stderr: "pipe" });
  const list = wrangler("pages", "project", "list");
  if (list.exitCode !== 0) throw new SnapError(4, `wrangler project list failed: ${list.stderr.toString().slice(-500)}`);
  if (!list.stdout.toString().includes(`${PROJECT}.pages.dev`)) {
    // wrangler 4.15x hands a new project to Workers unless --force keeps it a plain Pages project (*.pages.dev).
    const c = wrangler("pages", "project", "create", PROJECT, "--production-branch", "main", "--force");
    if (c.exitCode !== 0) {
      throw new SnapError(4, `wrangler project create failed for ${PROJECT}; the name may belong to another Cloudflare account, in which case set LAZYMAC_CF_PROJECT to one of your own: ${c.stderr.toString().slice(-500)}`);
    }
  }
  const d = wrangler("pages", "deploy", out, "--project-name", PROJECT, "--branch", "main", "--commit-dirty=true");
  if (d.exitCode !== 0) throw new SnapError(4, `DEPLOY_FAILED ${d.stderr.toString().slice(-800)}`);
  rmSync(out, { recursive: true, force: true });
  // A fresh deploy takes a few seconds to reach the edge; bounded wait for the newest day to show.
  for (let i = 0; i < 30; i++) {
    const r = await fetch(`${SITE_URL}/data/index.json?t=${Date.now()}`).catch(() => undefined);
    if (r?.ok && ((await r.json()) as { days: { date: string }[] }).days[0]?.date === newest) {
      console.log(`DEPLOYED ${SITE_URL}/ (newest ${newest})`);
      return;
    }
    await Bun.sleep(3000);
  }
  throw new SnapError(4, `NOT_LIVE ${SITE_URL}/ does not show ${newest}`);
}

if (import.meta.main) {
  const [cmd, arg] = process.argv.slice(2);
  try {
    if (cmd === "take") { requireMain(thisHost()); take(arg); await syncData(); }
    else if (cmd === "build" && arg) build(arg);
    else if (cmd === "deploy") await deploy();
    else throw new SnapError(2, "usage: snapshot.ts take [date] | build <dir> | deploy");
  } catch (e) {
    console.error(e instanceof Error ? e.message : String(e));
    process.exit(e instanceof SnapError ? e.code : 1);
  }
}
