# Move the app's engine into Jacqui's own Supabase

Instructions for Claude, working with Jacqui on her laptop. Read the whole file before you start. Read `CLAUDE.md` in the root of this folder first: its rules apply here too.

## What this is

Come Home to Each Other is a one-page app (`index.html`) for a mother and daughter. Each has it on her own phone. When one of them writes her words for the morning or evening, the other phone gets them, plus a notification.

Three things make that work, and all three sit in a Supabase project:

1. Three database tables (`chte_pairs`, `chte_entries`, `chte_push_subs`). They are locked: row level security is on with no policies. The app never reads the tables directly.
2. Seven database functions (`chte_...`). The app calls these, and every call needs the pair's secret token.
3. One server function, `chte-notify`, which sends the phone notification. It needs a pair of notification keys called VAPID keys.

Right now all of this sits in Kelly Wotherspoon's Supabase project (Kelly built the app). This job builds the same engine in Jacqui's own project and points the app at it. On 22 November 2026 Kelly's copy held four test pairings and no written entries, so there is nothing to move across. The app starts fresh.

Jacqui's Supabase project ref: `iqmfbhtusygvdxynfzzg`
Jacqui's project address: `https://iqmfbhtusygvdxynfzzg.supabase.co`
Live app: https://wholewomancollective.github.io/come-home-to-each-other/

## Done means

1. The three tables exist in her project with row level security on and no policies, and the seven functions exist.
2. Three function secrets are set: `CHTE_VAPID_PUBLIC`, `CHTE_VAPID_PRIVATE`, `CHTE_VAPID_SUBJECT`.
3. `chte-notify` is deployed, active, with JWT verification off.
4. The test in step 6 passed from start to finish.
5. The `SYNC` block in the live `index.html` holds her project address, her publishable key and her new public VAPID key.
6. Jacqui has been told in plain words what was done.

Do not tell Jacqui it is finished until all six are true. If you get stuck, stop, leave `index.html` as it was, and tell her to message Kelly with what you found. The app keeps working on Kelly's copy until step 7 is published, so stopping early breaks nothing.

## How to work with Jacqui here

- She is not technical. Before each numbered step, tell her in one or two plain sentences what you are about to do, then wait for her yes.
- Use the Supabase connector for everything in Supabase.
- Work only in project `iqmfbhtusygvdxynfzzg`. Touch nothing else in it, including her `jacqui_leads` table and `jacqui-lead` function.

## Steps

### 1. Check you can reach her Supabase

List the Supabase projects the connector can see. Project `iqmfbhtusygvdxynfzzg` must be in the list. If Supabase is not connected, or this project is not listed, send her to number 2 on her handover page (https://thewholewomancollective.com.au/handover/) and stop.

### 2. Create the tables and functions

Apply `_backend/schema.sql` to her project as a migration named `create_chte_app`.

Check: `chte_pairs`, `chte_entries` and `chte_push_subs` exist, each with row level security enabled and no policies. Seven functions exist whose names start with `chte_`. Do not add any policy.

### 3. Make a new pair of notification keys

Generate a new VAPID key pair on her laptop. It is a P-256 key pair written as base64url text with no padding.

- If Node is installed: `npx --yes web-push generate-vapid-keys --json`
- If not, PowerShell can do it:

```powershell
$ec = [System.Security.Cryptography.ECDsa]::Create([System.Security.Cryptography.ECCurve+NamedCurves]::nistP256)
$p = $ec.ExportParameters($true)
function B64Url($b) { [Convert]::ToBase64String($b).TrimEnd('=').Replace('+','-').Replace('/','_') }
$vapidPublic  = B64Url ([byte[]](@(4) + $p.Q.X + $p.Q.Y))
$vapidPrivate = B64Url $p.D
```

Check the shape before you use them: the public key is 87 characters and starts with the letter `B`. The private key is 43 characters. If either is wrong, generate again by another method.

Rules for the private key:

- Never write it into any file inside this folder. Everything in this folder is public.
- Never show it to Jacqui or repeat it in your replies. She does not need to see it.
- If you had to save it to a temporary file, put that file outside this folder and remove it, with her yes, once step 4 is done.

### 4. Store the three secrets

Ask Jacqui which email address should be the contact for notifications (her business email is fine). Then set these function secrets in her project:

- `CHTE_VAPID_PUBLIC`: the public key from step 3
- `CHTE_VAPID_PRIVATE`: the private key from step 3
- `CHTE_VAPID_SUBJECT`: `mailto:` followed by her email address, for example `mailto:name@example.com`

Use the connector's tool for function secrets. If the connector has no such tool, stop and tell Jacqui this step needs Kelly's help. Do not ask her to type the private key by hand.

Do this before step 5. The function reads these the moment it starts, and it fails to start without them.

### 5. Deploy the notification function

Deploy `_backend/chte-notify/index.ts` as an edge function named `chte-notify`, with JWT verification turned OFF (`verify_jwt: false`). The function does its own check: the request must carry the project's public key and a valid pair token.

Check: `chte-notify` is active and `verify_jwt` is false.

### 6. Test the engine before touching the app

Get her project's publishable key with the connector. It starts with `sb_publishable_`. It is made to be public. Never use a key that starts with `sb_secret_` here, and never the service role key.

PowerShell (put her publishable key in the second line):

```powershell
$url = "https://iqmfbhtusygvdxynfzzg.supabase.co"
$key = "PUT-THE-PUBLISHABLE-KEY-HERE"
$h = @{ apikey = $key; Authorization = "Bearer $key" }
function Rpc($fn, $body) { Invoke-RestMethod -Method Post -Uri "$url/rest/v1/rpc/$fn" -Headers $h -ContentType "application/json" -Body ($body | ConvertTo-Json) }

$token = Rpc "chte_create_pair" @{ p_mum = "Test Mum"; p_daughter = "Test Daughter" }
Rpc "chte_save_entry" @{ p_token = $token; p_day = (Get-Date -Format "yyyy-MM-dd"); p_part = "morning"; p_role = "mum"; p_words = "setup test" }
Rpc "chte_get" @{ p_token = $token }
Invoke-RestMethod -Method Post -Uri "$url/functions/v1/chte-notify" -Headers $h -ContentType "application/json" -Body (@{ token = $token; role = "mum"; part = "morning" } | ConvertTo-Json)
Rpc "chte_delete_pair" @{ p_token = $token }
```

Expected, in order:

1. `chte_create_pair` returns a 32-character token.
2. `chte_save_entry` returns `True`.
3. `chte_get` returns `mumName` "Test Mum", `daughterName` "Test Daughter" and one entry.
4. `chte-notify` returns `subscribers` 0 and `sent` 0. (No phone has signed up for notifications yet, so zero is right. An error here means the secrets or the deploy are wrong: read the function's logs.)
5. `chte_delete_pair` returns `True`. This removes the test pairing and its entry.

Then confirm the tables are locked: a direct read of `$url/rest/v1/chte_pairs` with the same headers must return an empty list or a permission error, never rows.

If the `rpc` calls fail with a "schema" or "permission" error, the project's Data API may be off or may not expose the `public` schema. Ask Jacqui to open https://supabase.com/dashboard/project/iqmfbhtusygvdxynfzzg/settings/api and tell you what the Data API section shows, then guide her.

Do not go on to step 7 until all five results match.

### 7. Point the app at her project

In `index.html`, find the block that starts `const SYNC = {`. Change the three values and nothing else:

- `url`: `https://iqmfbhtusygvdxynfzzg.supabase.co`
- `key`: her publishable key (starts with `sb_publishable_`)
- `vapid`: the new public VAPID key from step 3

Both of those keys are public by design, so they are allowed in this file. The private VAPID key is not.

Show Jacqui the before and after. When she says yes, commit and push to `master`.

Check: wait two minutes, then load https://wholewomancollective.github.io/come-home-to-each-other/ and confirm the page source contains `iqmfbhtusygvdxynfzzg.supabase.co` and no longer contains `jiquevvzrdavgqonvvug`.

### 8. Try it on two phones

Ask Jacqui to open the live app on her phone, start a new pairing, and send the invite link to a second phone (her daughter's, or any second phone). Each writes a few words. Each should see the other's words within about twenty seconds.

For notifications on an iPhone, the app has to be added to the Home Screen first, then notifications allowed when it asks. This has not been tested on a real iPhone yet, so if a notification does not arrive but the words do, tell her that part is known to be untested and to let Kelly know.

Anyone who set the app up before today has to tap Start over once. The earlier pairings were tests only.

### 9. Tell her

Tell Jacqui, in plain words:

- Her app's engine now runs in her own Supabase account.
- The words that mothers and daughters write are private. They are stored in her account and you will not read them.
- Ask her to message Kelly that this part is done, so Kelly can close off her old copy.

## Do not

- Do not add policies to the three tables or make them readable from the public internet.
- Do not read, list or show the `words` column of `chte_entries`. Those are private words between a mother and her daughter. Counting rows is fine.
- Do not put the private VAPID key or any Supabase secret key in a file, a commit or this chat.
- Do not change anything in `index.html` except the three `SYNC` values.
- Do not change or delete anything in Kelly's project. You have no access to it and do not need any.
