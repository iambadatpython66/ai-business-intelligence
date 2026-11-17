# Run, handoff and final-report contract

## Helper commands

The dependency-free helper runs on Windows PowerShell 5.1 or PowerShell 7. Invoke it from its actual installed skill location; all run paths may be elsewhere.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/pipeline.ps1 -Command init -RunPath ./runs/opportunities -AsOf '2026-11-17T07:00:00Z'
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/pipeline.ps1 -Command init -RunPath ./runs/filtered -Country 'UAE' -Industry 'logistics' -Budget 10000 -Currency 'AED' -BusinessType 'B2B SaaS'
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/pipeline.ps1 -Command validate -RunPath ./runs/opportunities
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/pipeline.ps1 -Command finalize -RunPath ./runs/opportunities
```

These paths assume the current location is the skill folder; otherwise use the absolute installed helper path. `-ExecutionPolicy Bypass` is process-scoped and does not change the machine's persistent policy. On PowerShell 7 use `pwsh -NoProfile -File ./scripts/pipeline.ps1 -Command ...` with the same remaining arguments. The explicit `-Command` parameter is required.

The date above is only an invocation example: actual research always uses the host's current clock or the user's explicit historical `as_of`. `init` creates a fresh `state.json`. Populate it through structured handoffs before validation and finalisation. Do not execute `init` over an existing run. Validation or qualification failures are non-success outcomes; inspect the emitted diagnostics. Finalisation publishes exactly three qualified ideas or an explicit shortage artifact, never a padded report.

## Bundle and research objects

The version-one root object contains:

```json
{
  "schema_version": 1,
  "config": {
    "run_id": "unique-run-id",
    "as_of": "RFC3339 UTC timestamp",
    "window_days": 30,
    "priority_days": 7,
    "filters": {
      "country": null,
      "industry": null,
      "business_type": null,
      "startup_budget": null
    },
    "quality_threshold": 70,
    "min_rounds": 3,
    "max_rounds": 5,
    "max_replenishments": 2
  },
  "capabilities": {
    "agent_mode": "parallel_independent",
    "research_tools": [],
    "limitations": []
  },
  "research": [],
  "candidates": [],
  "debates": [],
  "evaluations": [],
  "replenishments": 0
}
```

Use ISO/RFC3339 timestamps containing a timezone; normalise to UTC. A supplied startup budget is `{"amount": 10000, "currency": "AED"}`. Amount must be nonnegative and currency explicit. Optional extra provenance fields are permitted but do not replace required fields.

There is one research report per role: `news`, `markets`, `consumers`. Each report has `role`, `status` (`complete`, `partial`, `failed`), `sources`, `findings`, `gaps`, and `failures`. Empty research is a documented failure or partial result, not a complete report.

Every source has:

| Field | Meaning |
| --- | --- |
| `id` | Globally unique source ID, prefixed by its originating role |
| `url` | Specific public HTTP(S) page/API or thread URL |
| `title`, `publisher` | Observed source title and publisher |
| `source_type` | `primary`, `news`, `community`, `market_data`, `competitor` |
| `published_at` | Publication timestamp, or null when unknown |
| `retrieved_at` | Actual retrieval timestamp |
| `excerpt` | Inspected supporting passage or accurately labelled summary |
| `access` | `direct`, `excerpt_only`, `unavailable` |
| `independence_key` | Real originating publisher, dataset or distinct conversation |
| `historical` | Boolean marking contextual evidence outside the current window |

A finding has `id`, `claim`, `kind` (`fact`, `estimate`, `assumption`), `evidence_ids` and `category`. Fact records need usable citations. Estimate records identify their external inputs and assumptions in the claim or associated handoff. Assumptions never become facts by being repeated in another role. New evidence during debate is appended to the proper originating research report with globally unique source IDs before merging the debate record.

## Candidate

Each candidate has `id`, `name`, `overview`, `problem`, `target_customers`, `solution`, `competitors`, `revenue_model`, `market_opportunity`, `startup_complexity`, `supporting_evidence_ids`, `research_connections`, `shortlisted`, `finances`, `remaining_risks` and `action_plan`.

Use `target_customers` as clear prose identifying users and paying buyers. `competitors` is an array of `{name, url, evidence_ids}` with actual researched alternatives; a free workaround can be a competitor when relevant. `market_opportunity` is `{text, kind, evidence_ids}`. `startup_complexity` is `low`, `medium` or `high`. `research_connections` contains finding IDs from the connected reports; citations themselves go in `supporting_evidence_ids`. `shortlisted` is a boolean. Keep candidate IDs stable across rounds and replenishments.

`finances` has `currency`, `startup_cost` and `monthly_revenue`. Each monetary scenario has `low`, `high`, `kind: "estimate"`, `basis`, `evidence_ids` and `assumptions`. Bounds are nonnegative with `low <= high`. State units, time horizon, launch versus recurring costs, and the customer count × price calculation. Cite researched input costs/prices and list assumptions such as conversion, sales volume, capacity or founder unpaid labor. Do not present gross revenue as profit. Budget eligibility must use matching currency and startup costs; do not fabricate currency conversion rates. The helper rejects an idea when even its low startup estimate exceeds the budget. If the high estimate exceeds the budget, the coordinator must explicitly explain an evidenced lower-cost viable launch and record the overrun risk before treating the idea as eligible; a low number alone is not proof that the launch fits.

`remaining_risks` is an array of clear risk descriptions. `action_plan` is an array of `{days, action, success_metric}` covering the first 30 days. Use ASCII date ranges such as `1-7`, `8-14`, `15-21`, `22-30`, actions tied to pivotal uncertainties, and observable interview, prototype, pilot or purchasing thresholds.

Generate 10–15 candidates initially and shortlist three to six. Each replenishment adds and shortlists three to five distinct candidates; increment `replenishments`. Retain all prior candidates and debates for audit; the retained shortlist may exceed six after replenishment, bounded by six plus five per replenishment. Do not recreate a rejected idea under a different ID.

## Debate record

Each record has `idea_id`, `round` (integer 1–5), `role` (`defender`, `attacker`), `status` (`complete`, `failed`), `arguments`, `strongest_argument`, `unresolved_questions` and `kill_criteria`. There is at most one completed record for each idea/round/role. Arguments use `{claim, kind, evidence_ids}`. `strongest_argument` is a supported prose statement drawn from those arguments; its cited basis must remain inspectable. Questions and kill criteria are arrays of measurable statements.

Only consecutive paired completed rounds count. A shortlist must have rounds 1, 2 and 3 from both opponents; optional rounds 4 and 5 also need both responses. A failed record does not replace a completed paired round. The coordinator must preserve failed attempts in separate logs rather than overwrite the successful record or count a duplicate as another round.

Each completed response must contain at least one usable cited fact or estimate argument; additional labelled assumptions are permitted. Finalisation waits for the required paired rounds of every candidate still marked `shortlisted`. Keep failures and rejection reasons in the audit artifacts when removing an unqualified candidate from the retained shortlist.

## Evaluation and quality gates

Each evaluation has `idea_id`, `scores`, `rationale`, `fatal_flaw` and `verdict`. Scores have exactly these metrics, each 0–100; rationale maps every metric to `{text, evidence_ids}`.

| Metric | Weight | Strong score requires |
| --- | ---: | --- |
| `customer_demand` | 20% | Specific paying buyer, repeated current pain and credible buying signals |
| `market_opportunity` | 15% | Addressable buyer segment and supported scale without invented TAM |
| `revenue_potential` | 15% | Plausible price, acquisition and delivery economics with explicit scenarios |
| `competitive_advantage` | 15% | Researched alternatives and a differentiation customers can value |
| `feasibility` | 15% | Realistic delivery, skills, costs and first validation path within constraints |
| `market_timing` | 10% | Current verified trigger and practical buying/implementation timing |
| `risk` | 10% | Lower remaining risk earns the higher score; crucial unknowns lower it |

A score near 0 means absent or contrary support; near 50 means mixed evidence or large unresolved assumptions; near 75 means strong relevant support with manageable gaps; near 100 requires unusually strong direct validation and limited uncertainty. Do not award precision that evidence cannot justify. Apply the same anchors to every candidate.

Compute `sum(score × weight_percent) / 100` on the unrounded scores; round only for display. Default qualification requires weighted score at least 70, demand and feasibility each at least 60, no supported fatal flaw, and every applicable filter satisfied. It also requires at least three genuinely independent source origins including two distinct direct-access community conversations with known publication dates inside the research window, support across at least two research roles, researched competitors, explicit cited financial inputs/assumptions, and three to five completed paired debate rounds. Unknown source dates, unavailable sources, historical background and unsupported claims do not count toward current-demand gates.

An evaluation cannot rescue an unsupported factual claim merely by giving it a high score. Fatal flaws include evidence-supported legal or technical impossibility, a viable startup cost above the supplied budget without a supported cheaper launch, or business economics shown to be unworkable. An unresolved question is not automatically a fatal flaw; it lowers the appropriate score and becomes a validation action or a reason to research more.

## Final artifacts

Retain `state.json`, all role reports, source raw responses, debate packets and validation diagnostics. A successful `final.json` contains exactly three unique qualified selections and their weighted scores. `report.md` is the human-readable report. A shortage artifact explains why fewer than three passed and what evidence or new research is needed. An incomplete run is never labelled a successful three-idea report.

The report opens with as-of time, research window, filters, actual execution mode and material coverage gaps. For each selection give every required business, financial, debate, risk and 30-day-plan field, a metric score breakdown and verdict. Label factual observations, estimates and assumptions plainly and put source links next to substantive claims. Include a source register with publication/retrieval timestamps, access limitations and source origins. Keep the strongest defence and attack visible even when the final evaluator disagrees.

## Local verification

Run `tests/test-skill.ps1` and `tests/test-pipeline.ps1` with the same PowerShell invocation shown above. They check skill discovery, resource links, parsing, evidence integrity, dates, scoring, debate limits, filters, exactly-three output, and incomplete-run behavior. Generated fixture files use reserved `fixture.invalid` URLs and an explicit `test_fixture` flag; they are not market research. `tests/test-native-smoke.ps1 -RunPath <run>` consumes three previously generated native-agent failure reports at `research/news.json`, `research/markets.json`, and `research/consumers.json` to verify the access-failure branch. It makes no network or agent calls itself and requires those reports to exist.
