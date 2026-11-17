// Local stand-in for Supabase: PostgREST-style /rest/v1/rpc + storage, plus the static site.
const http = require('http'), fs = require('fs'), path = require('path');
const { Pool } = require('pg');
const pool = new Pool({ host: '/tmp', user: 'postgres', database: process.env.DB || 'race' });
const SITE = path.join(__dirname, '..', 'site'), UP = path.join(__dirname, 'uploads');
fs.mkdirSync(UP, { recursive: true });
const types = { '.html': 'text/html; charset=utf-8', '.js': 'text/javascript', '.css': 'text/css', '.jpg': 'image/jpeg', '.png': 'image/png', '.svg': 'image/svg+xml' };
const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Headers': '*', 'Access-Control-Allow-Methods': '*' };
let uploadCalls = 0;
http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://x');
  const chunks = []; for await (const c of req) chunks.push(c); const body = Buffer.concat(chunks);
  if (req.method === 'OPTIONS') { res.writeHead(204, cors); return res.end(); }
  try {
    let m;
    if ((m = url.pathname.match(/^\/rest\/v1\/rpc\/(\w+)$/))) {
      const args = body.length ? JSON.parse(body) : {};
      const keys = Object.keys(args);
      const sql = `select public.${m[1]}(${keys.map((k, i) => `${k} => $${i + 1}`).join(', ')}) as r`;
      try {
        const r = await pool.query(sql, keys.map(k => args[k]));
        res.writeHead(200, { ...cors, 'Content-Type': 'application/json' });
        return res.end(JSON.stringify(r.rows[0].r));
      } catch (e) {
        res.writeHead(400, { ...cors, 'Content-Type': 'application/json' });
        return res.end(JSON.stringify({ code: e.code, message: e.message }));
      }
    }
    if ((m = url.pathname.match(/^\/storage\/v1\/object\/public\/photos\/(.+)$/))) {
      const f = path.join(UP, m[1].replace(/\//g, '__'));
      if (!fs.existsSync(f)) { res.writeHead(404, cors); return res.end(); }
      res.writeHead(200, { ...cors, 'Content-Type': 'image/jpeg' }); return res.end(fs.readFileSync(f));
    }
    if ((m = url.pathname.match(/^\/storage\/v1\/object\/photos\/(.+)$/)) && req.method === 'POST') {
      // FLAKY=1 fails the first upload attempt of every photo, to exercise the retry loop.
      if (process.env.FLAKY && (uploadCalls++ % 2 === 0)) { res.writeHead(503, cors); return res.end('flaky'); }
      fs.writeFileSync(path.join(UP, m[1].replace(/\//g, '__')), body);
      res.writeHead(200, { ...cors, 'Content-Type': 'application/json' }); return res.end('{"Key":"photos/' + m[1] + '"}');
    }
    let p = decodeURIComponent(url.pathname); if (p.endsWith('/')) p += 'index.html';
    const f = path.join(SITE, p);
    if (!f.startsWith(SITE) || !fs.existsSync(f)) { res.writeHead(404); return res.end('nf'); }
    res.writeHead(200, { 'Content-Type': types[path.extname(f)] || 'application/octet-stream' });
    res.end(fs.readFileSync(f));
  } catch (e) { res.writeHead(500); res.end(String(e)); }
}).listen(process.env.PORT || 8080, () => console.log('mock on', process.env.PORT || 8080));
