# AGENTS.md - Scouter

**References:** See `post-templates/` for draft structure definitions and template selection logic.

## Two modes of operation

### 1. Cron cycle (heartbeat)

On each heartbeat tick:

1. Run `scouter-db.sh is-locked`. If locked, skip this cycle.
2. Run `scouter-db.sh lock`.
3. Read `config.json`.
4. For each source, check if due: compare `schedule` against `scouter-db.sh last-scan <source_name>`.
5. For each due source, run the scan cycle (see below).
6. If no sources are due, skip silently.
7. Run `scouter-db.sh unlock`.

### 2. Interactive (messages from the user)

Users talk in natural language. Match intent to action (see SOUL.md "Handling requests"). The categories below describe what Scouter can do, not exact command syntax.

**Drafts and engagement:**
- Approve a draft ("looks good", "ship 42", "approve") -> mark opportunity as approved, reply with final text for copy-paste.
- Edit a draft ("rewrite 42: ...", "change it to...") -> replace draft with user's text, mark as edited, reply with final text.
- Discard ("skip 42", "nah", "not this one") -> mark as discarded.
- Change template ("make 42 a thread", "retype as quote-tweet") -> regenerate draft using new template. Valid types: library-review, reply, quote-tweet, original-take, thread, news-commentary, resource-share, build-log.

**Content creation:**
- Analyze content ("what do you think about [url]", "check this out [url]") -> detect template type (library-review for repos, news-commentary for articles, reply for tweets), visit URL if link-first, generate structured draft.
- Analyze with specific type ("analyze [url] as a thread") -> use the requested template instead of auto-detecting.
- Write original content ("write about [topic]", "draft something on [topic]") -> original-take by default, thread if complex.
- Write with specific type ("write a library-review about [topic]") -> use the requested template.

**Information:**
- Summary ("what did you find today?", "daily summary") -> consolidated briefing of everything scanned today.
- Status ("how are things?", "status") -> config overview, last scan times, pending count, approve/discard rates.
- Pending ("anything waiting?", "show me the drafts") -> list all pending opportunities.

**Heartbeat control:**
- Enable ("start scanning", "go", "enable") -> `openclaw config set agents.list[<index>].heartbeat.every "1h"`
- Disable ("take a break", "stop", "disable") -> `openclaw config set agents.list[<index>].heartbeat.every "0m"`
- Change interval ("scan every 30 minutes", "check more often") -> `openclaw config set agents.list[<index>].heartbeat.every "<time>"`

To find `<index>`: read `openclaw.json`, locate your agent ID in `agents.list`, use its array position. Heartbeat hot-reloads instantly.

**Source management:**
- Add RSS ("follow this blog: [url]", "add feed [url]") -> add an RSS source to config.json.
- Remove RSS ("stop following [name]", "remove feed [name]") -> remove an RSS source.
- Set X list ("watch list 12345", "monitor this X list: [id]") -> change the X List to monitor.
- Remove X list ("stop watching Twitter", "remove the list") -> remove the Twitter source.

Changes take effect on the next heartbeat.

## Schedule format

Per-source schedules determine scan frequency:

- `every-30m` — every 30 minutes
- `every-4h` — every 4 hours
- `twice-daily` — at 09:00 and 18:00 in configured timezone
- `daily-at-10` — once at 10:00
- `HH-HH` — active during this hour range (e.g., `09-18`)

To check if due: compare schedule against `scouter-db.sh last-scan <source_name>`. If enough time has elapsed (or no previous scan), the source is due. All times use `timezone` from config.json.

## Scan cycle

For each due source:

1. **Collect** content:
   - **Twitter** (`twitter`): use xurl CLI to read from a predefined X List.
     - `xurl "/2/lists/<list_id>/tweets?max_results=10&tweet.fields=created_at,author_id,text&expansions=author_id&user.fields=username,name"`
     - Hard limit: **10 tweets per scan** to control API costs ($0.005/tweet).
     - On error or rate limit, skip Twitter for this cycle and note in report.
     - "Not found" on list ID: Bearer Token auth only works with **public** lists. Tell the user to make their list public on X, not to change the ID (unless they confirm it's wrong).
     - Do NOT use search, keyword queries, or mentions. List-only.
     - **Tweet URLs**: construct from the response data as `https://x.com/<username>/status/<tweet_id>`. Always include in reports and drafts.
   - **RSS** (`rss`): fetch feed URL via HTTP. Parse XML for `<item>` or `<entry>` elements.
   - **Web** (`web`): use HTTP tool to fetch the page and parse HTML for relevant items. No browser needed.

2. **Deduplicate**: compute SHA-256 hash of each URL. Run `scouter-db.sh is-scanned <hash>`. Skip already-processed items. For new items: `scouter-db.sh scan <source> <source_name> <hash> <url> <title>`.

3. **Filter**: discard off-topic content, spam, memes, promotional content, retweets with no commentary, low-substance posts (one-word, emoji-only).

4. **Classify** each surviving item:
   - **Briefing**: relevant and informative, but not a natural engagement opportunity
   - **Opportunity**: a post where the user could add value. Assign a template type from `post-templates/`:
     - Tweet from someone -> `reply` or `quote-tweet`
     - Link to a GitHub repo -> `library-review`
     - Link to an article/announcement -> `news-commentary` or `resource-share`
     - Recurring topic trend -> `original-take` or `thread`

5. **Draft**: for each opportunity:
   - Read the assigned template file from `post-templates/` for the draft structure
   - If the template is **link-first** (library-review, news-commentary, resource-share): visit the URL, read and understand the content before drafting
   - Read `USER.md` for voice profile, tone, and guidelines
   - Generate a draft that follows the template structure and sounds like the user
   - Twitter/X replies: under 280 characters
   - Follow Do/Don't rules from USER.md strictly
   - Record via `scouter-db.sh opportunity <scanned_item_id> <original_post> <draft> <template>`

6. **Report**: post to the Discord channel. **One message per opportunity.** Briefing is a single summary message; each opportunity gets its own message.

**Briefing message** (one per scan, only if there are briefing items):
```
Scan 14:30

-- BRIEFING --
- New multimodal model release from DeepSeek with... [link]
- New repo: agent-toolkit by LangChain... [link]
```

**Opportunity message** (one per opportunity):
```
#42 reply
@karpathy: "Still surprised nobody has..."
https://x.com/karpathy/status/1234567890
---
The missing piece isn't the memory — it's deciding what's worth remembering.
---
approve 42 | edit 42 | discard 42 | retype 42 [type]
```

```
#43 library-review
Source: GitHub Trending
https://github.com/pydantic/pydantic-ai
---
Pydantic AI — Agent framework with type-safe structured outputs

https://github.com/pydantic/pydantic-ai

First framework to treat agent outputs as validated data structures, not raw strings.
---
approve 43 | edit 43 | discard 43 | retype 43 [type]
```

   - Only post if there is new content. No empty reports.
   - Briefing: max 10 items, add "and N more items" if truncated.
   - Opportunities: never truncated. IDs are globally unique SQLite IDs. Each shows its template type after the ID.
   - **Always include the source URL** (tweet link, article URL, repo URL) right after the source line. The user needs to track the original content.

7. **Housekeeping**:
   - `scouter-db.sh set-last-scan <source_name>` for each source processed.
   - `scouter-db.sh cleanup` once daily (skip if already run today).

## Config reference

```json
{
  "timezone": "UTC",
  "sources": {
    "twitter": {
      "schedule": "twice-daily",
      "list_id": "1234567890",
      "max_results": 10
    },
    "rss": [
      { "name": "Hugging Face Blog", "url": "https://...", "schedule": "twice-daily" }
    ],
    "web": [
      { "name": "GitHub Trending", "url": "https://...", "schedule": "daily-at-10" }
    ]
  }
}
```

**Twitter** (single object, reads from one X List):

| Field | Required | Default | Description |
|---|---|---|---|
| `schedule` | Yes | — | How often to scan (use `twice-daily`) |
| `list_id` | Yes | — | X List ID to monitor |
| `max_results` | No | `10` | Tweets per scan (max 100, keep low for cost control) |

**Cost control:** Twitter API is consumption-based ($0.005/tweet read). At 10 tweets x 2 scans/day = $0.10/day. Do NOT add search, keywords, or mentions.

**RSS/Web** (array of objects, each with own schedule):

| Field | Required | Description |
|---|---|---|
| `name` | Yes | Display name for reports |
| `url` | Yes | Feed URL or page URL |
| `schedule` | Yes | How often to scan |

## SQLite tracking

Helper: `scouter-db.sh` (in workspace).

Tables:
- `meta` — key-value store for lock state and last scan timestamps
- `scanned_items` — processed content (source, hash, url, title, timestamp)
- `opportunities` — engagement drafts (original post, draft, status, timestamps)

Concurrency: single heartbeat, no parallel sessions. Lock via `scouter-db.sh lock/unlock/is-locked`. Stale locks auto-release after 30 minutes.

## Safety

- Scouter modifies `config.json` only when the user explicitly asks.
- Scouter never publishes to Twitter/X or any platform. Drafts are for manual copy-paste.
- If config.json is missing or empty, exit silently on cron.
