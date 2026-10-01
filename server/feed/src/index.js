// Damla update feed. Sparkle fetches /appcast.xml; the feed itself still lives in the GitHub repo
// (release.sh keeps committing it), this worker only passes it through and counts.
//
// Privacy: no IP address and no identifier is stored. A visitor is a SHA-256 of a secret salt, the day,
// the IP and the user agent; it only tells "counted already today" and is deleted after two days.

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    if (url.pathname !== "/appcast.xml") return new Response("Not found", { status: 404 });

    const upstream = await fetch(env.APPCAST_URL, { cf: { cacheTtl: 300, cacheEverything: true } });
    const body = await upstream.text();

    // Sparkle's user agent: "Damla/0.8.2 Sparkle/2.7.0". Anything else (browsers, bots) is served, not counted.
    const agent = request.headers.get("user-agent") || "";
    const match = agent.match(/^Damla\/([\w.]+)/);
    if (match && upstream.ok) ctx.waitUntil(count(env, request, agent, match[1]).catch(() => {}));

    return new Response(body, {
      status: upstream.status,
      headers: { "content-type": "application/xml; charset=utf-8", "cache-control": "no-cache" },
    });
  },
};

async function count(env, request, agent, version) {
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
