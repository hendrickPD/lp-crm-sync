#!/usr/bin/env bash
# lp-crm-sync — idempotent installer
# Safe to rerun. Won't overwrite an existing .env.
#
# Usage:
#   curl -sSL https://raw.githubusercontent.com/hendrickPD/lp-crm-sync/main/install.sh | bash
# or, if you prefer to read it first (recommended):
#   curl -sSL https://raw.githubusercontent.com/hendrickPD/lp-crm-sync/main/install.sh -o /tmp/lp-install.sh
#   less /tmp/lp-install.sh
#   bash /tmp/lp-install.sh

set -euo pipefail

SKILL_DIR="${SKILL_DIR:-$HOME/pd-lp-crm-skill}"
CLAUDE_SKILLS_DIR="$HOME/.claude/skills"
SYMLINK_PATH="$CLAUDE_SKILLS_DIR/lp-crm-sync"
ENV_FILE="$SKILL_DIR/.env"
ZSHRC="$HOME/.zshrc"
ZSHRC_LINE='[ -f ~/pd-lp-crm-skill/.env ] && set -a && source ~/pd-lp-crm-skill/.env && set +a'

echo ""
echo "============================================"
echo "  lp-crm-sync installer"
echo "============================================"
echo ""

# ---------- 1. Clone or update the skill source ----------
if [ -d "$SKILL_DIR/.git" ]; then
  echo "[1/5] Skill repo already at $SKILL_DIR — pulling latest..."
  git -C "$SKILL_DIR" pull --ff-only
else
  echo "[1/5] Cloning skill to $SKILL_DIR ..."
  git clone https://github.com/hendrickPD/lp-crm-sync.git "$SKILL_DIR"
fi

# ---------- 2. Register with Claude Code via symlink ----------
mkdir -p "$CLAUDE_SKILLS_DIR"
if [ -L "$SYMLINK_PATH" ]; then
  echo "[2/5] Skill already symlinked at $SYMLINK_PATH"
elif [ -e "$SYMLINK_PATH" ]; then
  echo "[2/5] WARNING: $SYMLINK_PATH exists and is not a symlink — leaving it alone." >&2
  echo "       Rename or remove it manually and rerun if you want to install." >&2
else
  ln -s "$SKILL_DIR" "$SYMLINK_PATH"
  echo "[2/5] Registered skill: $SYMLINK_PATH -> $SKILL_DIR"
fi

# ---------- 3. Create .env (Palm Drive defaults; non-secret values only) ----------
if [ -f "$ENV_FILE" ]; then
  echo "[3/5] $ENV_FILE already exists — leaving it alone"
else
  cat > "$ENV_FILE" <<'EOF'
# lp-crm-sync config — filled in locally, never committed.
#
# Get an Affinity API key at:
#   https://<your-subdomain>.affinity.co/settings/manage-apps
# Palm Drive colleagues: https://palmdrive.affinity.co/settings/manage-apps
# Click "Generate API key" — it's shown ONCE. Treat like a password.
AFFINITY_API_KEY=PASTE_YOUR_KEY_HERE

# Palm Drive defaults below — change these if you're a different team.
# Channel IDs: open the channel in Slack web, copy the trailing ID from the URL
# (e.g. https://<workspace>.slack.com/archives/GRKEM91EK)
LP_NOTES_CHANNEL_ID=GRKEM91EK
LP_CRM_CHANNEL_ID=C0ATD562S9K

# Affinity list ID — discover via:
#   curl -s https://api.affinity.co/lists -H "Authorization: Bearer $AFFINITY_API_KEY"
# pick the list whose `name` matches your LP tracker.
AFFINITY_LP_LIST_ID=254501

# Used for building Slack permalinks in reports
SLACK_WORKSPACE_DOMAIN=palmdrive
EOF
  chmod 600 "$ENV_FILE"
  echo "[3/5] Created $ENV_FILE with Palm Drive defaults (chmod 600)"
fi

# ---------- 4. Persist env loading in .zshrc ----------
if [ -f "$ZSHRC" ] && grep -Fq "$ZSHRC_LINE" "$ZSHRC"; then
  echo "[4/5] .zshrc already sources .env — no change"
else
  touch "$ZSHRC"
  {
    echo ""
    echo "# lp-crm-sync — load Affinity + Slack config for every shell (incl. scheduled runs)"
    echo "$ZSHRC_LINE"
  } >> "$ZSHRC"
  echo "[4/5] Added .env loader to $ZSHRC"
fi

# ---------- 5. Next steps ----------
cat <<'NEXT'

[5/5] Install complete. Three things left (all manual):

  1. Paste your Affinity API key into ~/pd-lp-crm-skill/.env
     Replace PASTE_YOUR_KEY_HERE with the key from:
       https://palmdrive.affinity.co/settings/manage-apps
     (For non-Palm-Drive users, use your own <subdomain>.affinity.co URL.)

     $ open -t ~/pd-lp-crm-skill/.env    # or: nano / vim

  2. Load env vars into your current shell (new shells get them automatically via .zshrc):
     $ set -a; source ~/pd-lp-crm-skill/.env; set +a

  3. Verify the key works:
     $ curl -s https://api.affinity.co/v2/auth/whoami \
         -H "Authorization: Bearer $AFFINITY_API_KEY" | python3 -m json.tool

     Expect a JSON with your tenant name and "scopes": ["api"].

  Then in Claude Code:
     "Run the lp-crm-sync skill."

  For weekly automation, see:
     https://github.com/hendrickPD/lp-crm-sync-schedule

NEXT
