param([string]$ArtifactsPath = (Join-Path $PSScriptRoot 'artifacts'))
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '..\scripts\pipeline.ps1')

# These reserved-domain fixtures exercise contracts, not real market facts.
function New-TestState {
    $asOf = [DateTimeOffset]::UtcNow.AddMinutes(-1)
    $published = $asOf.AddDays(-2).ToString('o')
    $retrieved = $asOf.ToString('o')
    $sourceSpecs = @(
        @('N1','news','primary','news-publisher'),
        @('M1','markets','market_data','exchange'),
        @('C1','consumers','community','community/thread-one'),
        @('C2','consumers','community','community/thread-two'),
        @('K1','news','competitor','competitor')
    )
    $reports = @()
    foreach ($role in @('news','markets','consumers')) {
        $sources = @()
        foreach ($spec in $sourceSpecs) {
            if ($spec[1] -ne $role) { continue }
            $sources += [pscustomobject]@{
                id=$spec[0]; url=('https://fixture.invalid/' + $spec[0])
                title=('SYNTHETIC source ' + $spec[0]); publisher='SYNTHETIC test publisher'
                source_type=$spec[2]; published_at=$published; retrieved_at=$retrieved
                excerpt='SYNTHETIC TEST FIXTURE: example source excerpt; never market research.'
                access='direct'; independence_key=$spec[3]; historical=$false
            }
        }
        $ids = @($sources | ForEach-Object { $_.id })
        $reports += [pscustomobject]@{
            role=$role; status='complete'; sources=$sources
            findings=@([pscustomobject]@{id=($role + '-finding'); claim='SYNTHETIC observation'; kind='fact'; evidence_ids=$ids; category=$role})
            gaps=@(); failures=@()
        }
    }
    $candidates = @(); $debates = @(); $evaluations = @()
    $scoreValues = @(91,86,82,75,72)
    $metrics = @('customer_demand','market_opportunity','revenue_potential','competitive_advantage','feasibility','market_timing','risk')
    foreach ($number in 1..12) {
        $id = 'idea-' + $number.ToString('00')
        $candidates += [pscustomobject]@{
            id=$id; name=('SYNTHETIC opportunity ' + $number)
            overview='SYNTHETIC overview for deterministic validation.'
            problem='SYNTHETIC recurring customer problem.'; target_customers='SYNTHETIC small businesses'
            solution='SYNTHETIC proposed subscription service.'
            competitors=@([pscustomobject]@{name='SYNTHETIC competitor'; url='https://fixture.invalid/K1'; evidence_ids=@('K1')})
            revenue_model='SYNTHETIC monthly subscription hypothesis.'
            market_opportunity=[pscustomobject]@{text='SYNTHETIC reachable niche assumption.'; kind='assumption'; evidence_ids=@('N1','C1')}
            startup_complexity='low'; supporting_evidence_ids=@('N1','M1','C1','C2','K1')
            research_connections=@('news-finding','markets-finding','consumers-finding')
            shortlisted=($number -le 5)
            finances=[pscustomobject]@{
                currency='USD'
                startup_cost=[pscustomobject]@{low=500; high=1500; kind='estimate'; basis='SYNTHETIC 10-30 hours at assumed USD50/hour.'; evidence_ids=@(); assumptions=@('Founder hourly cost USD50; no paid licenses.')}
                monthly_revenue=[pscustomobject]@{low=0; high=1000; kind='estimate'; basis='SYNTHETIC 0-20 customers x assumed USD50/month; gross revenue.'; evidence_ids=@(); assumptions=@('Price USD50/month and up to20 customers; unvalidated conversion.')}
            }
            remaining_risks=@('SYNTHETIC acquisition and retention uncertainty.')
            action_plan=@(
                [pscustomobject]@{days='1-7'; action='Interview ten customers.'; success_metric='Five independently confirm repeated pain.'},
                [pscustomobject]@{days='8-14'; action='Offer a manual pilot.'; success_metric='Two paid pilots.'},
                [pscustomobject]@{days='15-21'; action='Deliver pilot and measure effort.'; success_metric='Delivery under two hours per customer.'},
                [pscustomobject]@{days='22-30'; action='Test recurring pricing.'; success_metric='One renewal and a documented continue/stop decision.'}
            )
        }
        if ($number -gt 5) { continue }
        foreach ($round in 1..3) {
            foreach ($role in @('defender','attacker')) {
                $debates += [pscustomobject]@{
                    idea_id=$id; round=$round; role=$role; status='complete'
                    arguments=@([pscustomobject]@{claim=('SYNTHETIC ' + $role + ' observation, round ' + $round); kind='fact'; evidence_ids=@('C1','C2')})
                    strongest_argument=('SYNTHETIC strongest ' + $role + ' case; supported by arguments.')
                    unresolved_questions=@('Does acquisition cost permit positive contribution margin?')
                    kill_criteria=@('Stop if no paid pilots after ten qualified offers.')
                }
            }
        }
        $scores = [ordered]@{}; $rationale = [ordered]@{}
        foreach ($metric in $metrics) {
            $scores[$metric] = $scoreValues[$number - 1]
            $rationale[$metric] = [pscustomobject]@{text='SYNTHETIC scoring judgment with unvalidated assumptions explicitly disclosed.'; evidence_ids=@('N1','C1','C2')}
        }
        $evaluations += [pscustomobject]@{idea_id=$id; scores=[pscustomobject]$scores; rationale=[pscustomobject]$rationale; fatal_flaw=$false; verdict='SYNTHETIC: validate with paid pilots.'}
    }
    [pscustomobject]@{
        schema_version=1; test_fixture=$true
        config=[pscustomobject]@{run_id='synthetic-test'; as_of=$asOf.ToString('o'); window_days=30; priority_days=7; quality_threshold=70; min_rounds=3; max_rounds=5; max_replenishments=2; filters=[pscustomobject]@{country=$null; industry=$null; business_type=$null; startup_budget=$null}}
        capabilities=[pscustomobject]@{agent_mode='parallel_independent'; research_tools=@('SYNTHETIC adapter'); limitations=@('All data is synthetic reserved-domain test data.')}
        research=$reports; candidates=$candidates; debates=$debates; evaluations=$evaluations; replenishments=0
    }
}

function Copy-TestState($State) { $State | ConvertTo-Json -Depth 100 | ConvertFrom-Json }
function Assert-True($Condition, [string]$Message) { if (-not $Condition) { throw $Message } }
function Assert-Invalid($State, [string]$Message) {
    $validation = Validate-State -State $State
    Assert-True (-not $validation.valid) $Message
}
function Assert-Rejected($State, [string]$IdeaId, [string]$Message) {
    $selection = Get-EligibleIdeas -State $State
    Assert-True (@($selection.eligible | Where-Object { $_.idea_id -eq $IdeaId }).Count -eq 0) $Message
}

$testResults = [System.Collections.Generic.List[object]]::new()
function Test-Case([string]$Name, [scriptblock]$Body) {
    try { & $Body; $testResults.Add([pscustomobject]@{name=$Name; passed=$true}); Write-Output ('PASS ' + $Name) }
    catch { $testResults.Add([pscustomobject]@{name=$Name; passed=$false; error=$_.Exception.Message}); Write-Output ('FAIL ' + $Name + ': ' + $_.Exception.Message) }
}

$fixture = New-TestState
Test-Case 'A fully evidenced fixture validates' {
    $result = Validate-State -State $fixture
    Assert-True $result.valid ($result.errors -join '; ')
}
Test-Case 'Weighted score matches specified weights' {
    $scores = [pscustomobject]@{customer_demand=100; market_opportunity=80; revenue_potential=60; competitive_advantage=40; feasibility=20; market_timing=10; risk=0}
    Assert-True ((Get-WeightedScore -Scores $scores) -eq 51) 'Expected weighted score51.'
}
Test-Case 'Five qualified ideas ranked deterministically' {
    $result = Get-EligibleIdeas -State $fixture
    Assert-True (@($result.eligible).Count -eq 5) 'Expected five eligible candidates.'
    Assert-True ($result.eligible[0].idea_id -eq 'idea-01') 'Highest score must rank first.'
}
Test-Case 'Unsupported factual finding is invalid' {
    $s=Copy-TestState $fixture; $s.research[0].findings[0].evidence_ids=@(); Assert-Invalid $s 'Fact without evidence accepted.'
}
Test-Case 'Empty research cannot be marked complete' {
    $s=Copy-TestState $fixture; $s.research[0].findings=@(); Assert-Invalid $s 'Complete research accepted without findings.'
}
Test-Case 'Competitor research cannot be omitted' {
    $s=Copy-TestState $fixture; $s.candidates[0].competitors=@(); Assert-Invalid $s 'Missing competitor research accepted.'
}
Test-Case 'Remaining risks cannot be omitted' {
    $s=Copy-TestState $fixture; $s.candidates[0].remaining_risks=@(); Assert-Invalid $s 'Unstated remaining risks accepted.'
}
Test-Case 'Dangling evidence reference is invalid' {
    $s=Copy-TestState $fixture; $s.candidates[0].supporting_evidence_ids+=@('missing-source'); Assert-Invalid $s 'Dangling citation accepted.'
}
Test-Case 'Duplicate source ID is invalid' {
    $s=Copy-TestState $fixture; $s.research[1].sources[0].id='N1'; Assert-Invalid $s 'Duplicate source accepted.'
}
Test-Case 'Unavailable source cannot support a fact' {
    $s=Copy-TestState $fixture; $s.research[2].sources[0].access='unavailable'; Assert-Invalid $s 'Inaccessible evidence accepted.'
}
Test-Case 'Non-HTTP source URL is invalid' {
    $s=Copy-TestState $fixture; $s.research[0].sources[0].url='file:///private/data'; Assert-Invalid $s 'Local file treated as public research.'
}
Test-Case 'Future publication is invalid' {
    $s=Copy-TestState $fixture; $s.research[0].sources[0].published_at=[DateTimeOffset]::UtcNow.AddDays(1).ToString('o'); Assert-Invalid $s 'Future publication accepted.'
}
Test-Case 'Future retrieval is invalid' {
    $s=Copy-TestState $fixture; $s.research[0].sources[0].retrieved_at=[DateTimeOffset]::UtcNow.AddDays(1).ToString('o'); Assert-Invalid $s 'Future retrieval accepted.'
}
Test-Case 'Undated direct sources cannot qualify demand' {
    $s=Copy-TestState $fixture; foreach($r in $s.research) { foreach($source in $r.sources) { if($source.source_type -eq 'community') { $source.published_at=$null; $source.historical=$true } } }; Assert-Rejected $s 'idea-01' 'Undated community evidence qualifies demand.'
}
Test-Case 'Historical sources cannot qualify current demand' {
    $s=Copy-TestState $fixture; foreach($r in $s.research) { foreach($source in $r.sources) { if($source.source_type -eq 'community') { $source.published_at=([DateTimeOffset]::Parse($s.config.as_of).AddDays(-60)).ToString('o'); $source.historical=$true } } }; Assert-Rejected $s 'idea-01' 'Old complaints qualify current demand.'
}
Test-Case 'Search excerpts alone cannot qualify demand' {
    $s=Copy-TestState $fixture; foreach($source in $s.research[2].sources) { $source.access='excerpt_only' }; Assert-Rejected $s 'idea-01' 'Search snippets qualify current demand.'
}
Test-Case 'Both independent demand threads must be current and direct' {
    $s=Copy-TestState $fixture; $s.research[2].sources[1].access='excerpt_only'; Assert-Rejected $s 'idea-01' 'One direct thread and one snippet qualify.'
}
Test-Case 'Syndicated duplicate threads are not independent' {
    $s=Copy-TestState $fixture; $s.research[2].sources[1].independence_key=$s.research[2].sources[0].independence_key; Assert-Rejected $s 'idea-01' 'Duplicated community thread counts twice.'
}
Test-Case 'Connections need more than one research role' {
    $s=Copy-TestState $fixture; $s.candidates[0].research_connections=@('consumers-finding'); Assert-Rejected $s 'idea-01' 'Single role connection qualifies.'
}
Test-Case 'Two debate rounds cannot qualify' {
    $s=Copy-TestState $fixture; $s.debates=@($s.debates | Where-Object { -not ($_.idea_id -eq 'idea-01' -and $_.round -eq 3) }); Assert-Rejected $s 'idea-01' 'Two rounds accepted.'
}
Test-Case 'Missing paired rebuttal cannot qualify' {
    $s=Copy-TestState $fixture; $s.debates=@($s.debates | Where-Object { -not ($_.idea_id -eq 'idea-01' -and $_.round -eq 2 -and $_.role -eq 'attacker') }); Assert-Rejected $s 'idea-01' 'Unpaired debate accepted.'
}
Test-Case 'Failed debate result cannot qualify' {
    $s=Copy-TestState $fixture; $s.debates[0].status='failed'; Assert-Rejected $s 'idea-01' 'Failed defender accepted.'
}
Test-Case 'A sixth debate round violates loop bound' {
    $s=Copy-TestState $fixture; $extra=Copy-TestState $s.debates[0]; $extra.round=6; $s.debates+=@($extra); Assert-Invalid $s 'Sixth debate round accepted.'
}
Test-Case 'Duplicate debate records are invalid' {
    $s=Copy-TestState $fixture; $s.debates+=@(Copy-TestState $s.debates[0]); Assert-Invalid $s 'Duplicate debate record accepted.'
}
Test-Case 'Unsupported defender fact is invalid' {
    $s=Copy-TestState $fixture; $s.debates[0].arguments[0].evidence_ids=@(); Assert-Invalid $s 'Uncited factual argument accepted.'
}
Test-Case 'Debate cannot consist only of uncited assumptions' {
    $s=Copy-TestState $fixture; foreach($argument in $s.debates[0].arguments) { $argument.kind='assumption'; $argument.evidence_ids=@() }; Assert-Invalid $s 'An entirely assumption-based debate response accepted.'
}
Test-Case 'Fatal flaw overrides high score' {
    $s=Copy-TestState $fixture; $s.evaluations[0].fatal_flaw=$true; Assert-Rejected $s 'idea-01' 'Fatal flaw candidate accepted.'
}
Test-Case 'Demand floor overrides weighted total' {
    $s=Copy-TestState $fixture; $s.evaluations[0].scores.customer_demand=59; Assert-Rejected $s 'idea-01' 'Weak demand accepted.'
}
Test-Case 'Rounding cannot promote a below-threshold idea' {
    $s=Copy-TestState $fixture; foreach($metric in @('customer_demand','market_opportunity','revenue_potential','competitive_advantage','feasibility','market_timing','risk')) { $s.evaluations[0].scores.$metric=69.9996 }; Assert-Rejected $s 'idea-01' 'Rounded70promoted below-threshold score.'
}
Test-Case 'Missing scoring criterion is invalid' {
    $s=Copy-TestState $fixture; $s.evaluations[0].scores.PSObject.Properties.Remove('risk'); Assert-Invalid $s 'Missing risk score accepted.'
}
Test-Case 'Scores outside range are invalid' {
    $s=Copy-TestState $fixture; $s.evaluations[0].scores.risk=101; Assert-Invalid $s 'Out of range score accepted.'
}
Test-Case 'Financial estimate requires assumptions' {
    $s=Copy-TestState $fixture; $s.candidates[0].finances.startup_cost.assumptions=@(); Assert-Rejected $s 'idea-01' 'Unexplained financial estimate accepted.'
}
Test-Case 'Negative cost estimate is invalid' {
    $s=Copy-TestState $fixture; $s.candidates[0].finances.startup_cost.low=-1; Assert-Invalid $s 'Negative startup cost accepted.'
}
Test-Case 'Startup budget constrains selection' {
    $s=Copy-TestState $fixture; $s.config.filters.startup_budget=[pscustomobject]@{amount=400; currency='USD'}; Assert-Rejected $s 'idea-01' 'Unaffordable idea qualifies.'
}
Test-Case 'Unconverted budget currency cannot qualify' {
    $s=Copy-TestState $fixture; $s.config.filters.startup_budget=[pscustomobject]@{amount=10000; currency='EUR'}; Assert-Rejected $s 'idea-01' 'Currency mismatch qualifies.'
}
Test-Case 'Plan must cover all thirty days' {
    $s=Copy-TestState $fixture; $s.candidates[0].action_plan=@($s.candidates[0].action_plan[0..2]); Assert-Rejected $s 'idea-01' 'Incomplete30day plan accepted.'
}
Test-Case 'Replenishment is bounded' {
    $s=Copy-TestState $fixture; $s.replenishments=3; Assert-Invalid $s 'Third replenishment accepted.'
}
Test-Case 'Missing debate loop bounds are invalid' {
    $s=Copy-TestState $fixture; $s.config.PSObject.Properties.Remove('max_rounds'); Assert-Invalid $s 'Missing maximum debate bound accepted.'
}
Test-Case 'Fractional debate loop bounds are invalid' {
    $s=Copy-TestState $fixture; $s.config.max_rounds=4.5; Assert-Invalid $s 'Fractional debate bound accepted.'
}
Test-Case 'Fractional replenishment count is invalid' {
    $s=Copy-TestState $fixture; $s.replenishments=0.5; Assert-Invalid $s 'Fractional replenishment count accepted.'
}
Test-Case 'Initial generation cannot omit required breadth' {
    $s=Copy-TestState $fixture; $s.candidates=@($s.candidates[0..8]); Assert-Invalid $s 'Only nine initial candidates accepted.'
}
Test-Case 'Sequential mode remains disclosed' {
    $s=Copy-TestState $fixture; $s.capabilities.agent_mode='sequential_roles'; $s.capabilities.limitations=@('No independent agents available; sequential role emulation.'); $result=Validate-State -State $s; Assert-True $result.valid ($result.errors -join '; ')
}

New-Item -ItemType Directory -Path $ArtifactsPath -Force | Out-Null
$runPath=Join-Path $ArtifactsPath ('synthetic-' + [Guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $runPath | Out-Null
Test-Case 'Complete run produces exactly three ranked ideas' {
    Write-JsonAtomic -Path (Join-Path $runPath 'state.json') -Value $fixture
    $result=Complete-Run -RunPath $runPath
    Assert-True ($result.exit_code -eq 0) ('Finalize failed: ' + ($result | ConvertTo-Json -Depth 8))
    $final=Get-Content -LiteralPath (Join-Path $runPath 'final.json') -Raw | ConvertFrom-Json
    Assert-True (@($final.ideas).Count -eq 3) 'Final artifact does not contain exactly three ideas.'
    Assert-True $final.test_fixture 'Final artifact lost synthetic marker.'
    $report=Get-Content -LiteralPath (Join-Path $runPath 'report.md') -Raw
    Assert-True ($report -match 'SYNTHETIC TEST FIXTURE') 'Report lost synthetic marker.'
    Assert-True ($report -match 'https://fixture.invalid/C1') 'Report lost source links.'
}
Test-Case 'Quality shortage never pads to three' {
    $s=Copy-TestState $fixture; foreach($evaluation in $s.evaluations) { if($evaluation.idea_id -ne 'idea-01' -and $evaluation.idea_id -ne 'idea-02') { $evaluation.fatal_flaw=$true } }
    Write-JsonAtomic -Path (Join-Path $runPath 'state.json') -Value $s
    $result=Complete-Run -RunPath $runPath
    Assert-True ($result.exit_code -eq 2) 'Shortage must return exit code2.'
    Assert-True (Test-Path -LiteralPath (Join-Path $runPath 'shortage.json')) 'Shortage artifact missing.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $runPath 'final.json'))) 'Stale successful final artifact remains.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $runPath 'report.md'))) 'Stale successful report remains.'
}
Test-Case 'Invalid state cannot produce final result' {
    $s=Copy-TestState $fixture; $s.research[0].findings[0].evidence_ids=@()
    Write-JsonAtomic -Path (Join-Path $runPath 'state.json') -Value $s
    $result=Complete-Run -RunPath $runPath
    Assert-True ($result.exit_code -eq 1) 'Invalid state must return exit code1.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $runPath 'final.json'))) 'Invalid state wrote final ideas.'
}
Test-Case 'Finalization waits for every retained shortlist debate' {
    $s=Copy-TestState $fixture; $s.debates=@($s.debates | Where-Object { -not ($_.idea_id -eq 'idea-05' -and $_.round -eq 3) })
    Write-JsonAtomic -Path (Join-Path $runPath 'state.json') -Value $s
    $result=Complete-Run -RunPath $runPath
    Assert-True ($result.exit_code -eq 2) 'Enough other qualifying ideas bypassed unfinished shortlisted debate.'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $runPath 'final.json'))) 'Unfinished shortlist wrote final result.'
}
Test-Case 'Initialization preserves optional filters' {
    $initPath=Join-Path $ArtifactsPath ('init-' + [Guid]::NewGuid().ToString('N'))
    $shell = (Get-Process -Id $PID).Path
    & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\scripts\pipeline.ps1') -Command init -RunPath $initPath -AsOf $fixture.config.as_of -Country AE -Industry software -Budget 2500 -Currency AED -BusinessType service | Out-Null
    Assert-True ($LASTEXITCODE -eq 0) 'Init CLI failed.'
    $state=Read-State -RunPath $initPath
    Assert-True ($state.config.filters.country -eq 'AE') 'Country filter lost.'
    Assert-True ($state.config.filters.startup_budget.amount -eq 2500) 'Budget lost.'
    Assert-True ($state.config.filters.startup_budget.currency -eq 'AED') 'Currency lost.'
    & $shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot '..\scripts\pipeline.ps1') -Command init -RunPath $initPath | Out-Null
    Assert-True ($LASTEXITCODE -ne 0) 'Init overwrote existing state.'
}

$summary=[pscustomobject]@{test_fixture=$true; executed_at=[DateTimeOffset]::UtcNow.ToString('o'); total=$testResults.Count; passed=@($testResults | Where-Object passed).Count; failed=@($testResults | Where-Object { -not $_.passed }).Count; tests=@($testResults); artifact_run=$runPath}
Write-JsonAtomic -Path (Join-Path $ArtifactsPath 'test-results.json') -Value $summary
Write-Output ('Tests: ' + $summary.passed + '/' + $summary.total + ' passed.')
if ($summary.failed -gt 0) { exit 1 }
exit 0
