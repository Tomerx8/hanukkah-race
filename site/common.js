// Shared helpers for the player app, the TV board and the admin page.
(function () {
  const cfg = window.GAME_CONFIG || {};
  const isLocal = /^(localhost|127\.0\.0\.1)$/.test(location.hostname);
  // On localhost the test mock server (test/mock-server.js) stands in for Supabase.
  const BASE = (isLocal ? location.origin : (cfg.supabaseUrl || '')).replace(/\/$/, '');
  const KEY = cfg.supabaseKey || 'local';

  const ERRORS = {
    BAD_TEAM: 'הצוות לא נמצא. היכנסו שוב.',
    BAD_PIN_FORMAT: 'הקוד צריך להיות 4 ספרות.',
    BAD_PIN: 'קוד הצוות שגוי.',
    BAD_NAME: 'שם הצוות צריך להיות בין 2 ל-30 תווים.',
    NAME_TAKEN: 'כבר יש צוות בשם הזה. בחרו שם אחר, או הצטרפו אליו.',
    NO_SUCH_TEAM: 'אין צוות בשם הזה.',
    REGISTRATION_CLOSED: 'המשחק כבר התחיל, ואי אפשר לפתוח צוות חדש. הצטרפו לצוות קיים.',
    BAD_PASSWORD: 'סיסמה שגויה.',
    PASSWORD_TOO_SHORT: 'בחרו סיסמה של 6 תווים לפחות.',
    ALREADY_STARTED: 'המשחק כבר התחיל. כדי להתחיל מחדש, אפסו אותו.',
    NO_STATIONS: 'אין תחנות פעילות.',
    NO_TEAMS: 'עוד לא נרשם אף צוות.',
    GAME_RUNNING: 'אי אפשר למחוק תחנה בזמן משחק. אפשר לכבות אותה.',
    NOT_CONFIGURED: 'האתר עוד לא מחובר למסד הנתונים (config.js).',
    NETWORK: 'אין חיבור לרשת. נסו שוב.'
  };

  class GameError extends Error {
    constructor(code, raw) { super(ERRORS[code] || raw || code); this.code = code; }
  }

  async function rpc(fn, args) {
    if (!BASE) throw new GameError('NOT_CONFIGURED');
    let res;
    try {
      res = await fetch(`${BASE}/rest/v1/rpc/${fn}`, {
        method: 'POST',
        headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'application/json' },
        body: JSON.stringify(args || {})
      });
    } catch (e) { throw new GameError('NETWORK'); }
    const text = await res.text();
    let data = null; try { data = text ? JSON.parse(text) : null; } catch (e) { /* ignore */ }
    if (!res.ok) {
      const msg = (data && data.message) || text || String(res.status);
      const code = (msg.match(/[A-Z][A-Z_]{3,}/) || [msg])[0];
      throw new GameError(code, msg);
    }
    return data;
  }

  async function uploadPhoto(path, blob) {
    const res = await fetch(`${BASE}/storage/v1/object/photos/${path}`, {
      method: 'POST',
      headers: { apikey: KEY, Authorization: `Bearer ${KEY}`, 'Content-Type': 'image/jpeg' },
      body: blob
    });
    // 409/400 "already exists" means an earlier attempt got through.
    if (res.ok || res.status === 409) return true;
    const t = await res.text();
    if (/exists|Duplicate/i.test(t)) return true;
    throw new Error('upload ' + res.status);
  }

  const photoUrl = (path) => `${BASE}/storage/v1/object/public/photos/${path}`;

  // Shrink a camera photo to at most 1600px so it uploads fast on mobile data.
  async function compressImage(file, maxSide = 1600, quality = 0.8) {
    try {
      const bmp = await createImageBitmap(file, { imageOrientation: 'from-image' });
      const scale = Math.min(1, maxSide / Math.max(bmp.width, bmp.height));
      const c = document.createElement('canvas');
      c.width = Math.round(bmp.width * scale); c.height = Math.round(bmp.height * scale);
      c.getContext('2d').drawImage(bmp, 0, 0, c.width, c.height);
      return await new Promise((r) => c.toBlob((b) => r(b || file), 'image/jpeg', quality));
    } catch (e) { return file; }
  }

  function fmtDuration(sec) {
    sec = Math.max(0, Math.floor(sec));
    const h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60), s = sec % 60;
    const mm = String(m).padStart(h ? 2 : 1, '0'), ss = String(s).padStart(2, '0');
    return h ? `${h}:${mm}:${ss}` : `${mm}:${ss}`;
  }

  function esc(s) {
    return String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  }
  // Escaped text with line breaks kept.
  const textHtml = (s) => esc(s).replace(/\n/g, '<br>');

  const store = {
    get(k) { try { return JSON.parse(localStorage.getItem(k)); } catch (e) { return null; } },
    set(k, v) { try { localStorage.setItem(k, JSON.stringify(v)); } catch (e) { /* private mode */ } },
    del(k) { try { localStorage.removeItem(k); } catch (e) { /* ignore */ } }
  };

  window.Game = { rpc, uploadPhoto, photoUrl, compressImage, fmtDuration, esc, textHtml, store, GameError, BASE };
})();
