// Drives the built history page (tests/snapshot.sh fixture, day 2026-01-02) in a WebView and presses the counts.
// Prints, after each press, "<pressed button>:<decision of each listed row>" (or "empty"), joined with "|".
// Usage: bun tests/history-filter.ts <site dir>
const dir = process.argv[2];
const srv = Bun.serve({
  port: 0,
  fetch: (r) => {
    const p = new URL(r.url).pathname;
    return new Response(Bun.file(dir + (p.endsWith("/") ? p + "index.html" : p)));
  },
});
const v = new Bun.WebView({ width: 1000, height: 800 });
try {
  await v.navigate(`http://localhost:${srv.port}/#2026-01-02`);
  await v.evaluate(`new Promise((resolve, reject) => {
    if (document.querySelector("#list h2")) { resolve(true); return; }
    const observer = new MutationObserver(() => {
      if (document.querySelector("#list h2")) {
        observer.disconnect(); clearTimeout(timeout); resolve(true);
      }
    });
    const timeout = setTimeout(() => { observer.disconnect(); reject(new Error("History list did not load")); }, 8000);
    observer.observe(document.documentElement, {childList:true, subtree:true});
  })`);
  const state = () =>
    v.evaluate(`[...document.querySelectorAll("[aria-pressed=true]")].map((b) => b.dataset.f).join() + ":" +
      ([...document.querySelectorAll("#list ul.rows .tag")].map((t) => t.textContent).join("") || (document.querySelector("#list > p") ? "empty" : ""))`);
  const out = [await state()];
  for (const k of ["keep", "keep", "drop", "ask", "total"]) {
    await v.evaluate(`document.querySelector("[data-f=${k}]").click()`);
    out.push(await state());
  }
  console.log(out.join("|"));
} finally {
  v.close();
  srv.stop(true);
}
