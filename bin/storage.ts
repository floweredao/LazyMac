import { existsSync, readFileSync } from "node:fs";
import { homedir } from "node:os";
import { join, resolve } from "node:path";

const conf = process.env.LAZYMAC_STORAGE_CONF ?? join(homedir(), "Library/Application Support/lazymac/storage.conf");
const settings = new Map<string, string>();
if (existsSync(conf)) {
  for (const line of readFileSync(conf, "utf8").split("\n")) {
    const match = line.trim().match(/^(\w+)\s+(.+)$/);
    if (match) settings.set(match[1], match[2]);
  }
}
const expand = (p: string) => p === "~" ? homedir() : p.startsWith("~/") ? join(homedir(), p.slice(2)) : p;
export const dataRoot = resolve(expand(process.env.LAZYMAC_DATA ?? settings.get("data") ?? join(homedir(), "LazyMac-data")));

export async function syncData(): Promise<void> {
  const process = Bun.spawn(["/bin/zsh", join(import.meta.dir, "storage.sh"), "upload"], {
    env: { ...Bun.env, LAZYMAC_DATA: dataRoot }, stdout: "inherit", stderr: "inherit",
  });
  if (await process.exited !== 0) throw new Error("Data saved locally, but storage synchronization failed.");
}

export function requireMain(host: string): void {
  const text = readFileSync(join(dataRoot, "machines.tsv"), "utf8");
  if (!text.split("\n").some((l) => { const c = l.split("\t"); return c[0] === host && c[1] === "main"; })) {
    throw new Error("Only the main Mac may change shared data (machines.tsv).");
  }
}
