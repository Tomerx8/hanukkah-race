# מרוץ חנוכה – Hanukkah QR race

A Hebrew mobile web game: teams race through QR stations in the office, each in its own rotated order, then return to the conference room.

- `site/` – the website (plain HTML, no build step). Host it on GitHub Pages.
  - `index.html` – the player app (the QR codes open this page).
  - `tv.html` – the big-screen board (lobby / live / blackout / results).
  - `admin.html` – game control, riddle editor, photo judging, printable QR codes.
  - `config.js` – the Supabase project URL and publishable key.
- `sql/setup.sql` – the whole database. Run once in Supabase.
- `test/` – local mock server and an end-to-end test of a full game.

## Setup

The site is already connected to the Supabase project (`site/config.js`) and publishes itself to GitHub Pages on every push to `main`.

1. **Database** (once, and again after any change to `sql/setup.sql`): in Supabase open **SQL Editor → New query**, paste all of `sql/setup.sql`, press **Run**. Running it again later is safe; it keeps teams and riddles.
2. **Pages** (once): in this repository open **Settings → Pages** and set **Source: GitHub Actions**.
3. Open `https://tomerx8.github.io/hanukkah-race/admin.html`. **The first password you type becomes the admin password.** Do this right away.

Links: players `https://tomerx8.github.io/hanukkah-race/` · TV `…/tv.html` · admin `…/admin.html`.

## Before the game

1. **Stations tab**: write each station's *location riddle* (what leads the team to it), its *task*, and the accepted answers (one per line). Set the circle order so that walking from one station to the next makes sense. Edit the final riddle.
2. **QR tab**: print. Each code is on its own page. Scan every printed code with a phone before hanging it. Hang the **finish** code in the conference room, apart from that room's own station code.
3. Do a dry run: open the site on your phone, open a team, press start, play a station, then **Reset** (and delete teams) in the admin page.

## On the day

1. TV shows `tv.html` in **Lobby** mode, with a QR for joining. One person per team opens a team and picks a 4-digit code; teammates join with that code.
2. Admin → **🚀 Start**. Every phone shows its team's first riddle; the TV switches to **Live**.
3. When teams start heading back, press **Blackout**. At the end, press **Results**.
4. Keep the admin page open and press **🔔 Enable alerts** once. When a team sends its photo you get a chime, a yellow banner and a red badge on the **Photos** tab (plus a desktop notification where the browser allows it). **Approve** shows the team its next riddle at once; **Reject** asks the team to retake. You can also add a manual penalty per team.
5. If a QR goes missing, **Skip** moves that team past its current station. **Release lock** clears a lockout.

## Rules built in

- Station links are random, so a team cannot skip ahead or guess the next URL. Scanning another team's station shows "not your station".
- First wrong answer is free; each further miss locks the team for 20s, 40s, 80s… up to 5 minutes (editable).
- Answers ignore spaces, niqqud, punctuation and final letters. An answer that is only a number also matches a sentence containing it.
- Photo tasks wait for the admin: the team sees "waiting for the judge" until you approve, and gets a retake form if you reject. The photo upload keeps retrying, even across page reloads.
- Starting stations: teams are spread round-robin over the stations in registration order (11 teams on 8 stations → 1-2 per station). You can set a team's start station by hand before the start.

## Run locally

```
cd test && npm install
# Postgres 16 with the stub roles:  psql -f supabase_stub.sql -f ../sql/setup.sql
node mock-server.js        # http://localhost:8080
node e2e.js                # full game test
```
