---
name: lp-crm-sync
description: Sync LP (limited partner) meeting notes from a Slack channel into Affinity CRM, surface cold-but-interesting leads, and draft personalized follow-up emails. Use this skill whenever the user asks to summarize their LP pipeline, identify stale investor contacts, generate follow-up outreach drafts, consolidate Slack-captured investor conversations into Affinity, or run a weekly LP pipeline review — even if they don't explicitly name the tool. Designed for VC funds that capture raw LP conversations in one Slack channel and track pipeline in an Affinity list. Also triggers on prompts like "who should we follow up with", "what's gone cold in our LP pipeline", "sync our LP notes", "draft LP follow-ups", "run the LP CRM routine".
---

# LP CRM Sync

Automates the "Slack capture → Affinity CRM → follow-up" loop that many VC fundraising teams run manually. The skill reads an LP meeting-notes Slack channel, cross-references against an Affinity list, identifies cold-but-interesting leads, drafts personalized follow-up emails, and posts a report to a feedback Slack channel. On request it also consolidates new leads into Affinity with notes.

## When to use

Trigger this skill when the user asks any of:
- "Summarize our LP pipeline / meeting notes"
- "Who's gone cold in our LP outreach?"
- "Draft follow-ups for the LPs we haven't talked to in a while"
- "Sync the LP notes channel to Affinity"
- "Run the weekly LP CRM routine"
- "Give me the top N cold-but-interesting LPs"

## Preflight — run this BEFORE anything else, every single invocation

Every time this skill triggers, run the four checks below in order. The first one that fails: stop, give the user the specific recovery instructions for that check, and do not continue. Do not silently paper over missing config by asking the user to paste secrets inline, and never fall back to hardcoded values.

A clean preflight pass should take <5 seconds. Don't skip it "because we ran it recently" — a lot can change between invocations (token revoked, MCP disconnected, channel renamed).

### Check 1 — Affinity API key is set and working

Verify both that `AFFINITY_API_KEY` is in the environment AND that it actually authenticates:

```bash
curl -s -o /dev/null -w "%{http_code}" https://api.affinity.co/v2/auth/whoami \
  -H "Authorization: Bearer $AFFINITY_API_KEY"
```

Expect `200`. On anything else (unset variable, 401, 403), show this recovery block:

> I can't reach Affinity. Here's how to set up the API key:
> 1. Log in to Affinity as an admin (or ask an admin on your workspace).
> 2. Go to **Settings → API**. URL pattern: `https://<your-subdomain>.affinity.co/settings/manage-apps`
>    - Palm Drive colleagues: https://palmdrive.affinity.co/settings/manage-apps
> 3. Click **Generate API key** and copy it immediately — shown only once.
> 4. Save it in `~/pd-lp-crm-skill/.env` as `AFFINITY_API_KEY=<your key>` (create the file if it doesn't exist — the installer does this for you).
> 5. `chmod 600 ~/pd-lp-crm-skill/.env` so only you can read it.
> 6. Load it into your shell: `set -a; source ~/pd-lp-crm-skill/.env; set +a`
> 7. For persistent loading (required for scheduled headless runs), add this to `~/.zshrc`:
>    `[ -f ~/pd-lp-crm-skill/.env ] && set -a && source ~/pd-lp-crm-skill/.env && set +a`
>
> After fixing, ask me to run the skill again.

Treat the key as a secret. Do not echo it in the terminal, do not paste it into Slack, do not include it in error messages, do not write it anywhere other than `.env`. If the user pastes it into chat, remind them to rotate after the task completes.

### Check 2 — Slack MCP is connected with the tools we need

Look at the tools available this session. The skill needs Slack tools covering read, write, and search — names vary by MCP flavor but typically look like `slack_read_channel` / `slack_send_message` / `slack_search_channels` (possibly with a workspace prefix). If none match:

> The Slack MCP connector isn't available in this session. Recovery:
> 1. In Claude Code, run `/mcp` to see configured connectors.
> 2. If no Slack connector is listed, add one (any Slack MCP that exposes channel read/write works).
> 3. Once connected, invite the bot to both your LP notes channel and your feedback channel. Inside each channel in Slack: `/invite @<bot-name>`.
> 4. Restart this chat / resume, and ask me to run the skill again.

### Check 3 — Config env vars are set

Verify `LP_NOTES_CHANNEL_ID`, `LP_CRM_CHANNEL_ID`, and `AFFINITY_LP_LIST_ID` are all set and non-empty.

Palm Drive reference values: `LP_NOTES_CHANNEL_ID=GRKEM91EK`, `LP_CRM_CHANNEL_ID=C0ATD562S9K`, `AFFINITY_LP_LIST_ID=254501`. Other teams will have their own — these are just examples.

If any are missing:

> Config incomplete. Set these in `~/pd-lp-crm-skill/.env`:
> - `LP_NOTES_CHANNEL_ID` — Slack channel where raw LP notes are captured. Open the channel in Slack web and copy the trailing ID from the URL (e.g. `https://palmdrive.slack.com/archives/GRKEM91EK` → `GRKEM91EK`).
> - `LP_CRM_CHANNEL_ID` — Slack channel where this skill posts reports and reads feedback. Same method.
> - `AFFINITY_LP_LIST_ID` — numeric Affinity list ID. Discover with:
>   ```
>   curl -s https://api.affinity.co/lists -H "Authorization: Bearer $AFFINITY_API_KEY" | python3 -m json.tool
>   ```
>   Find the list whose `name` matches your LP tracker and copy its `id`.
>
> Then re-source: `set -a; source ~/pd-lp-crm-skill/.env; set +a`

### Check 4 — Slack bot has access to both channels

Try a 1-message read on each configured channel. On `not_in_channel` or similar:

> The Slack MCP bot isn't a member of `<channel-id>`. Inside that channel in Slack, run `/invite @<bot-name>` and ask me to retry.

## Security rules

These apply throughout every run, not just preflight.

- **The skill itself never writes secrets.** `AFFINITY_API_KEY` is read from the environment; the skill never echoes it, never writes it to files, never passes it back to the user. The user's own `.env` (populated by the installer) is their responsibility — if you touch it at all, only to suggest what should be in it.
- **`.env` stays out of git.** The repo's `.gitignore` blocks `.env`, `*.key`, `*.secret`. Don't circumvent it and don't advise the user to commit a key.
- **No secrets in Slack messages.** Not the API key, not any env-var contents, not even in error messages posted to `$LP_CRM_CHANNEL_ID`.
- **If the user pastes a key into chat**, flag that the transcript now contains it and recommend they rotate after the task finishes. Chat transcripts persist locally and pass through the API.

## Workflow

The default run consists of the steps below. Follow them in order unless the user asks for a subset.

### 1. Read LP notes channel

Read the last N days (default: 30) of messages from `$LP_NOTES_CHANNEL_ID`. For each message:
- Capture author, timestamp, text, and any thread replies
- Preserve the Slack permalink so you can cite sources in your report

Entity extraction is noisy — notes are often pronoun-first ("He is raising…") with the subject named only a message or two earlier. When a message lacks a clear subject, scroll backwards in the thread to resolve it. When in doubt, flag with a ⚠️ and ask the user for clarification rather than guessing.

### 2. Read LP_CRM channel for feedback

Read the last 14 days of messages from `$LP_CRM_CHANNEL_ID`. Look for:
- **"go"** — user has approved a pending consolidation write
- **Corrections** — "remove X", "David's name is spelled Hirsch not Hirschfield", "Riady is at Vest Capital not Giti"
- **New manual leads** — the team may add context that isn't in the raw notes channel

Apply corrections before generating the new report.

### 3. Pull Affinity state

Use the Affinity V1 REST API (Bearer auth):

```bash
curl -s "https://api.affinity.co/lists/$AFFINITY_LP_LIST_ID/list-entries?page_size=500" \
  -H "Authorization: Bearer $AFFINITY_API_KEY"
```

Parse the response to build a map of `entity_name → entity_id` so you know who's already in the list.

### 4. Cross-reference

For each entity surfaced in the Slack notes (step 1):
- If already in the Affinity list: mark as "tracked", note its existing Affinity ID
- If not in the list: mark as "missing, candidate for consolidation"

### 5. Identify cold-but-interesting

Definition: surfaced in Slack more than **30 days ago**, not flagged as dead/declined, with any of these high-signal traits:
- Institutional LP (pension, endowment, fund of funds, sovereign)
- Large check size (>$5M or large AUM)
- Strong strategic angle (specific thesis fit, warm intro path, unique access)
- Explicit interest previously expressed

Rank and select a top-10 list. For each, collect:
- Last Slack date + permalink
- Cold duration (weeks/months)
- Source / owner (which teammate surfaced them)
- Why interesting (one line)

### 6. Look up emails

For each of the top 10, search Affinity's global person/org graph:

```bash
curl -s "https://api.affinity.co/persons?term=<urlencoded-name>" \
  -H "Authorization: Bearer $AFFINITY_API_KEY"

curl -s "https://api.affinity.co/organizations?term=<urlencoded-name>" \
  -H "Authorization: Bearer $AFFINITY_API_KEY"
```

Affinity auto-ingests contacts from any connected email accounts, so leads may have emails even if they aren't on the LP list. When matches are found, extract the `emails` array. When no match is found, do NOT fabricate an email — flag as "email unknown; educated guess: firstname.lastname@<org-domain>" only if the org domain is known, and clearly label as unverified.

Watch for mismatches between Slack context and Affinity data (e.g., "contact is at Firm X in Slack but their Affinity email domain is Firm Y"). Flag these as potential affiliation changes — they're high-signal, not noise.

### 7. Draft follow-up emails

For each of the top 10, draft a short follow-up email (3–6 sentences). Style:
- Semi-formal but personable
- Reference the specific Slack-captured context ("you'd mentioned…", "following up from our exchange last September…")
- State one clear ask (15-min call, send deck, intro)
- Sign off as the correct owner (the teammate who surfaced the lead — infer from the Slack message author)
- Flag any uncertainties (unverified email, unconfirmed name spelling, possible affiliation change) so the sender can fix before hitting send

Drafts are starting points, not final copy. Always emphasize to the user that they should customize to voice before sending.

### 8. Post report to LP_CRM channel

Compose the report with these sections:
1. **Top 10 cold-but-interesting** (ranked list with one-line "why")
2. **Emails found** (which ones came from Affinity directly, which are educated guesses, which are missing)
3. **Follow-up drafts** (one short email per lead)
4. **Consolidation plan** (list of entities missing from Affinity; what fields would be populated if approved)
5. **Next actions** (what the user needs to do — verify emails, confirm spellings, approve consolidation)

Slack has a 5000-character-per-message limit. Split into multiple messages if needed (summary + drafts is a natural split). Use Slack-compatible markdown: `*bold*`, `_italic_`, `\`code\``, `- bullets`. Avoid triple-hyphens for horizontal rules and avoid bullet characters like `•` — some Slack connectors reject them.

### 9. Execute consolidation (only on explicit approval)

Only write to Affinity if the user has replied **"go"** (or similar explicit approval like "proceed", "do it", "confirmed") in the LP_CRM channel since the last report was posted. **Never mutate Affinity data without explicit approval.**

When approved, for each missing entity:
1. Create the person or organization via `POST https://api.affinity.co/persons` or `POST https://api.affinity.co/organizations` — but first search to avoid duplicates.
2. Add to the LPs list via `POST https://api.affinity.co/list-entries` with `list_id` and `entity_id`.
3. Populate the standard fields (Status = "Target", Investor Type, Check size, Location) via `POST https://api.affinity.co/field-values`.
4. Attach a note with the Slack-captured context + permalink via `POST https://api.affinity.co/notes`.

See `references/affinity-api-cheatsheet.md` for exact payload shapes.

After writes complete, post a brief confirmation to LP_CRM ("✅ Added 12 new entities to the LPs list. Run again next week.").

## Running on a schedule

This skill is designed to be run weekly, but the *when* is intentionally not baked in — different teams have different rhythms and timezones.

- **Manual / on-demand** — ask Claude "run the LP CRM routine" whenever you want it
- **Scheduled** — see the companion project [lp-crm-sync-schedule](https://github.com/hendrickPD/lp-crm-sync-schedule) for a weekly Monday-morning setup you can copy or adapt. It ships with an opinionated prompt and install instructions for the Claude Code `scheduled-tasks` MCP tool.

## Failure modes and recovery

- **Affinity 401** — API key invalid or expired. Stop, tell the user, ask for a fresh key.
- **Affinity 429** — rate limited. Back off (Affinity V1 is ~50 req/min). Batch where possible.
- **Slack message too long** — split into two messages with a visible `↓ continued` marker.
- **Slack MCP disconnected mid-run** — stop and ask user to reconnect; do not retry blindly.
- **Ambiguous entity resolution** — surface the ambiguity in the report (e.g., "Takamol vs Takamul Holding") rather than guessing. The user can correct via the feedback channel.

## What this skill explicitly does NOT do

- **Does not send emails** — it only drafts them. Sending is the user's job after review.
- **Does not delete from Affinity** — reads and creates only. Deletions should be done manually.
- **Does not modify existing Affinity entities** without explicit per-entity approval.

## Reference files

- `references/affinity-api-cheatsheet.md` — Affinity V1/V2 endpoint reference with example payloads
