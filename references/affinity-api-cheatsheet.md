# Affinity API Cheatsheet

Quick reference for the Affinity V1 REST endpoints this skill uses. V2 is emerging but V1 is more complete for write operations as of this writing.

## Authentication

Affinity now uses **Bearer token auth on both V1 and V2** (older docs still show Basic — those are out of date):

```bash
curl -s https://api.affinity.co/lists \
  -H "Authorization: Bearer $AFFINITY_API_KEY"
```

Confirm the key works with the V2 whoami endpoint:

```bash
curl -s https://api.affinity.co/v2/auth/whoami \
  -H "Authorization: Bearer $AFFINITY_API_KEY"
```

Expected response:

```json
{
  "tenant": {"id": 2289, "name": "Your Workspace", "subdomain": "yourworkspace"},
  "user": {"id": 123, "firstName": "...", "lastName": "...", "emailAddress": "..."},
  "grant": {"type": "api-key", "scopes": ["api"], "createdAt": "..."}
}
```

## Getting an API key

1. Log in to Affinity as an admin
2. Settings (bottom-left) → **API**
3. Click **Generate API key**
4. Copy immediately (shown once only)

Keys are workspace-scoped and have full read/write. Treat like a password.

## Key endpoints used by this skill

### List lists

```bash
curl -s https://api.affinity.co/lists \
  -H "Authorization: Bearer $AFFINITY_API_KEY"
```

Returns an array of lists with `id`, `name`, `type`, `public`, `list_size`. Use this to find your LP list ID.

### Get list details (includes field schema)

```bash
curl -s https://api.affinity.co/lists/$LIST_ID \
  -H "Authorization: Bearer $AFFINITY_API_KEY"
```

Returns list metadata plus an array of `fields` — each field has:
- `id` (integer, used when setting values)
- `name` (e.g. "Status", "Check size", "Investor Type")
- `value_type` — 0=person, 2=dropdown, 3=number, 4=date, 6=text, 7=ranked dropdown
- `dropdown_options` — array of `{id, text, rank, color}` for dropdown fields

### List entries in a list

```bash
curl -s "https://api.affinity.co/lists/$LIST_ID/list-entries?page_size=500" \
  -H "Authorization: Bearer $AFFINITY_API_KEY"
```

Returns `list_entries` array and optional `next_page_token` for pagination. Each entry has:
- `id` (list entry ID)
- `entity_id` (the underlying person/org ID)
- `entity_type` (0 = person, 1 = org, 8 = opportunity)
- `entity.name`

### Search persons

```bash
curl -s "https://api.affinity.co/persons?term=<urlencoded-name>" \
  -H "Authorization: Bearer $AFFINITY_API_KEY"
```

Returns persons array with `id`, `first_name`, `last_name`, `emails` (array), `organization_ids`.

### Search organizations

```bash
curl -s "https://api.affinity.co/organizations?term=<urlencoded-name>" \
  -H "Authorization: Bearer $AFFINITY_API_KEY"
```

Returns organizations with `id`, `name`, `domain`, `domains`, `person_ids`.

### Create a person (write)

```bash
curl -s -X POST https://api.affinity.co/persons \
  -H "Authorization: Bearer $AFFINITY_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "first_name": "David",
    "last_name": "Hirsch",
    "emails": ["david@example.com"]
  }'
```

Returns the created person. Search first to avoid duplicates.

### Create an organization (write)

```bash
curl -s -X POST https://api.affinity.co/organizations \
  -H "Authorization: Bearer $AFFINITY_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Peterson Group",
    "domain": "petersonhk.com"
  }'
```

### Add an entity to a list (write)

```bash
curl -s -X POST https://api.affinity.co/list-entries \
  -H "Authorization: Bearer $AFFINITY_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "list_id": 254501,
    "entity_id": 123456,
    "creator_id": null
  }'
```

### Set a field value (write)

```bash
curl -s -X POST https://api.affinity.co/field-values \
  -H "Authorization: Bearer $AFFINITY_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "field_id": 4600056,
    "entity_id": 123456,
    "list_entry_id": 987654,
    "value": 14271151
  }'
```

For dropdown fields, `value` is the dropdown option's numeric ID.
For text fields, `value` is a string.
For number fields, `value` is a number.
For date fields, `value` is an ISO-8601 date string.
For person fields, `value` is the person's ID (integer).

### Create a note (write)

```bash
curl -s -X POST https://api.affinity.co/notes \
  -H "Authorization: Bearer $AFFINITY_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "person_ids": [123456],
    "organization_ids": [],
    "opportunity_ids": [],
    "content": "From #lp-meeting-note 2026-04-16: ..."
  }'
```

Use the note to capture the raw Slack-sourced context + a permalink back to the original message, so future runs can trace the attribution.

## Rate limits

Affinity V1 allows roughly **50 requests/minute** per API key. Batch where possible. The skill's normal weekly run (~5 search calls + 1 list-entries call + 10–20 write calls on approval) stays well under.

On 429 responses, back off with a 60-second pause before retrying. Don't hammer.

## Gotchas

1. **`/lists/{id}/fields` returns "Unknown API endpoint"** — fields come embedded in the `/lists/{id}` response instead. Don't try the separate fields endpoint.
2. **Bearer auth on V1** — older Affinity docs still show Basic auth (`-u :$KEY`). That stopped working; use Bearer.
3. **Dropdown values are IDs, not strings** — when setting a Status field, pass the numeric `dropdown_options[i].id`, not the text.
4. **Entity search is fuzzy, not exact** — a search for "Peterson" will return multiple orgs. Always eyeball the `domain` field to pick the right one; don't blindly take the first result.
5. **Auto-ingested contacts** — people added to Affinity via email auto-capture may not have a `first_name` / `last_name` split cleanly (sometimes stored as a single full name in one field). Handle gracefully.

## Further reading

- Official Affinity API docs: https://api-docs.affinity.co/
- V2 preview: https://api-docs.affinity.co/#introduction-to-affinity-api-v2 (still gaining endpoints)
