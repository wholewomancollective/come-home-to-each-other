# Come Home to Each Other - instructions for Claude

This is Jacqui McGregor's mother-daughter app, part of her business Whole Woman Collective. Jacqui owns it and is not a developer. She tells you what she wants in plain words. You make the change, show her, and publish only when she says yes.

## How to work with Jacqui

- Before you start any change, get the latest version: `git pull`.
- Make the change she asked for and nothing else. If her request is unclear, ask one short question.
- Show her what changed in plain words before publishing.
- Publish only after she says yes. Commit with a short plain message, then `git push` to `master`. The live app updates one to two minutes later.
- After publishing, load the live app and confirm the change is there.
- Never delete a file without asking her first.
- If a change looks wrong: `git revert` the last commit and push, then tell her the app is back to how it was.
- Explain things without technical words. If you must use one, say what it means.

## The app

One page, plain HTML, no build step.

| File | What it is |
|---|---|
| `index.html` | The whole app: screens, styles and logic |
| `sw.js` | Shows the phone notification |
| `manifest.webmanifest` | Lets the app be added to a phone's Home Screen. It deliberately has no `start_url`. Do not add one: it would break the invite link on iPhones. |
| `_backend/` | Set-up files for the app's engine in Supabase. Not part of the live app. |

Live at https://wholewomancollective.github.io/come-home-to-each-other/. Hosted free on GitHub Pages from the `master` branch of `wholewomancollective/come-home-to-each-other`. Everything in this folder is public on the internet.

## How it works

A mother and daughter each open the app on their own phone and are joined as a pair by a secret token carried in the invite link. What they write is saved in Supabase and shown on the other phone. The other phone also gets a notification, which never contains the words themselves.

The `SYNC` block near the top of the script in `index.html` holds three values: the Supabase project address, its publishable key and the public notification key. All three are public by design.

## Do not change without asking Jacqui

- The `SYNC` block in `index.html`.
- `manifest.webmanifest` and `sw.js`.
- Anything in `_backend/`.

## Privacy

- The words people write in this app are private between a mother and her daughter. Never read, list, copy or show the `words` column of the `chte_entries` table. Counting rows is fine.
- Never copy any names or words from Supabase into a file in this folder.

## Keys and passwords

- Never put a secret key, password or token in any file in this folder.
- The only keys allowed in `index.html` are the Supabase publishable key (starts with `sb_publishable_`) and the public notification key.
- Secret keys live in the Secrets page of her Supabase project and nowhere else.

## Connections

Jacqui has connected GitHub and Supabase to her Claude account in the browser (claude.ai, Customise, then Connectors). Both should show when she types `/mcp`. Her GitHub account is `wholewomancollective`. Her Supabase project ref is `iqmfbhtusygvdxynfzzg`.

## Help

Kelly Wotherspoon built this app and has helper access until 21 December 2026 (GitHub user `aiwithsoulofficial`). If something is beyond what you and Jacqui can sort out, suggest she messages Kelly.
