# Scan Cycle

## Due sources this cycle
{{due_sources}}

## Instructions

For each due source:

### 1. Collect
- **Twitter**: use xurl CLI to read from the configured X List. See `TOOLS.md` for the exact command. Hard limit: 10 tweets per scan. Do NOT use search, keywords, or mentions.
- **RSS**: use HTTP tool to fetch the feed URL, parse XML for new entries since last scan.
- **Web**: use HTTP tool to fetch the page, parse HTML for relevant items. No browser needed.

### 2. Deduplicate
For each collected item, compute SHA-256 hash of the URL.
Run `scouter-db.sh is-scanned <hash>`. Skip if already processed.
For new items: `scouter-db.sh scan <source> <source_name> <hash> <url> <title>`.

### 3. Filter, classify, and assign template
Read `USER.md` for the user's topics of expertise and interests.
Read `post-templates/_index.md` for available template types and selection logic.
Evaluate each new item:
- **Discard**: off-topic, spam, memes, retweets with no commentary, promotional content.
- **Briefing**: relevant and informative, but not a natural engagement opportunity.
- **Opportunity**: a post where the user could add value. Assign a template type:
  - Tweet from someone -> `reply` or `quote-tweet`
  - Link to a GitHub repo -> `library-review`
  - Link to an article/announcement -> `news-commentary` or `resource-share`
  - Recurring topic trend -> `original-take` or `thread`

### 4. Draft
For each opportunity, generate a response draft:
- Read the assigned template file from `post-templates/` for the draft structure.
- If the template is **link-first** (library-review, news-commentary, resource-share): visit the URL and read the content before drafting.
- Read `USER.md` for voice, tone, and guidelines.
- Generate a draft that follows the template structure exactly.
- Follow the Do/Don't rules from the voice profile strictly.

### 5. Record
Insert each opportunity via `scouter-db.sh opportunity <scanned_item_id> <original_post> <draft> <template>`.

### 6. Report
Post a structured report to Discord (The Watchtower):

```
Scan 14:30

-- BRIEFING --
- New multimodal model release from DeepSeek with... [link]
- New repo: agent-toolkit by LangChain... [link]

-- OPPORTUNITIES --
#42 reply
@karpathy: "Still surprised nobody has..."
---
The missing piece isn't the memory — it's deciding what's worth remembering.
---
approve 42 | edit 42 | discard 42 | retype 42 [type]
```

- Only post if there is new content.
- Briefing: max 10 items, add "and N more items" if truncated.
- Opportunities: never truncated. IDs are globally unique SQLite IDs. Each shows its template type after the ID.

### 7. Housekeeping
- `scouter-db.sh set-last-scan <source_name>` for each source processed.
- `scouter-db.sh cleanup` (run once daily, not every cycle).

## Pending opportunities
There are currently {{pending_opportunities}} unresolved opportunities from previous scans.
