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

## Prerequisites

- **Claude Code** with a Slack MCP connector configured (any flavor — the skill detects available Slack tools at runtime)
- **Affinity API key** — generate at Affinity → Settings → API. Any admin on your workspace can create one. Keep it out of version control.
- **Claude Code skill support** — drop this directory into your skills path or install it via whatever skill-management mechanism your setup uses

## Setup

### 1. Clone or copy this directory

```bash
git clone <your-fork-url> ~/pd-lp-crm-skill
# or copy the files into your preferred skills directory
```

### 2. Configure your environment

Copy `.env.example` to `.env` (which is gitignored) and fill in your values:

```bash
cp .env.example .env
$EDITOR .env
```

Required variables:
- `AFFINITY_API_KEY` — your Affinity API key (treat like a password)
- `LP_NOTES_CHANNEL_ID` — Slack channel ID for raw LP notes (get from the channel's Slack URL)
- `LP_CRM_CHANNEL_ID` — Slack channel ID where the skill posts reports and reads feedback
- `AFFINITY_LP_LIST_ID` — numeric ID of your Affinity list tracking LPs

To find the Affinity list ID, run:

```bash
curl -s https://api.affinity.co/lists \
  -H "Authorization: Bearer $AFFINITY_API_KEY" | python3 -m json.tool
```

Find the list whose `name` matches your LP tracker (e.g., "LPs", "Fund V LPs") and note its `id`.

Then source the file before running Claude Code:

```bash
set -a; source .env; set +a
claude
```

(Or use `direnv` or your preferred env manager.)

### 3. Verify the Slack MCP is connected

In Claude Code, run `/mcp` and confirm a Slack connector shows up. If not, add one — any Slack MCP that exposes `slack_read_channel` and `slack_send_message` will work.

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
