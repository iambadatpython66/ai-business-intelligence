param([Alias('RunPath')][string]$SmokeRunPath = (Join-Path $PSScriptRoot 'artifacts\native-agent-smoke'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\pipeline.ps1')
$state = Read-State -RunPath $SmokeRunPath
$state.capabilities.agent_mode='parallel_independent'
$state.capabilities.research_tools=@()
$state.capabilities.limitations=@('Three native independent researchers ran concurrently. Live connector execution was blocked by wallet credits. No live market evidence was collected.')
$state.research=@('news','markets','consumers' | ForEach-Object {
    Get-Content -LiteralPath (Join-Path $SmokeRunPath ('research\'+$_+'.json')) -Raw -Encoding UTF8 | ConvertFrom-Json
})
foreach ($report in $state.research) {
    if ($report.status -ne 'failed' -or @($report.sources).Count -ne 0 -or @($report.findings).Count -ne 0 -or @($report.failures).Count -eq 0) { throw "Unexpected failure-branch report for $($report.role)" }
}
Write-JsonAtomic -Path (Join-Path $SmokeRunPath 'state.json') -Value $state
$validation=Validate-State -State $state
if (-not $validation.valid) { throw ($validation.errors -join '; ') }
$completion=Complete-Run -RunPath $SmokeRunPath
if ($completion.exit_code -ne 2 -or $completion.eligible_count -ne 0) { throw 'Failed research incorrectly produced a successful report.' }
if (Test-Path -LiteralPath (Join-Path $SmokeRunPath 'final.json')) { throw 'Failed research produced final business ideas.' }
$shortage=Get-Content -LiteralPath (Join-Path $SmokeRunPath 'shortage.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (@($shortage.research_coverage).Count -ne 3) { throw 'Shortage artifact lost research coverage.' }
foreach ($coverage in $shortage.research_coverage) { if (@($coverage.failures).Count -eq 0) { throw 'Shortage artifact lost the access failure.' } }
$result=[pscustomobject]@{
    status='passed'; tested_at=[DateTimeOffset]::UtcNow.ToString('o')
    mode='parallel_independent'; independent_roles=@('news','markets','consumers')
    research_sources=0; fabricated_findings=0; final_ideas=0
    expected_outcome='insufficient_evidence'; actual_outcome=$completion.status
    note='Native agent report generation was tested under an actual recorded connector billing failure. This is not a live research success test.'
}
Write-JsonAtomic -Path (Join-Path $SmokeRunPath 'smoke-results.json') -Value $result
$result | ConvertTo-Json -Depth 10
