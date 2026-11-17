---
name: ai-business-intelligence
description: Discover and evaluate evidence-backed business opportunities through independent news, stock-market and consumer research, business strategy, and adversarial debate. Use when asked to research market gaps or deliver validated business ideas.
---

# AI Business Intelligence

Deliver exactly three qualified business ideas supported by dated, inspectable real-world evidence. Run six specialised roles: News Researcher, Stock Market Analyst, Consumer Researcher, Business Strategist, Defender, and Attacker. Research and debate are independent where the host supports agents. Never claim that sequential role emulation is independent research.

## Prepare the run

1. Inspect applicable project instructions and available agent, search, browser, market-data API, and connector capabilities. Discover tools and read their actual schemas before calling them; record connection availability and limits. Use existing authorised read-only capabilities. Never hardcode credentials, invent tool names, or create external posts or messages as part of research.
2. Use the host's current UTC time as `as_of`. Default to the preceding 30 days, prioritising the latest seven days and today's developments. Apply optional country, industry, startup-budget amount and currency, and business-type filters. An absent filter means unrestricted; do not ask the user to select filters before proceeding. Interpret a supplied budget without a currency only when context makes the currency clear; otherwise ask while doing independent research.
3. Create a fresh run directory outside the skill package. Keep `state.json`, raw tool responses, agent reports, handoff packets, and final artifacts there. Read [references/report-contract.md](references/report-contract.md) for the JSON contracts and helper commands. On Windows use `powershell -NoProfile -ExecutionPolicy Bypass -File <skill>/scripts/pipeline.ps1 -Command init -RunPath <run-directory>` and supply known filters. The bypass applies only to that process, with no persistent execution-policy change. On PowerShell 7 use `pwsh -NoProfile -File <skill>/scripts/pipeline.ps1 -Command init -RunPath <run-directory>`. If neither runtime is available, use the contracts and calculations manually and disclose that automated validation was unavailable.
4. Set `capabilities.agent_mode` truthfully: `parallel_independent`, `sequential_independent`, or `sequential_roles`. List usable research tools and limitations. Initialise a run only once; resume existing artifacts rather than overwriting work.

## Research in parallel

Read [references/research.md](references/research.md) and the three researcher prompts in [references/agent-prompts.md](references/agent-prompts.md).

When independent agents are supported, spawn all three researchers before waiting for any result. With a four-slot limit, the coordinator plus three researchers fits; do not reserve extra agents that prevent the required parallel research. Give each the same config and research contract, a unique role and source-ID prefix, and a distinct output path. Give researchers no other researcher's conclusions. Each writes its own structured report and raw response files. Tool calls within each role can also be batched when independent.

Wait for all three reports and inspect every result. Validate source dates, access status, references, and coverage before incorporating the reports into `state.json`. News covers today's global news and emerging problems, technologies, rules and industry shifts. Markets covers current rising and falling stocks, sectors, unusual activity and documented explanations. Consumers covers Reddit, Hacker News, Indie Hackers, 4chan, forums and other relevant public communities, looking for repeated complaints, explicit product requests, current workarounds and evidence of willingness to pay.

A failed site is a recorded coverage gap, not evidence of absent demand. Retry a transient failure at most twice per source, then use an authorised alternative public source. A quota, billing, authentication, disabled-tool or policy restriction is a hard stop for that connector workflow: record it, inform the user, and do not attempt speculative retries or workarounds. An active connection is not proof of available credits or successful execution; restart a restricted live workflow only after access is restored. Never bypass access controls, invent inaccessible comments or financial figures, or turn a search snippet into a claimed direct page inspection. If an entire research role fails, record `failed` or `partial` and preserve the limitation.

When parallel scheduling is unavailable, run the three independent researchers sequentially. When independent agents themselves are unavailable, execute the role prompts sequentially with separate files, and set `sequential_roles`. Preserve the same evidence and scoring requirements in every mode.

## Generate and shortlist

After the research barrier, give a fresh Business Strategist agent the complete validated research bundle. Allow completed research workers to finish before scheduling new roles within the host's concurrency limit. If the host cannot create fresh workers, use explicit sequential role passes and record the independence limitation; a reused conversation does not become an independent new agent merely by changing its role.

Generate 10–15 distinct candidates. Each must include the problem, target customers, solution, researched competitors, revenue model, opportunity, startup complexity, supporting evidence, connected research findings, estimated startup cost and monthly revenue with explicit assumptions. Distinguish facts, estimates and assumptions throughout. Connect at least two research streams per shortlisted candidate; stock movements indicate context, not proof of customer demand.

Shortlist three to six candidates using evidence strength, identifiable buyers, realistic acquisition paths, feasible delivery and defensible differentiation. Keep rejected candidates and reasons in the run artifacts so weak ideas cannot reappear under new names. Keep ideas within any supplied budget and business-type constraints, or label them ineligible rather than silently changing the filters.

## Debate every shortlisted idea

Read the Defender and Attacker prompts in [references/agent-prompts.md](references/agent-prompts.md). Run two independent agents with opposing roles. They receive identical idea and research packets. Within a round, each submits its argument before seeing the other's new response. Then the coordinator creates the next-round packet containing both completed responses and newly verified evidence.

Complete at least three and at most five paired rounds for each shortlisted idea:

1. Independently assess demand, business model, competition, pricing, costs and execution; state measurable success or failure conditions.
2. Respond to the strongest opposing claim using dated evidence; investigate pivotal unknowns and unit economics.
3. Reassess after rebuttals; identify the strongest supported case, unresolved questions and kill criteria.

Use rounds four and five only when a specific unresolved issue could change selection and can be investigated. Agreement is not a stopping condition. A failed or incomplete response does not count as a completed paired round; retry once with the saved packet, then mark the idea unqualified if the required rounds cannot be completed. The fifth round is a hard stop. Add new sources to the appropriate research report before referencing their IDs.

Every completed debate response needs at least one cited factual or estimated argument; a collection of assumptions cannot satisfy the evidence requirement. Complete the required paired rounds for every retained shortlisted candidate before finalisation. If a worker failure prevents this, preserve the failed attempts and rejection reason, set that candidate's `shortlisted` to false, and research replacements as needed.

With one worker slot, create distinct fresh Defender and Attacker agents sequentially while withholding the current opposing response until both are saved. If separate fresh contexts cannot be created, use sequential role passes, set `sequential_roles`, and disclose the independence limitation. Do not call a single reused conversation independent or describe those passes as six actual agents.

## Score, replenish and report

Score every debated candidate from 0 to 100 with cited rationale for each metric. Apply these exact weights: customer demand 20%, market opportunity 15%, revenue potential 15%, competitive advantage 15%, feasibility 15%, market timing 10%, and risk 10%. A higher risk score means lower remaining risk. Use the rubric and quality gates in [references/report-contract.md](references/report-contract.md); default threshold is 70, with demand and feasibility each at least 60.

Run the helper with `-Command validate -RunPath <run-directory>` before finalisation, using the runtime command above. Automated checks verify structure and gates; the coordinator must also audit that cited excerpts actually support the claims, source independence is real, current data is current, and estimates follow their stated arithmetic. Never call a structural validation proof that research is true.

Run the helper with `-Command finalize -RunPath <run-directory>`. Only a successful qualified run may publish `final.json` and `report.md` as a completed report. Exactly three unique eligible ideas must appear, ordered by weighted score with deterministic tie-breaking.

If fewer than three qualify, read the shortage reasons, research the uncovered gaps, and generate a fresh batch of three to five distinct candidates. Append evidence and candidates, increment `replenishments`, debate each new shortlist, and rescore. Allow at most two replenishment cycles. Never lower the threshold, alter filters, relabel duplicate ideas, or pad the result to reach three. If the bound is exhausted or evidence access prevents progress, return the incomplete-run artifact and specific missing evidence; do not present fewer than three as successful completion.

The final report includes, for each selected idea: overview; problem and solution; target market; researched competitors; revenue model; market evidence with source links and publication/retrieval dates; startup-cost and revenue estimates with currency, basis and assumptions; the Defender's strongest argument; the Attacker's strongest criticism; remaining risks; the first 30-day plan with measurable outcomes; final score and verdict. Include a source register and disclose coverage failures, data delays, fallback mode and unresolved assumptions.
