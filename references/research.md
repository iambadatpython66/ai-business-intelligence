# Evidence collection and source handling

## Discovery and freshness

Use the capabilities actually available in the host. Prefer existing web-search/page-fetch tools, public market-data APIs, regulatory and company sources, and already-connected research services. If a connector tool search exists, discover the required read-only search, extraction and market-data operations, review complete schemas and active connection status, and respect provider restrictions. Never assume a tool from an earlier environment is present. Native public browsing is a suitable alternative when authorised; unavailable connectors do not justify guessing an API or credentials.

For example, some Composio environments offer Parallel web search and Tinyfish URL fetching. These are examples, not dependencies or guaranteed availability. Discover them before execution, respect instant-account allowlists and pricing, and inspect every per-URL result and error. A successful batch response can contain failed pages. Do not initiate paid or new authentication workflows unnecessarily when existing authorised capabilities suffice.

Compute the research start as `as_of` minus `window_days`, and priority start as `as_of` minus `priority_days`. The default is 30 and seven days. Query today's news separately and record source-local dates when relevant. Treat publication time, event time, market quote time and retrieval time as different fields. Retrieval today does not make an old article current. A search provider's date filter is a useful search aid, not proof of a publication date.

Keep historical sources for competitor background or structural market context only, marked `historical: true`. They cannot substitute for current consumer demand. Sources with unknown publication dates must have `published_at: null`; they cannot qualify as recent evidence merely because the model infers a date. Do not include events later than `as_of` in the research window. Retrieval times may follow the run's starting `as_of`.

If only a publication calendar date is visible, preserve it in an optional `published_date` field and leave `published_at` null unless an actual publication timestamp and timezone are known. Do not manufacture a time or timezone to satisfy the current-demand gate; seek timestamped evidence instead.

## Source record

Preserve the complete raw tool response at a relative path such as `raw/news/search-001.json`, and record the role, tool, arguments without secrets, request time, response time and per-source outcome in the handoff artifacts. Extract each claim's supporting passage into a source record with its canonical URL, title, publisher, source type, publication time or null, retrieval time, access status and independence key. Optional additional metadata may retain event time, quote time, exchange, currency, adjustment basis, raw-response path and exact tool attribution without changing the required contract.

`access: direct` means the page or authorised API response was actually retrieved and inspected. `excerpt_only` means only a search excerpt or secondary snippet was available. `unavailable` records a failed source and cannot support a factual claim. Preserve short exact passages where practical; clearly identify summaries as summaries. Do not fabricate quotes, paraphrase a snippet as a firsthand observation, or substitute a homepage link for a specific thread or release.

The `independence_key` represents the real originating publisher, study, customer thread or dataset. Syndicated copies and articles quoting the same press release share the originating key. Community threads count independently only when they represent distinct conversations and authors; repeated posts, copied text and a single prolific commenter are not multiple customers. Inspect duplicates before counting them. Site names and manufactured IDs alone do not prove independence.

Every factual finding and debate argument cites supporting source IDs. An estimate cites its external inputs and names its assumptions. An assumption is explicitly labelled and is not counted as evidence. User complaints are evidence of those users' experiences, not automatically the prevalence of a problem. Engagement, upvotes and stock returns are not measures of willingness to pay.

## News researcher coverage

Start broadly across regions and sectors, then pursue concrete triggers: new regulation, enforcement or deadlines; supply constraints; labor and workflow changes; newly affordable technology; disruptions; and changes in existing products or pricing. Prioritise primary regulations, regulator notices, company releases and dated reporting. Separate a rule's proposal, adoption, entry into force and enforcement date. Explain who must act, what changes, and what evidence suggests a buyer or urgent workflow.

Avoid building the whole report from one country's headlines unless a country filter requests that scope. Identify research limits explicitly rather than calling a narrow search global coverage.

## Stock-market researcher coverage

Research both gains and declines, relevant sector and benchmark trends, and unusual price or volume activity. Use the latest available market session and state quote date/time, exchange timezone, currency, delay and session status. On weekends and holidays, label the last completed session; do not describe it as a live movement today. When calculating percentage changes, retain the actual price observations, comparison interval and adjustment basis. Do not mix intraday, close-to-close and 30-day returns.

Unusual volume requires a reported or computed comparison baseline with its period. Do not label volume unusual from a large absolute number alone. Consider splits, dividends, currency changes, ticker changes, earnings and sector-wide moves when relevant. Use official filings, earnings releases, exchange or licensed API data, and credible dated reporting. Attribute reported explanations; call a model's inferred explanation an assumption. Correlation between a headline and a price move is not proof of cause.

Do not invent unavailable quotes, return percentages, volume statistics, market capitalisation, market size or consensus numbers. If reliable quote data is inaccessible, provide documented company and sector developments with a quote-data gap. Shortlisted opportunities still need direct consumer evidence and cross-stream support.

## Consumer researcher coverage

Search relevant public discussions on Reddit, Hacker News, Indie Hackers, 4chan, specialist forums, product communities and other accessible public sources. Attempt coverage appropriate to the proposed market and record inaccessible platforms. 4chan threads may expire; preserve inspected thread URLs, timestamps and a supporting passage before expiry, and treat anonymous unverifiable claims cautiously. Do not invent archived contents or bypass a site's restrictions.

Look for a repeated specific task, who performs it, the frequency and consequence of failure, present workarounds, products already tried, price complaints, active purchases, budget, explicit requests and willingness to pay. Preserve the customer's actual language and distinguish a complaint from a paid buying signal. Investigate counterevidence such as satisfied users, free substitutes, low urgency and abandoned purchasing attempts.

A qualified idea needs at least two distinct current community conversations with direct access and genuinely independent origins, plus another independent source and at least two research streams. This is a minimum, not a representative market survey. A repeated pattern without buyer identity or payment evidence should lower the demand score and become an interview question.

## Failures and verification

Record failures as structured objects or strings describing URL/tool, timestamp, error type, attempts, and alternative used. Retry a transient timeout or temporary rate limit at most twice per source with a bounded delay. Authentication, quota exhaustion, billing failure, disabled tools, policy restrictions and access-control failures are hard stops for the affected connector workflow. Inform the user, preserve the returned restriction, and do not attempt speculative retries or workarounds. A connector reported as active, or a listed free discount, does not prove that execution will succeed. Restart the restricted live workflow only after external access or credits are restored. Local artifact validation may continue. Do not keep polling expired threads or repeatedly request the same blocked page. For ordinary inaccessible public pages, use authorised alternatives and clearly label secondhand evidence; do not use alternatives to evade a connector restriction.

Before selection, inspect the pivotal evidence for each idea: current direct customer passages, actual competitor offerings/prices, the dated market or news trigger, cost inputs and the strongest attack. Verify that source links resolve when possible and that their contents support the stated claim. A JSON validator checks records and reference integrity, not whether a publisher is truthful or a quoted passage was really observed.
