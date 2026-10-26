#!/usr/bin/env bun
// lazymac catalog tool. catalog.tsv is the one list of everything on this Mac.
//
//   bun bin/catalog.ts render          rewrite setup/ and the lists inside README.md / README-ko.md
//   bun bin/catalog.ts check [dir]     compare with an inventory folder (default: every Mac in inventory/):
//                                      things not in the catalog (tagged with the Mac they were found on),
//                                      keep items missing on this Mac, and whether setup/ and the READMEs
//                                      are up to date. Exits 1 when something is unclassified or out of date.
//   bun bin/catalog.ts prune           remove rows (any decision) for things the scans can see that are gone
//                                      from EVERY Mac in inventory/<host>/: deleted means no longer needed.
//                                      Then run render. Refuses (exit 1) when this Mac's scan has an empty
//                                      file or more than PRUNE_LIMIT rows would go (a broken scan). Another
//                                      Mac's scan only ever keeps rows: a kind its scan file lacks is kept.
//   bun bin/catalog.ts profile <names> <dir>
//                                      write the setup lists for a profile (base[,add-on...]) into <dir>,
//                                      in the setup/ format, plus skip.txt (steps the profile leaves out)
//   bun bin/catalog.ts compare <names> | --file <profile.txt>  [--host <host>] [--json]
//                                      compare a profile with a Mac's scan (default: this Mac):
//                                      missing (would be installed), extra (only shown, never deleted), same
//
// Each Mac's scan lives in inventory/<host>/ (host = scutil --get LocalHostName, or LAZYMAC_HOST).
// machines.tsv says which Mac runs the full daily job (role main) and each Mac's profiles.
// profiles/<name>.txt: a base profile starts with `from keep|empty|<base>`; an add-on has no from line.
// Lines: `+ group <section>/<group>` (its ✅ and ❓ rows), `- group ...`, `+ <section>/<id>`, `- <section>/<id>`,
// `skip <step>...` (setup steps the profile leaves out).
//   bun bin/catalog.ts machine [--host h]   print this Mac's role (main | extra) and profiles from machines.tsv
import { existsSync, mkdirSync, readdirSync, readFileSync, statSync, writeFileSync } from "node:fs";
import { hostname } from "node:os";
import { join, resolve } from "node:path";

import { dataRoot, requireMain, syncData } from "./storage.ts";
const ROOT = dataRoot;
const INVENTORY = process.env.LAZYMAC_INVENTORY_DIR ?? join(ROOT, "inventory");
const PROFILES = process.env.LAZYMAC_PROFILES_DIR ?? join(ROOT, "profiles");

export function thisHost(): string {
  if (process.env.LAZYMAC_HOST) return process.env.LAZYMAC_HOST;
  const r = Bun.spawnSync(["/usr/sbin/scutil", "--get", "LocalHostName"]);
  return (r.exitCode === 0 && r.stdout.toString().trim()) || hostname().split(".")[0];
}
type Decision = "keep" | "drop" | "ask";
type Row = {
  section: string; group: string; ids: string[]; name: string; label: { en: string; ko: string }; decision: Decision; how: string; ref: string;
  what: { en: string; ko: string }; why: { en: string; ko: string };
};
type Lang = "en" | "ko";

const HOWS = new Set(["brew", "cask", "mas", "npm", "bun", "uv", "tap", "nvm", "bun-install", "uv-python", "script", "release", "download",
  "build", "repo", "bundle", "copy", "with-tool", "with-app", "register", "restore", "byhand", "signin", "none"]);

export function parseCatalog(text: string): Row[] {
  const rows: Row[] = [];
  const lines = text.split("\n").filter((l) => l.trim() && !l.startsWith("#"));
  for (const [i, line] of lines.slice(1).entries()) {
    const c = line.split("\t");
    if (c.length !== 12) throw new Error(`catalog.tsv row ${i + 1}: expected 12 columns, got ${c.length}: ${line.slice(0, 60)}`);
    const [section, group, id, name, nameKo, decision, how, ref, wen, wko, yen, yko] = c;
    if (!["keep", "drop", "ask"].includes(decision)) throw new Error(`catalog.tsv row ${i + 1}: bad decision ${decision}`);
    if (!HOWS.has(how)) throw new Error(`catalog.tsv row ${i + 1}: bad how ${how}`);
    rows.push({ section, group, ids: id.split(","), name, label: { en: name, ko: nameKo || name }, decision: decision as Decision, how, ref,
      what: { en: wen, ko: wko }, why: { en: yen, ko: yko } });
  }
  return rows;
}

type Title = { en: string; ko: string };

// groups.tsv: the subcategory titles, in display order. The history page and the app read the same file.
export function parseGroups(text: string): Record<string, Record<string, Title>> {
  const out: Record<string, Record<string, Title>> = {};
  const lines = text.split("\n").filter((l) => l.trim() && !l.startsWith("#"));
  for (const [i, line] of lines.slice(1).entries()) {
    const c = line.split("\t");
    if (c.length !== 4 || c.some((v) => !v.trim())) throw new Error(`groups.tsv row ${i + 1}: expected 4 filled columns: ${line.slice(0, 60)}`);
    (out[c[0]] ??= {})[c[1]] = { en: c[2], ko: c[3] };
  }
  return out;
}

const GROUPS = parseGroups(readFileSync(join(ROOT, "groups.tsv"), "utf8"));

const SECTIONS: Record<string, Title & { groups: Record<string, Title> }> = {
  app: { en: "Apps", ko: "앱", groups: GROUPS.app ?? {} },
  cli: { en: "Command-line tools", ko: "명령줄 도구", groups: GROUPS.cli ?? {} },
  job: { en: "Running in the background", ko: "뒤에서 도는 것", groups: GROUPS.job ?? {} },
  setting: { en: "Settings and fonts", ko: "설정·글꼴", groups: GROUPS.setting ?? {} },
  secret: { en: "Secrets and sign-ins", ko: "비밀값·로그인", groups: GROUPS.secret ?? {} },
  elsewhere: { en: "Kept in other repos", ko: "다른 저장소에 있는 것", groups: GROUPS.elsewhere ?? {} },
  leftover: { en: "Leftovers on this Mac", ko: "이 맥의 찌꺼기", groups: GROUPS.leftover ?? {} },
};

// A row whose group has no title in groups.tsv would silently drop out of the README lists.
const unknownGroups = (rows: Row[]) => rows.filter((r) => !SECTIONS[r.section]?.groups[r.group]);

const MARK: Record<Decision, { en: string; ko: string }> = {
  keep: { en: "✅ bring", ko: "✅ 가져감" }, drop: { en: "⛔ leave", ko: "⛔ 두고 감" }, ask: { en: "❓ your call", ko: "❓ 직접 결정" },
};

function cell(s: string): string {
  return s.replaceAll("|", "\\|");
}

function newMac(r: Row, l: Lang): string {
  const how = howText(r, l);
  if (r.decision !== "ask") return how;
  return l === "ko" ? `가져가기로 하면 ${how}` : `if brought: ${how}`;
}

function howText(r: Row, l: Lang): string {
  const ko = l === "ko";
  const auto = (src: string) => (ko ? `자동 (${src})` : `auto (${src})`);
  const link = (label: string) => `[${label}](${r.ref})`;
  switch (r.how) {
    case "brew": case "cask": case "tap": return auto("Homebrew");
    case "mas": return auto("App Store");
    case "npm": case "bun": case "uv": case "nvm": return auto(r.how);
    case "bun-install": return auto(ko ? "bun 설치기" : "bun installer");
    case "uv-python": return auto("uv");
    case "script": return auto(ko ? "설치 스크립트" : "install script");
    case "release": return auto(ko ? `GitHub 릴리즈 [${r.ref.split("#")[0]}](https://github.com/${r.ref.split("#")[0]}/releases)` : `GitHub release [${r.ref.split("#")[0]}](https://github.com/${r.ref.split("#")[0]}/releases)`);
    case "download": return ko ? `직접 ${link("받기")}` : `by hand: ${link("download")}`;
    case "build": return ko ? `직접 ${link("빌드")}` : `by hand: ${link("build")}`;
    case "repo": return auto(r.ref);
    case "bundle": return auto(ko ? "암호화 묶음" : "encrypted bundle");
    case "copy": return auto(ko ? "복사" : "copied");
    case "with-tool": case "with-app": return ko ? `${r.ref} 설치 때 같이 옴` : `comes with ${r.ref}`;
    case "register": return auto(ko ? "setup이 등록" : "setup registers");
    case "restore": return ko ? "자체 복원 안내" : "its own restore";
    case "byhand": return ko ? "직접" : "by hand";
    case "signin": return ko ? "직접 로그인" : "sign in";
    default: return "-";
  }
}

function table(rows: Row[], l: Lang, withMac = true): string[] {
  const h = l === "ko"
    ? (withMac ? "| 이름 | 하는 일 | 가져갈까 | 새 맥에서 |\n|---|---|---|---|" : "| 이름 | 하는 일 | 왜 |\n|---|---|---|")
    : (withMac ? "| Name | What it does | Bring it? | On the new Mac |\n|---|---|---|---|" : "| Name | What it does | Why |\n|---|---|---|");
  const out = [h];
  for (const r of rows) {
    const why = `${MARK[r.decision][l]}: ${r.why[l]}`;
    out.push(withMac
      ? `| ${cell(r.label[l])} | ${cell(r.what[l])} | ${cell(why)} | ${newMac(r, l)} |`
      : `| ${cell(r.label[l])} | ${cell(r.what[l])} | ${cell(r.why[l])} |`);
  }
  return out;
}

function count(rows: Row[], d: Decision) {
  return rows.filter((r) => r.decision === d).length;
}

export function renderBlocks(rows: Row[], l: Lang): Record<string, string> {
  const ko = l === "ko";
  const counts = [ko ? "| 묶음 | ✅ 가져감 | ⛔ 두고 감 | ❓ 직접 결정 |" : "| Area | ✅ bring | ⛔ leave | ❓ your call |", "|---|---:|---:|---:|"];
  for (const [key, s] of Object.entries(SECTIONS)) {
    const rs = rows.filter((r) => r.section === key);
    counts.push(`| [${s[l]}](#${anchor(sectionTitle(key, l))}) | ${count(rs, "keep")} | ${count(rs, "drop")} | ${count(rs, "ask")} |`);
  }
  counts.push(`| **${ko ? "합계" : "Total"}** | **${count(rows, "keep")}** | **${count(rows, "drop")}** | **${count(rows, "ask")}** |`);

  const asks = rows.filter((r) => r.decision === "ask");
  const ask = asks.length
    ? asks.map((r) => `- **${r.label[l]}**: ${r.what[l]}. ${r.why[l]}.`).join("\n")
    : (ko ? "지금은 없어요." : "Nothing right now.");

  const body: string[] = [];
  let n = 0;
  for (const [key, s] of Object.entries(SECTIONS)) {
    const rs = rows.filter((r) => r.section === key && r.decision !== "drop");
    if (!rs.length) continue;
    body.push(`## ${sectionTitle(key, l)}`, "");
    n++;
    for (const [g, gt] of Object.entries(s.groups)) {
      const gr = rs.filter((r) => r.group === g);
      if (!gr.length) continue;
      body.push(`### ${gt[l]}`, "", ...table(gr, l), "");
    }
  }
  const drops = rows.filter((r) => r.decision === "drop");
  body.push(`## ${sectionTitle("drop", l)}`, "",
    ko ? "새 맥에 설치하지 않아요. 이 맥에서 지우지도 않아요(지우는 건 원할 때만)."
      : "Not installed on the new Mac. Nothing is deleted from this Mac either.", "");
  for (const [key, s] of Object.entries(SECTIONS)) {
    const dr = drops.filter((r) => r.section === key);
    if (!dr.length) continue;
    body.push(`### ${s[l]}`, "", ...table(dr, l, false), "");
  }
  return { counts: counts.join("\n"), ask, catalog: body.join("\n").trimEnd() };
}

function sectionTitle(key: string, l: Lang): string {
  const order = ["app", "cli", "job", "setting", "secret", "elsewhere"];
  if (key === "drop") return l === "ko" ? `${order.length + 1}. 두고 가는 것` : `${order.length + 1}. Left behind`;
  if (key === "leftover") return sectionTitle("drop", l);
  return `${order.indexOf(key) + 1}. ${SECTIONS[key][l]}`;
}

function anchor(title: string): string {
  return title.toLowerCase().replace(/[^\p{L}\p{N} -]/gu, "").replaceAll(" ", "-");
}

function fillMarkers(doc: string, blocks: Record<string, string>, file: string): string {
  let out = doc;
  for (const [k, v] of Object.entries(blocks)) {
    const re = new RegExp(`(<!-- ${k}:begin -->\\n)[\\s\\S]*?(<!-- ${k}:end -->)`);
    if (!re.test(out)) throw new Error(`${file}: missing <!-- ${k}:begin --> / <!-- ${k}:end --> markers`);
    out = out.replace(re, (_m, a, b) => `${a}${v}\n${b}`);
  }
  return out;
}

// `pick` chooses the rows (default: every keep row). The lazymac app's Catalog.setupFiles must give the same lists.
export function setupFiles(rows: Row[], pick: (r: Row) => boolean = (r) => r.decision === "keep",
  head = "# Generated by `bun bin/catalog.ts render` from catalog.tsv (keep items only). Do not edit.\n"): Record<string, string> {
  const keep = rows.filter(pick);
  const of = (how: string) => keep.filter((r) => r.how === how);
  const trusted = (ref: string) => (ref.split("/").length === 3 ? ", trusted: true" : "");
  // A package from a third-party tap needs that tap even when the tap row itself was not picked.
  const taps = of("tap").map((r) => r.ref);
  for (const r of [...of("brew"), ...of("cask")]) {
    const p = r.ref.split("/");
    if (p.length === 3 && !taps.includes(`${p[0]}/${p[1]}`)) taps.push(`${p[0]}/${p[1]}`);
  }
  const brewfile = [
    ...taps.map((t) => `tap "${t}"`),
    ...of("brew").map((r) => `brew "${r.ref}"${trusted(r.ref)}`),
    ...of("cask").map((r) => `cask "${r.ref}"${trusted(r.ref)}`),
    ...of("mas").map((r) => `mas "${r.name}", id: ${r.ref}`),
    ...of("uv").map((r) => `uv "${r.ref}"`),
  ];
  const lines = (how: string, f: (r: Row) => string) => head + of(how).map(f).join("\n") + "\n";
  const version = (how: string) => (rows.find((r) => r.how === how && r.decision === "keep") ?? rows.find((r) => r.how === how))?.ref ?? "";
  const node = version("nvm");
  const py = version("uv-python");
  return {
    "setup/Brewfile": head + brewfile.join("\n") + "\n",
    "setup/npm.txt": lines("npm", (r) => r.ref),
    "setup/bun.txt": lines("bun", (r) => r.ref),
    "setup/scripts.tsv": lines("script", (r) => `${r.ids[0]}\t${r.ref}`),
    "setup/downloads.tsv": head + keep.filter((r) => r.how === "download" || r.how === "build")
      .map((r) => `${r.name}\t${r.ref}\t${installedPath(r)}`).join("\n") + "\n",
    "setup/jobs.txt": lines("register", (r) => r.ids[0]),
    // Apps LazyMac never installs: the restore must tell the user to install each one by hand.
    "setup/byhand.tsv": head + of("byhand").filter((r) => r.section === "app").map((r) => `${r.name}\t${r.ref || "-"}`).join("\n") + "\n",
    "setup/releases.tsv": lines("release", (r) => {
      const [repo, pattern] = r.ref.split("#");
      return `${r.name}\t${repo}\t${pattern || "-"}\t${installedPath(r)}`;
    }),
    "setup/versions.env": `${head}NODE_VERSION=${node}\nPYTHON_VERSION=${py}\n`,
  };
}

function installedPath(r: Row): string {
  if (r.section === "app") return `/Applications/${r.ids[0]}.app`;
  if (r.group === "fonts") return `~/Library/Fonts/${r.ids[0]}*`;
  return `~/.local/bin/${r.ids[0]}`;
}

function rendered(rows: Row[]): Record<string, string> {
  return setupFiles(rows);
}

type Found = { kind: string; id: string; alt?: string[] };

function readInventory(dir: string): Found[] {
  const read = (f: string) => (existsSync(join(dir, f)) ? readFileSync(join(dir, f), "utf8").split("\n") : []);
  const out: Found[] = [];
  for (const l of read("apps.tsv")) {
    const [app, src, , , bid, , team] = l.split("\t");
    if (!l || l.startsWith("#") || src === "apple") continue;
    // A catalog id matches by name, by bundle id, or by "<bundle id>@<team id>" (the strict form).
    const alt = bid ? [bid, ...(team && team !== "-" ? [`${bid}@${team}`] : [])] : [];
    out.push({ kind: "app", id: app, alt });
  }
  for (const l of read("brew-leaves.tsv")) if (l && !l.startsWith("#")) out.push({ kind: "brew", id: l.split("\t")[0] });
  for (const l of read("Brewfile")) {
    const m = l.match(/^(tap|cask) "([^"]+)"/);
    if (m) out.push({ kind: m[1], id: m[2] });
  }
  for (const l of read("mas.txt")) {
    const m = l.trim().match(/^(\d+)/);
    if (m) out.push({ kind: "mas", id: m[1] });
  }
  let sec = "";
  for (const l of read("cli-global.txt")) {
    if (l.startsWith("## ")) { sec = l.split(" ")[1]; continue; }
    if (!l.trim()) continue;
    if (sec === "bun" || sec === "npm") {
      const pkg = l.trim().replace(/@[^@]*$/, "");
      if (pkg !== "npm") out.push({ kind: sec, id: pkg });
    } else if (sec === "uv") out.push({ kind: "uv", id: l.trim().split(" ")[0] });
  }
  for (const l of read("launchd.tsv")) if (l && !l.startsWith("#")) out.push({ kind: "job", id: l.split("\t")[1] });
  for (const l of read("local-bin.tsv")) if (l && !l.startsWith("#")) out.push({ kind: "bin", id: l.split("\t")[0] });
  for (const l of read("fonts.txt")) if (l.trim()) out.push({ kind: "font", id: l.trim() });
  return out;
}

function matches(r: Row, f: Found): boolean {
  switch (f.kind) {
    case "app": return r.section === "app" && [f.id, ...(f.alt ?? [])].some((k) => r.ids.includes(k));
    case "job": return r.section === "job" && r.ids.includes(f.id);
    case "bin": return r.section === "cli" && r.ids.includes(f.id);
    case "font": return r.group === "fonts" && r.ids.some((p) => f.id.startsWith(p));
    case "brew": return r.how === "brew" && r.ref === f.id;
    case "tap": return r.how === "tap" && r.ref === f.id;
    // A by-hand app row can claim the cask that happens to be installed ("cask:<token>" in its ids).
    case "cask": return (r.how === "cask" && r.ref === f.id) || (r.how === "byhand" && r.ids.includes(`cask:${f.id}`));
    case "mas": return r.how === "mas" && r.ref === f.id;
    default: return r.how === f.kind && r.ref === f.id;
  }
}

const visible = (r: Row) => r.section === "app" || r.section === "job" || r.group === "fonts" ||
  ["brew", "tap", "mas", "npm", "bun", "uv"].includes(r.how) || (r.how === "cask" && r.section === "cli");

function gone(rows: Row[], found: Found[]): Row[] {
  return rows.filter((r) => visible(r) && !r.ids.some((id) => found.some((f) => matches({ ...r, ids: [id] }, f))));
}

const PRUNE_LIMIT = Number(process.env.LAZYMAC_PRUNE_LIMIT ?? 10);
// Every scan file the visible rows depend on; an empty one means the scan failed (or, on another Mac, that
// the tool is not installed there).
const NEED = ["apps.tsv", "Brewfile", "brew-leaves.tsv", "launchd.tsv", "fonts.txt", "cli-global.txt", "mas.txt"];

const hasContent = (dir: string, f: string) => existsSync(join(dir, f)) &&
  readFileSync(join(dir, f), "utf8").split("\n").some((l) => l.trim() && !l.startsWith("#"));

// The scan files a visible row can be seen in.
function scanFiles(r: Row): string[] {
  if (r.section === "app") return ["apps.tsv"];
  if (r.section === "job") return ["launchd.tsv"];
  if (r.group === "fonts") return ["fonts.txt"];
  if (r.how === "brew") return ["brew-leaves.tsv", "Brewfile"];
  if (r.how === "tap" || r.how === "cask") return ["Brewfile"];
  if (r.how === "mas") return ["mas.txt"];
  return ["cli-global.txt"];
}

// Everything a scan saw. A formula that became a dependency drops out of brew leaves but is still
// installed, so Brewfile counts too.
function scan(dir: string): Found[] {
  const found = readInventory(dir);
  if (existsSync(join(dir, "Brewfile"))) {
    for (const l of readFileSync(join(dir, "Brewfile"), "utf8").split("\n")) {
      const m = l.match(/^brew "([^"]+)"/);
      if (m) found.push({ kind: "brew", id: m[1] });
    }
  }
  return found;
}

// Macs with a scan: inventory/<host>/ folders that have at least one scan file.
export function hosts(root = INVENTORY): string[] {
  if (!existsSync(root)) return [];
  return readdirSync(root).filter((h) => statSync(join(root, h)).isDirectory() && NEED.some((f) => existsSync(join(root, h, f)))).sort();
}

function prune(rows: Row[], self: string): number {
  const macs = hosts();
  if (!macs.includes(self)) { console.error(`prune: refusing, no scan for this Mac (${self}) in inventory/`); return 1; }
  const empty = NEED.filter((f) => !hasContent(join(INVENTORY, self), f));
  if (empty.length) { console.error(`prune: refusing, empty or missing scan files: ${empty.join(", ")}`); return 1; }
  // A row goes only when every Mac's scan shows it gone. A Mac whose scan file for that kind is empty
  // cannot show it gone, so it keeps the row.
  let out = rows.filter(visible);
  for (const h of macs) {
    const dir = join(INVENTORY, h);
    const goneHere = new Set(gone(out, scan(dir)).filter((r) => scanFiles(r).every((f) => hasContent(dir, f))));
    out = out.filter((r) => goneHere.has(r));
  }
  if (out.length > PRUNE_LIMIT) {
    console.error(`prune: refusing, ${out.length} rows would go (limit ${PRUNE_LIMIT}): ${out.map((r) => r.name).join(", ")}`);
    return 1;
  }
  if (out.length) {
    const file = join(ROOT, "catalog.tsv");
    const isGone = (line: string) => {
      const [section, , id, name, , , , ref] = line.split("\t");
      return out.some((r) => r.section === section && r.ids.join(",") === id && r.name === name && r.ref === ref);
    };
    const kept = readFileSync(file, "utf8").split("\n").filter((l) => l.startsWith("#") || !isGone(l));
    writeFileSync(file, kept.join("\n"));
  }
  console.log(`removed from every Mac (${macs.join(", ")}): ${out.length}`);
  for (const r of out) console.log(`  - ${r.section}/${r.group}\t${r.name}\t(${r.decision})`);
  return 0;
}

function check(rows: Row[], dir: string | null, self: string): number {
  // One folder given (for example a scan right after setup): that folder only. Else every Mac in inventory/.
  const scans = dir ? [{ host: self, dir }] : hosts().map((h) => ({ host: h, dir: join(INVENTORY, h) }));
  const mine = scans.find((s) => s.host === self) ?? (dir ? scans[0] : undefined);
  const unclassified: { host: string; f: Found }[] = [];
  for (const s of scans) {
    for (const f of readInventory(s.dir)) {
      if (rows.some((r) => matches(r, f)) || unclassified.some((u) => u.f.kind === f.kind && u.f.id === f.id)) continue;
      unclassified.push({ host: s.host, f });
    }
  }
  const missing = mine ? gone(rows, readInventory(mine.dir)).filter((r) => r.decision === "keep") : [];
  const unknown = unknownGroups(rows);
  const stale = Object.entries(rendered(rows)).filter(([f, v]) => !existsSync(join(ROOT, f)) || readFileSync(join(ROOT, f), "utf8") !== v).map(([f]) => f);

  console.log(`inventory: ${scans.map((s) => s.dir.replace(ROOT + "/", "")).join(", ") || "(none)"} (this Mac: ${self})`);
  console.log(`unclassified: ${unclassified.length}`);
  for (const u of unclassified) console.log(`  + ${u.f.kind}\t${u.f.id}${u.host === self ? "" : ` (${u.host})`}   (new: add a row to catalog.tsv)`);
  console.log(`keep items not found on this Mac: ${mine ? missing.length : "no scan for this Mac"}`);
  for (const r of missing) console.log(`  - ${r.section}/${r.group}\t${r.name}\t(${newMac(r, "en")})`);
  console.log(`out of date: ${stale.length}${stale.length ? ` (${stale.join(", ")}; run: bun bin/catalog.ts render)` : ""}`);
  console.log(`unknown groups: ${unknown.length}`);
  for (const r of unknown) console.log(`  ? ${r.section}/${r.group}\t${r.name}   (add the group to groups.tsv)`);
  return unclassified.length || stale.length || unknown.length ? 1 : 0;
}

// ---- profiles ----

export class ProfileError extends Error {}
type Op = { add: boolean; group?: string; key?: string };
export type Profile = { name: string; from: string | null; ops: Op[]; skip: string[] };
const STEP_NAMES = ["brew", "node", "bun", "python", "scripts", "releases", "dotfiles", "secrets", "repos", "jobs", "downloads", "check"];

export const keyOf = (r: Row) => `${r.section}/${r.ids.join(",")}`;

export function parseProfile(name: string, text: string): Profile {
  const p: Profile = { name, from: null, ops: [], skip: [] };
  for (const [i, raw] of text.split("\n").entries()) {
    const line = raw.replace(/\s+#.*$/, "").trim();
    if (!line || line.startsWith("#")) continue;
    let m: RegExpMatchArray | null;
    if ((m = line.match(/^from\s+(\S+)$/))) {
      if (p.from) throw new ProfileError(`${name} line ${i + 1}: a second from line`);
      p.from = m[1];
    } else if ((m = line.match(/^([+-])\s+group\s+(\S+\/\S+)$/))) p.ops.push({ add: m[1] === "+", group: m[2] });
    else if ((m = line.match(/^([+-])\s+(\S+?\/.+)$/))) p.ops.push({ add: m[1] === "+", key: m[2].trim() });
    else if ((m = line.match(/^skip\s+(.+)$/))) {
      for (const s of m[1].split(/\s+/)) {
        if (!STEP_NAMES.includes(s)) throw new ProfileError(`${name} line ${i + 1}: unknown step ${s}`);
        p.skip.push(s);
      }
    } else throw new ProfileError(`${name} line ${i + 1}: cannot read "${line}"`);
  }
  return p;
}

export function loadProfile(name: string, dir = PROFILES): Profile {
  if (!/^[a-z0-9][a-z0-9-]*$/.test(name)) throw new ProfileError(`bad profile name: ${name} (use a-z, 0-9 and -)`);
  const f = join(dir, `${name}.txt`);
  if (!existsSync(f)) throw new ProfileError(`no profile ${name} (profiles/${name}.txt)`);
  return parseProfile(name, readFileSync(f, "utf8"));
}

function applyOps(rows: Row[], set: Set<string>, p: Profile) {
  for (const op of p.ops) {
    let hit: Row[];
    if (op.group) {
      const [s, g] = op.group.split("/");
      if (!SECTIONS[s]?.groups[g]) throw new ProfileError(`${p.name}: no group ${op.group} in groups.tsv`);
      // A group adds its ✅ and ❓ rows; a ⛔ leave row comes in only when named on its own line.
      hit = rows.filter((r) => r.section === s && r.group === g && (!op.add || r.decision !== "drop"));
    } else {
      hit = rows.filter((r) => keyOf(r) === op.key);
      if (!hit.length) throw new ProfileError(`${p.name}: no item ${op.key} in catalog.tsv`);
    }
    for (const r of hit) op.add ? set.add(keyOf(r)) : set.delete(keyOf(r));
  }
}

function baseSet(rows: Row[], p: Profile, seen: string[], dir: string): Set<string> {
  if (!p.from) throw new ProfileError(`${p.name} is an add-on profile (no from line); start with a base profile`);
  if (seen.includes(p.name)) throw new ProfileError(`profile loop: ${[...seen, p.name].join(" -> ")}`);
  const set = p.from === "keep" ? new Set(rows.filter((r) => r.decision === "keep").map(keyOf))
    : p.from === "empty" ? new Set<string>()
    : baseSet(rows, loadProfile(p.from, dir), [...seen, p.name], dir);
  applyOps(rows, set, p);
  return set;
}

// A base profile, then add-ons on top in order. An add-on's lines apply to what the base picked.
export function resolveProfiles(rows: Row[], base: Profile, addOns: Profile[], dir = PROFILES): { keys: Set<string>; skip: string[] } {
  const keys = baseSet(rows, base, [], dir);
  const skip = [...base.skip];
  for (const a of addOns) {
    if (a.from) throw new ProfileError(`${a.name} is a base profile (it has a from line); only add-ons go after the first name`);
    applyOps(rows, keys, a);
    for (const s of a.skip) if (!skip.includes(s)) skip.push(s);
  }
  return { keys, skip };
}

function resolveNames(rows: Row[], names: string): { keys: Set<string>; skip: string[] } {
  const [b, ...rest] = names.split(",").map((n) => n.trim()).filter(Boolean);
  if (!b) throw new ProfileError("no profile name");
  return resolveProfiles(rows, loadProfile(b), rest.map((n) => loadProfile(n)));
}

function writeProfile(rows: Row[], names: string, out: string) {
  const { keys, skip } = resolveNames(rows, names);
  mkdirSync(out, { recursive: true });
  const head = `# Generated by \`bun bin/catalog.ts profile ${names}\` from catalog.tsv. Do not edit.\n`;
  for (const [f, v] of Object.entries(setupFiles(rows, (r) => keys.has(keyOf(r)), head))) writeFileSync(join(out, f.replace(/^setup\//, "")), v);
  writeFileSync(join(out, "skip.txt"), head + skip.map((s) => s + "\n").join(""));
  console.log(`profile ${names}: ${rows.filter((r) => keys.has(keyOf(r))).length} items, skip: ${skip.join(" ") || "-"} -> ${out}`);
}

function compare(rows: Row[], picked: Set<string>, host: string, json: boolean): number {
  const dir = join(INVENTORY, host);
  if (!hosts().includes(host)) throw new ProfileError(`no scan for ${host} in inventory/ (run bin/scan.sh on that Mac)`);
  const found = scan(dir);
  const item = (r: Row) => ({ key: keyOf(r), name: r.name, name_ko: r.label.ko, section: r.section, group: r.group, decision: r.decision });
  const seen = (r: Row) => gone([r], found).length === 0;
  const comparable = rows.filter(visible);
  const missing = comparable.filter((r) => picked.has(keyOf(r)) && !seen(r));
  const extra = comparable.filter((r) => !picked.has(keyOf(r)) && seen(r));
  const same = comparable.filter((r) => picked.has(keyOf(r)) && seen(r)).length;
  const notChecked = rows.filter((r) => picked.has(keyOf(r)) && !visible(r)).length;
  const unlisted = readInventory(dir).filter((f) => !rows.some((r) => matches(r, f))).length;
  const scanned = statSync(join(dir, existsSync(join(dir, "versions.txt")) ? "versions.txt" : NEED.find((f) => existsSync(join(dir, f)))!)).mtime.toISOString();
  if (json) {
    console.log(JSON.stringify({ host, scanned, missing: missing.map(item), extra: extra.map(item), same, notChecked, unlisted }));
    return 0;
  }
  console.log(`compared with ${host} (scanned ${scanned})`);
  console.log(`missing (would be installed): ${missing.length}`);
  for (const r of missing) console.log(`  + ${keyOf(r)}\t${r.name}`);
  console.log(`extra on this Mac (shown only, never deleted): ${extra.length}`);
  for (const r of extra) console.log(`  = ${keyOf(r)}\t${r.name}`);
  console.log(`same: ${same}`);
  console.log(`not checked (no scan for these kinds): ${notChecked}`);
  console.log(`on the Mac but not in catalog.tsv: ${unlisted}`);
  return 0;
}

// machines.tsv: host -> role (main | extra) and profiles. A Mac not listed is extra with the pro profile.
export function machine(host: string): { role: "main" | "extra"; profiles: string } {
  const f = process.env.LAZYMAC_MACHINES ?? join(ROOT, "machines.tsv");
  const lines = existsSync(f) ? readFileSync(f, "utf8").split("\n").filter((l) => l.trim() && !l.startsWith("#")).slice(1) : [];
  for (const l of lines) {
    const [h, role, profiles] = l.split("\t");
    if (h === host) return { role: role === "main" ? "main" : "extra", profiles: profiles?.trim() || "pro" };
  }
  return { role: "extra", profiles: "pro" };
}

function flag(args: string[], name: string): string | undefined {
  const i = args.indexOf(name);
  return i >= 0 ? args[i + 1] : undefined;
}

if (import.meta.main) {
  const args = process.argv.slice(2);
  const [cmd, arg] = args;
  const rows = parseCatalog(readFileSync(join(ROOT, "catalog.tsv"), "utf8"));
  try {
    if (cmd === "render") {
      requireMain(thisHost());
      const unknown = unknownGroups(rows);
      if (unknown.length) {
        console.error(`render: groups missing from groups.tsv: ${[...new Set(unknown.map((r) => `${r.section}/${r.group}`))].join(", ")}`);
        process.exit(1);
      }
      mkdirSync(join(ROOT, "setup"), { recursive: true });
      for (const [f, v] of Object.entries(rendered(rows))) writeFileSync(join(ROOT, f), v);
      console.log(`rendered ${rows.length} rows: keep ${count(rows, "keep")}, leave ${count(rows, "drop")}, your call ${count(rows, "ask")}`);
      await syncData();
    } else if (cmd === "check") {
      process.exit(check(rows, arg ? resolve(arg) : null, thisHost()));
    } else if (cmd === "prune") {
      const host = flag(args, "--host") ?? thisHost();
      requireMain(thisHost());
      const code = prune(rows, host);
      if (code === 0) await syncData();
      process.exit(code);
    } else if (cmd === "profile" && arg && args[2]) {
      writeProfile(rows, arg, resolve(args[2]));
    } else if (cmd === "compare" && arg) {
      const file = flag(args, "--file");
      const picked = file ? resolveProfiles(rows, parseProfile("selection", readFileSync(resolve(file), "utf8")), []).keys
        : resolveNames(rows, arg).keys;
      process.exit(compare(rows, picked, flag(args, "--host") ?? thisHost(), args.includes("--json")));
    } else if (cmd === "host") {
      console.log(thisHost());
    } else if (cmd === "machine") {
      const m = machine(flag(args, "--host") ?? thisHost());
      console.log(`${m.role}\t${m.profiles}`);
    } else {
      console.error("usage: bun bin/catalog.ts render | check [inventory-dir] | prune [--host h] | profile <base[,add-on...]> <dir>\n" +
        "       | compare <base[,add-on...]> | --file <profile.txt> [--host h] [--json] | host | machine [--host h]");
      process.exit(2);
    }
  } catch (e) {
    if (e instanceof ProfileError) { console.error(`profile: ${e.message}`); process.exit(2); }
    throw e;
  }
}
