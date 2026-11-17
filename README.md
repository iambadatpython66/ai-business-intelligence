# AI Business Intelligence

A reusable Codex skill that researches current market gaps, generates business opportunities, and challenges them through evidence-based debate. A successful run delivers exactly three qualified ideas. If research access or evidence is insufficient, it reports the missing evidence instead of fabricating a result.

## How it works

1. **News Researcher**, **Stock Market Analyst**, and **Consumer Researcher** investigate independently and run in parallel when the host supports it.
2. **Business Strategist** connects the research, generates 10–15 candidates, and shortlists the strongest opportunities.
3. **Defender** and **Attacker** challenge every retained shortlisted idea for three to five paired rounds.
4. The coordinator evaluates demand, market opportunity, revenue, advantage, feasibility, timing, and risk, then selects exactly three qualifying ideas.

Research defaults to the previous 30 days, prioritising the latest seven days. Optional filters cover country, industry, startup budget and currency, and business type. Reports preserve source links, publication and retrieval timestamps, assumptions, financial estimates, criticism, and a measurable 30-day action plan.

## Requirements

- Codex or a compatible agent host that can read `SKILL.md` and its resources.
- Authorised web search, browsing, market-data APIs, or research connectors for current evidence. The skill discovers available tools; no provider or API key is embedded.
- Windows PowerShell 5.1 or PowerShell 7 for the local helper and automated tests.

Native host agents perform the research and debate. The PowerShell helper initializes runs, validates their saved reports, scores candidates, and renders final artifacts; it does not call models or research APIs. If parallel scheduling is unavailable, the skill uses sequential independent agents. If independent agents are unavailable, it discloses sequential role emulation.

## Install and use

Download or clone this repository, then copy the repository's skill files into a directory named `ai-business-intelligence` under your Codex skills directory. Normally this is `~/.codex/skills/ai-business-intelligence`; if `CODEX_HOME` is configured, use its `skills` directory.

You can also ask Codex to follow the repository's `SKILL.md` directly.

Example request:

```text
Use $ai-business-intelligence to research business opportunities in the UAE,
focused on B2B software with a startup budget of AED 10,000.
```

The complete orchestration instructions are in [SKILL.md](SKILL.md). Read [report contracts](references/report-contract.md) for structured handoffs, scoring gates, helper commands, and final report fields.

## Local helper

From the skill directory on Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/pipeline.ps1 -Command init -RunPath ./runs/example -Country UAE -Industry software -Budget 10000 -Currency AED -BusinessType 'B2B SaaS'
```

The Codex coordinator populates the generated `state.json` from the agents' structured reports. Then validate and finalize:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/pipeline.ps1 -Command validate -RunPath ./runs/example
powershell -NoProfile -ExecutionPolicy Bypass -File ./scripts/pipeline.ps1 -Command finalize -RunPath ./runs/example
```

PowerShell 7 users can replace `powershell -NoProfile -ExecutionPolicy Bypass` with `pwsh -NoProfile`. The Windows execution-policy setting applies only to the invoked process.

Successful finalization produces `final.json` and `report.md`. Insufficient evidence produces `shortage.json` with coverage gaps and failures. Debate rounds, source retries, and candidate replenishment are bounded. Estimated revenue remains conditional on explicit assumptions; it is not a profit forecast or proof of demand.

## Tests

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/test-skill.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File ./tests/test-pipeline.ps1
```

The pipeline suite contains 47 tests covering citations, freshness, source independence, score weights, budget constraints, debate completion, exact-three output, and failure handling. Fixtures use reserved `fixture.invalid` URLs and explicit synthetic markers; they are not real market research.

`tests/test-native-smoke.ps1 -RunPath <run>` additionally verifies three previously generated native-agent failure reports. It requires those reports to exist and performs no network or agent calls itself.

The build's independent-agent failure test verified that a blocked research connector produced no invented sources or business ideas. A successful live research run still requires functioning authorised research tools. Structural validation cannot establish that sources are truthful or that customers will buy; the coordinator must inspect the evidence.

## Repository contents

- `SKILL.md`: workflow and orchestration.
- `agents/openai.yaml`: skill discovery metadata.
- `references/`: six role prompts, research guidance, report contracts, and scoring rubric.
- `scripts/pipeline.ps1`: dependency-free validation and reporting helper.
- `tests/`: reproducible local checks.

Generated runs, raw research responses, local credentials, and test output are excluded from version control.
