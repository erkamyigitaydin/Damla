// damla.erkamaydin.com. The site is static (docs/); this worker only runs for:
//   /appcast.xml      Sparkle's update feed, from R2; each check is counted
//   /latest.json      {"version", "file"} of the newest release, for the site's download button
//   /download/latest  a redirect to the newest dmg
//   /download/<dmg>   the dmg itself, from R2; each download is counted
//
// Privacy: no IP address and no identifier is stored. A visitor is a SHA-256 of a secret salt, the day,
// the IP and the user agent; it only tells "counted already today" and is deleted after two days.

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (request.method !== "GET" && request.method !== "HEAD") return new Response("Method not allowed", { status: 405 });
    if (url.pathname === "/appcast.xml") return appcast(request, env, ctx);
    if (url.pathname === "/latest.json") return latestJSON(env);
    if (url.pathname === "/download/latest") {
      const latest = await readLatest(env);
      return latest ? Response.redirect(`${url.origin}/download/${latest.file}`, 302) : new Response("No release", { status: 404 });
    }
    if (url.pathname.startsWith("/download/")) return download(request, env, ctx, url.pathname.slice("/download/".length));
    return env.ASSETS.fetch(request);
  },
};

async function appcast(request, env, ctx) {
  const object = await env.FILES.get("appcast.xml");
  if (!object) return new Response("Feed missing", { status: 503 });
  // Sparkle's user agent: "Damla/0.8.2 Sparkle/2.7.0". Anything else (browsers, bots) is served, not counted.
  const agent = request.headers.get("user-agent") || "";
  const match = agent.match(/^Damla\/([\w.]+)/);
  if (match) ctx.waitUntil(countCheck(env, request, agent, match[1]).catch(() => {}));
  return new Response(request.method === "HEAD" ? null : object.body, {
    headers: { "content-type": "application/xml; charset=utf-8", "cache-control": "no-cache" },
  });
}

async function readLatest(env) {
  const object = await env.FILES.get("latest.json");
  return object ? object.json() : null;
}

async function latestJSON(env) {
  const latest = await readLatest(env);
  if (!latest) return new Response("{}", { status: 404, headers: { "content-type": "application/json" } });
  return Response.json(latest, { headers: { "cache-control": "max-age=300" } });
}

async function download(request, env, ctx, file) {
  if (!/^Damla-[\w.]+\.dmg$/.test(file)) return new Response("Not found", { status: 404 });
  const object = await env.FILES.get(file, { range: request.headers, onlyIf: request.headers });
  if (!object) return new Response("Not found", { status: 404 });
  const headers = new Headers();
  object.writeHttpMetadata(headers);
  headers.set("etag", object.httpEtag);
  headers.set("accept-ranges", "bytes");
  headers.set("content-disposition", `attachment; filename="${file}"`);
  if (!("body" in object)) return new Response(null, { status: 304, headers });   // If-None-Match hit
  // A resumed download (a Range past the first byte) is the same download, counted once at its start.
  const range = request.headers.get("range");
  if (request.method === "GET" && (!range || /^bytes=0-/.test(range))) ctx.waitUntil(countDownload(env, file).catch(() => {}));
  let status = 200;
  if (object.range && range) {
    const { offset = 0, length = object.size - offset } = object.range;
    headers.set("content-range", `bytes ${offset}-${offset + length - 1}/${object.size}`);
    headers.set("content-length", String(length));
    status = 206;
  } else {
    headers.set("content-length", String(object.size));
  }
  return new Response(request.method === "HEAD" ? null : object.body, { status, headers });
}

async function countDownload(env, file) {
  const day = new Date().toISOString().slice(0, 10);
  await env.DB.prepare(
    "INSERT INTO downloads (day, file, count) VALUES (?, ?, 1) ON CONFLICT(day, file) DO UPDATE SET count = count + 1"
  ).bind(day, file).run();
}

async function countCheck(env, request, agent, version) {
  const day = new Date().toISOString().slice(0, 10);
  const ip = request.headers.get("cf-connecting-ip") || "";
  const visitor = await sha256(`${env.SALT}|${day}|${ip}|${agent}`);
  const fresh = await env.DB.prepare("INSERT OR IGNORE INTO seen (day, visitor) VALUES (?, ?)").bind(day, visitor).run();
  const installs = fresh.meta.changes > 0 ? 1 : 0;
  await env.DB.batch([
    env.DB.prepare(
      "INSERT INTO daily (day, version, checks, installs) VALUES (?, ?, 1, ?) " +
      "ON CONFLICT(day, version) DO UPDATE SET checks = checks + 1, installs = installs + excluded.installs"
    ).bind(day, version, installs),
    env.DB.prepare("DELETE FROM seen WHERE day < date(?, '-1 day')").bind(day),
  ]);
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(text));
  return [...new Uint8Array(digest)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
