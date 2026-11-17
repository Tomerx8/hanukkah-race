// End-to-end run of a full game against the local mock. Screens go to ./shots.
const { chromium, devices } = require('playwright');
const fs = require('fs');
const BASE = 'http://localhost:8080/';
const SHOTS = __dirname + '/shots';

fs.mkdirSync(SHOTS, { recursive: true });
const PW = 'chanuka1';

async function api(fn, args = {}) {
  const r = await fetch(BASE + 'rest/v1/rpc/' + fn, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(args) });
  const j = await r.json(); if (!r.ok) throw new Error(fn + ': ' + j.message); return j;
}
const assert = (c, m) => { if (!c) throw new Error('ASSERT: ' + m); console.log('  ok -', m); };

(async () => {
  await api('admin_reset', { p_pw: PW, p_delete_teams: true });
  const browser = await chromium.launch();
  const phone = await browser.newContext({ ...devices['iPhone 13'] });
  const phone2 = await browser.newContext({ ...devices['Pixel 7'] });
  const tvCtx = await browser.newContext({ viewport: { width: 1920, height: 1080 } });
  const adminCtx = await browser.newContext({ viewport: { width: 1300, height: 900 } });
  const errors = [];
  for (const c of [phone, phone2, tvCtx, adminCtx]) c.on('page', (p) => p.on('pageerror', (e) => errors.push(e.message)));

  // --- registration
  const p1 = await phone.newPage();
  await p1.goto(BASE);
  await p1.screenshot({ path: SHOTS + '/01-join.png' });
  await p1.fill('#name', 'המכבים המהירים');
  await p1.fill('#pin', '1234');
  await p1.click('button[type=submit]');
  await p1.waitForSelector('text=מוכנים?');
  await p1.screenshot({ path: SHOTS + '/02-waiting.png' });
  assert(true, 'team created from the phone and waiting screen shown');

  // duplicate name
  const p2 = await phone2.newPage();
  await p2.goto(BASE);
  await p2.fill('#name', 'המכבים המהירים'); await p2.fill('#pin', '9999'); await p2.click('button[type=submit]');
  await p2.waitForSelector('text=כבר יש צוות בשם הזה');
  assert(true, 'duplicate team name rejected');
  // join with wrong then right pin
  await p2.click('text=הצטרפות לצוות');
  await p2.waitForSelector('option:has-text("המכבים המהירים")', { state: 'attached' });
  await p2.selectOption('#name', 'המכבים המהירים'); await p2.fill('#pin', '1111'); await p2.click('button[type=submit]');
  await p2.waitForSelector('text=קוד הצוות שגוי');
  await p2.fill('#pin', '1234'); await p2.click('button[type=submit]');
  await p2.waitForSelector('text=מוכנים?');
  assert(true, 'second phone joined the same team with the team code');

  // 10 more teams via API -> 11 teams
  const names = ['סביבונים', 'לביבות', 'הפכים', 'נס גדול', 'השמש', 'סופגניות', 'יהודה', 'החשמונאים', 'נרות', 'מודיעין'];
  const secrets = {};
  for (const [i, n] of names.entries()) secrets[n] = (await api('join_team', { p_name: n, p_pin: String(1000 + i), p_create: true })).secret;

  // --- TV lobby + admin
  const tv = await tvCtx.newPage();
  await tv.goto(BASE + 'tv.html');
  await tv.waitForSelector('.trow');
  await tv.waitForTimeout(500);
  await tv.screenshot({ path: SHOTS + '/10-tv-lobby.png' });
  const admin = await adminCtx.newPage();
  admin.on('dialog', (d) => d.accept());
  await admin.goto(BASE + 'admin.html');
  await admin.fill('#pw', 'wrongpass'); await admin.click('#lf button');
  await admin.waitForSelector('text=סיסמה שגויה');
  await admin.fill('#pw', PW); await admin.click('#lf button');
  await admin.waitForSelector('text=ממתין לזינוק');
  await admin.screenshot({ path: SHOTS + '/20-admin-before.png', fullPage: true });
  assert(true, 'admin login rejects wrong password, accepts right one');

  await admin.click('#start');
  await admin.waitForSelector('text=רץ');
  assert(true, 'admin started the game');

  // registration closed after start
  let closed = false;
  try { await api('join_team', { p_name: 'מאחרים', p_pin: '1234', p_create: true }); } catch (e) { closed = /REGISTRATION_CLOSED/.test(e.message); }
  assert(closed, 'new teams cannot register after the start');

  // --- routes: rotated starts
  let ov = await api('admin_overview', { p_pw: PW });
  const starts = ov.teams.map((t) => t.route[0]);
  const counts = {}; starts.forEach((s) => counts[s] = (counts[s] || 0) + 1);
  assert(Object.keys(counts).length === 8 && Math.max(...Object.values(counts)) === 2, `11 teams spread over 8 starting stations (1-2 per station): ${JSON.stringify(Object.values(counts))}`);
  assert(ov.teams.every((t) => new Set(t.route).size === 8), 'every route visits all 8 stations once');

  const team = ov.teams.find((t) => t.name === 'המכבים המהירים');
  const st = Object.fromEntries(ov.stations.map((s) => [s.id, s]));
  await tv.waitForTimeout(2500);
  await tv.screenshot({ path: SHOTS + '/11-tv-live-start.png' });

  // --- phone 1 plays the whole route
  await p1.waitForSelector('text=החידה שמובילה לתחנה 1', { timeout: 6000 });
  await p1.screenshot({ path: SHOTS + '/03-first-riddle.png' });
  assert(true, 'phone picked up the start by itself and shows the first location riddle');

  // scanning a station that is not ours
  const notOurs = team.route[3];
  await p1.goto(BASE + '?s=' + st[notOurs].token);
  await p1.waitForSelector('text=זה לא הקוד שאתם מחפשים');
  assert(true, 'a QR from later in the route does not open its question');
  // unknown token
  await p1.goto(BASE + '?s=deadbeef');
  await p1.waitForSelector('text=הקוד הזה לא מוכר');

  let lockTested = false;
  for (let i = 0; i < team.route.length; i++) {
    const s = st[team.route[i]];
    await p1.goto(BASE + '?s=' + s.token);
    if (s.kind === 'photo') {
      await p1.waitForSelector('text=משימת צילום');
      if (i === 0 || !fs.existsSync(SHOTS + '/05-photo-task.png')) await p1.screenshot({ path: SHOTS + '/05-photo-task.png' });
      await p1.setInputFiles('#photo', __dirname + '/sample.jpg');
      await p1.click('#sendPhoto');
    } else {
      await p1.waitForSelector('#answer');
      if (!lockTested) {
        await p1.fill('#answer', 'תשובה לא נכונה'); await p1.click('#sendAnswer');
        await p1.waitForSelector('text=לא נכון. נסו שוב');
        assert(await p1.isEnabled('#answer'), 'first wrong answer is free (no lock)');
        await p1.fill('#answer', 'עוד טעות'); await p1.click('#sendAnswer');
        await p1.waitForSelector('#lockBox:not(.hidden)');
        await p1.waitForTimeout(600);
        await p1.screenshot({ path: SHOTS + '/04-locked.png' });
        assert(!(await p1.isEnabled('#answer')), 'second wrong answer locks the team');
        const r = await api('submit_answer', { p_secret: (await p1.evaluate(() => JSON.parse(localStorage.race_team).secret)), p_token: s.token, p_answer: s.answers[0] });
        assert(r.result === 'locked', 'server refuses even a right answer during the lock');
        // admin releases lock
        await admin.click('text=שחרור נעילה');
        await admin.waitForTimeout(800);
        await p1.reload();
        await p1.waitForSelector('#answer:enabled');
        assert(true, 'admin "release lock" button unlocks the team');
        lockTested = true;
      }
      // answer with decoration to test normalising
      const a = s.answers[s.answers.length - 1];
      const typed = /^\d+$/.test(a) ? `התשובה היא ${a}!` : ` ${a.toUpperCase()}. `;
      await p1.fill('#answer', typed); await p1.click('#sendAnswer');
    }
    const label = i + 1 < team.route.length ? `החידה שמובילה לתחנה ${i + 2}` : 'החידה האחרונה';
    await p1.waitForSelector(`text=${label}`);
    if (i === 1) await p1.screenshot({ path: SHOTS + '/06-correct-next.png' });
    if (i === 3) {
      // the other phone of the team follows along
      await p2.reload();
      await p2.waitForSelector('text=תחנות שהושלמו: 4 מתוך 8');
      await p2.screenshot({ path: SHOTS + '/07-teammate-phone.png' });
      assert(true, "teammate's phone shows the shared progress (4/8)");
      // advance a few other teams for a nicer board
      ov = await api('admin_overview', { p_pw: PW });
      for (const [k, n] of names.entries()) {
        const t = ov.teams.find((x) => x.name === n);
        for (let j = 0; j < (k % 7) + 1; j++) {
          const s2 = st[t.route[j]];
          if (s2.kind === 'photo') await api('submit_photo', { p_secret: secrets[n], p_token: s2.token });
          else await api('submit_answer', { p_secret: secrets[n], p_token: s2.token, p_answer: s2.answers[0] });
        }
      }
      await tv.waitForTimeout(2500);
      await tv.screenshot({ path: SHOTS + '/12-tv-live.png' });
    }
  }
  assert(true, 'phone solved all 8 stations in its own order');
  await p1.screenshot({ path: SHOTS + '/08-final-riddle.png' });

  // scanning an already solved station
  await p1.goto(BASE + '?s=' + st[team.route[0]].token);
  await p1.waitForSelector('text=את התחנה הזאת כבר פתרתם');

  // another team scanning the finish early
  const early = await api('scan', { p_secret: secrets['לביבות'], p_token: ov.settings.finish_token });
  assert(early.scan.status === 'finish_early', 'finish QR does not count for a team that has stations left');

  // blackout
  await admin.click('[data-m=blackout]');
  await tv.waitForTimeout(2500);
  await tv.screenshot({ path: SHOTS + '/13-tv-blackout.png' });
  const board = await api('board');
  assert(board.mode === 'blackout' && board.teams.length === 0, 'blackout sends no progress data to the TV at all');

  // finish
  await p1.goto(BASE + '?s=' + ov.settings.finish_token);
  await p1.waitForSelector('text=סיימתם!');
  await p1.screenshot({ path: SHOTS + '/09-finished.png' });
  assert(true, 'finish QR stops the clock');

  // second team finishes via admin button route: solve all via API then scan finish
  const sv = ov.teams.find((x) => x.name === 'סביבונים');
  for (let j = 1; j < 8; j++) {
    const s2 = st[sv.route[j]];
    if (s2.kind === 'photo') await api('submit_photo', { p_secret: secrets['סביבונים'], p_token: s2.token });
    else await api('submit_answer', { p_secret: secrets['סביבונים'], p_token: s2.token, p_answer: s2.answers[0] });
  }
  const fin2 = await api('scan', { p_secret: secrets['סביבונים'], p_token: ov.settings.finish_token });
  assert(fin2.stage === 'finished', 'second team finished too');

  // judge photos (uploads were made flaky: first attempt fails, retry must succeed)
  await p1.waitForTimeout(4000);
  await admin.click('text=שיפוט תמונות');
  await admin.waitForSelector('.photo');
  ov = await api('admin_overview', { p_pw: PW });
  const mine = ov.photos.filter((p) => p.team === 'המכבים המהירים');
  assert(mine.length === 1 && mine.every((p) => p.uploaded), 'the photo uploaded after a failed first attempt (retry works)');
  await admin.reload();
  await admin.waitForSelector('.photo img');
  await admin.waitForTimeout(500);
  await admin.screenshot({ path: SHOTS + '/21-admin-judge.png' });
  await admin.fill('#pen-' + mine[0].id, '3');
  await admin.click(`[data-pen="${mine[0].id}"]`);
  await admin.waitForTimeout(800);
  ov = await api('admin_overview', { p_pw: PW });
  const pt = ov.teams.find((t) => t.name === 'המכבים המהירים');
  assert(pt.penalty_total === 180, 'photo penalty of 3 minutes adds 180s to the team');

  await admin.click('text=ניהול המשחק');
  await admin.waitForTimeout(800);
  await admin.screenshot({ path: SHOTS + '/22-admin-running.png', fullPage: true });
  await admin.click('[data-m=results]');
  await tv.waitForTimeout(2500);
  await tv.screenshot({ path: SHOTS + '/14-tv-results.png' });
  const res = await api('board');
  assert(res.teams[0].finished && res.teams[1].finished, 'results list finished teams first');

  await admin.click('text=תחנות וחידות');
  await admin.waitForTimeout(500);
  await admin.screenshot({ path: SHOTS + '/23-admin-stations.png' });
  // edit a station question from admin
  const f = await admin.$('form.station');
  await (await f.$('textarea[name=question]')).fill('שאלה חדשה לבדיקה');
  await (await f.$('button[type=submit]')).click();
  await admin.waitForSelector('text=התחנה נשמרה');
  ov = await api('admin_overview', { p_pw: PW });
  assert(ov.stations.some((s) => s.question === 'שאלה חדשה לבדיקה'), 'station text edited from the admin page');

  await admin.click('text=קודי QR להדפסה');
  await admin.waitForSelector('.qrcard svg');
  await admin.screenshot({ path: SHOTS + '/24-admin-qr.png' });
  assert((await admin.$$('.qrcard')).length === 10, '8 station QRs + finish QR + join QR');

  assert(errors.length === 0, 'no JavaScript errors on any page' + (errors.length ? ': ' + errors.join(' | ') : ''));
  await browser.close();
  console.log('ALL PASSED');
})().catch((e) => { console.error(e); process.exit(1); });
