# lp-crm-sync

A Claude Code skill that automates the "Slack capture → Affinity CRM → follow-up" loop that many VC fundraising teams run by hand.

## What it does

1. Reads recent LP meeting notes from a Slack channel
2. Cross-references them against your Affinity LP list
3. Identifies cold-but-interesting leads (stale but worth re-engaging)
4. Drafts personalized follow-up emails
5. Posts a report to a feedback Slack channel
6. On your approval, writes new leads into Affinity with notes + Slack permalinks

The skill is designed to run weekly — either on-demand or on a schedule.

## Install (one-liner)

```bash
curl -sSL https://raw.githubusercontent.com/hendrickPD/lp-crm-sync/main/install.sh | bash
```

This clones the skill, symlinks it into `~/.claude/skills/lp-crm-sync` so Claude Code discovers it, creates a `.env` with Palm Drive's channel/list defaults and a placeholder for your Affinity key, `chmod`s the file to `600`, and adds a line to `~/.zshrc` so every new shell (including scheduled headless runs) picks up the env vars automatically.

The installer is idempotent — safe to rerun. It won't overwrite an existing `.env`.

Prefer to read the script first (recommended for anyone who hasn't met it before)?

```bash
curl -sSL https://raw.githubusercontent.com/hendrickPD/lp-crm-sync/main/install.sh -o /tmp/lp-install.sh
less /tmp/lp-install.sh
bash /tmp/lp-install.sh
```

## After install — three manual steps

1. **Paste your Affinity API key** into `~/pd-lp-crm-skill/.env` over the `PASTE_YOUR_KEY_HERE` placeholder.

   Get a key at `https://<your-subdomain>.affinity.co/settings/manage-apps` → **Generate API key**. It's shown once only — treat like a password.

   Palm Drive colleagues: https://palmdrive.affinity.co/settings/manage-apps

2. **Load env vars into your current shell** (new shells get them automatically via `.zshrc`):

   ```bash
   set -a; source ~/pd-lp-crm-skill/.env; set +a
   ```

3. **Verify the key works**:

   ```bash
   curl -s https://api.affinity.co/v2/auth/whoami \
     -H "Authorization: Bearer $AFFINITY_API_KEY" | python3 -m json.tool
   ```

   Expect JSON with your tenant name and `"scopes": ["api"]`. A `401` usually means a trailing newline in `.env`.

Then in Claude Code: *"Run the lp-crm-sync skill."*

## Prerequisites (what the installer assumes)

- **Claude Code** installed and working (`claude --version` should respond)
- **Slack MCP connector** already configured — check with `/mcp` in any Claude Code session. Any connector that exposes channel read/write works. The bot needs to be invited to both your LP notes channel and your feedback channel.
- **Admin access to Affinity** (or a colleague who can generate you a key)
- **Git** available on your PATH

## If you're not at Palm Drive

The installer bakes in Palm Drive's channel IDs and Affinity list ID as `.env` defaults — useful shorthand for colleagues, wrong for anyone else. After running the installer, edit `~/pd-lp-crm-skill/.env` and replace:

- `LP_NOTES_CHANNEL_ID` — open your LP notes channel in Slack web, copy the trailing ID from the URL
- `LP_CRM_CHANNEL_ID` — same, for the channel where you want the skill to post reports and read feedback
- `AFFINITY_LP_LIST_ID` — discover with `curl -s https://api.affinity.co/lists -H "Authorization: Bearer $AFFINITY_API_KEY"`, then pick the list whose `name` matches your LP tracker

## Manual install (without the one-liner)

```bash
git clone https://github.com/hendrickPD/lp-crm-sync.git ~/pd-lp-crm-skill
mkdir -p ~/.claude/skills
ln -s ~/pd-lp-crm-skill ~/.claude/skills/lp-crm-sync
cp ~/pd-lp-crm-skill/.env.example ~/pd-lp-crm-skill/.env
chmod 600 ~/pd-lp-crm-skill/.env
$EDITOR ~/pd-lp-crm-skill/.env   # fill in all values
echo '[ -f ~/pd-lp-crm-skill/.env ] && set -a && source ~/pd-lp-crm-skill/.env && set +a' >> ~/.zshrc
```

## Usage

Ask Claude:

- *"Run the LP CRM routine"*
- *"Who should we follow up with in our LP pipeline?"*
- *"Sync the last 30 days of LP notes to Affinity"*
- *"Draft follow-up emails for our cold LP leads"*

The skill posts a report to `LP_CRM_CHANNEL_ID` with a top-10 cold list, follow-up drafts, and a consolidation plan. Reply in that channel with **"go"** to approve writing the new leads into Affinity.

## Running on a schedule

Scheduling is deliberately kept out of this repo so the skill stays portable. See the companion project [lp-crm-sync-schedule](https://github.com/hendrickPD/lp-crm-sync-schedule) for a ready-to-install weekly Monday-morning cadence. You can fork it to customize day/time or skip it entirely and invoke the skill manually.

## Security

- `.env` is gitignored. Do not commit it.
- The skill never writes your API key to disk. It reads from environment only.
- If you paste a key into a Claude chat, rotate it afterwards — chat transcripts may persist.
- Consider scoping the Affinity key to a service account if your plan allows (Affinity V1 keys are workspace-scoped by default).

## Customization

- **Cold threshold** — edit `SKILL.md` "cold-but-interesting" definition to change from 30 days
- **Top N** — same file, change "top-10" to your preferred count
- **Field mapping** — Affinity field names are read from the list schema at runtime (see `references/affinity-api-cheatsheet.md`), so you shouldn't need to edit unless your list has unusual custom fields

## Feedback loop

The skill reads the LP_CRM channel each run to pick up:
- Approval ("go") for pending consolidations
- Corrections ("David's name is actually Hirsch not Hirschfield")
- Additional context ("Riady moved to Vest Capital")

Write feedback freely in that channel — the skill will incorporate it on the next run.

## License

MIT (or whatever you prefer — this is a starter skill, fork and adapt).
