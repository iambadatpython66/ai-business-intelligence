param(
    [ValidateSet('init','validate','finalize')][string]$Command,
    [string]$RunPath,
    [string]$AsOf,
    [string]$Country,
    [string]$Industry,
    [Nullable[decimal]]$Budget,
    [string]$Currency = 'USD',
    [string]$BusinessType
)

# No network calls or model calls: Codex orchestrates the six roles. This helper
# validates the preserved artifacts, not the truth or relevance of a citation.
$script:Weights = [ordered]@{
    customer_demand=20; market_opportunity=15; revenue_potential=15
    competitive_advantage=15; feasibility=15; market_timing=10; risk=10
}

function Write-JsonAtomic {
    param([Parameter(Mandatory=$true)][string]$Path,[Parameter(Mandatory=$true)]$Value)
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($Path))
    if (-not (Test-Path -LiteralPath $parent)) { [IO.Directory]::CreateDirectory($parent) | Out-Null }
    $temporary = Join-Path $parent ('.json-' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $json = ConvertTo-Json -InputObject $Value -Depth 100
        [IO.File]::WriteAllText($temporary,$json,(New-Object Text.UTF8Encoding($false)))
        if ([IO.File]::Exists($Path)) { [IO.File]::Replace($temporary,$Path,[NullString]::Value) }
        else { [IO.File]::Move($temporary,$Path) }
    } finally { if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) } }
}

function Read-State {
    param([Parameter(Mandatory=$true)][string]$RunPath)
    $path = Join-Path $RunPath 'state.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "No state.json at $RunPath" }
    return Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Convert-UtcTimestamp {
    param($Value)
    if ($Value -isnot [string] -or $Value -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$') { return $null }
    $parsed = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse($Value,[Globalization.CultureInfo]::InvariantCulture,[Globalization.DateTimeStyles]::None,[ref]$parsed)) { return $null }
    return $parsed.ToUniversalTime()
}

function Test-PublicUrl {
    param($Value)
    if ($Value -isnot [string]) { return $false }
    $uri = $null
    if (-not [Uri]::TryCreate($Value,[UriKind]::Absolute,[ref]$uri)) { return $false }
    return ($uri.Scheme -in @('http','https') -and $uri.Host -and -not $uri.UserInfo)
}

function Test-Nonblank { param($Value) return ($Value -is [string] -and -not [string]::IsNullOrWhiteSpace($Value)) }
function Test-Number {
    param($Value)
    if ($null -eq $Value -or $Value -is [bool] -or $Value -is [string]) { return $false }
    try { $number=[double]$Value; return (-not [double]::IsNaN($number) -and -not [double]::IsInfinity($number)) } catch { return $false }
}
function Get-StateIndex {
    param($State)
    $sources=@{}; $sourceRoles=@{}; $findings=@{}; $findingRoles=@{}
    foreach ($report in @($State.research)) {
        foreach ($source in @($report.sources)) { if ($source.id) { $sources[$source.id]=$source; $sourceRoles[$source.id]=$report.role } }
        foreach ($finding in @($report.findings)) { if ($finding.id) { $findings[$finding.id]=$finding; $findingRoles[$finding.id]=$report.role } }
    }
    return @{sources=$sources;source_roles=$sourceRoles;findings=$findings;finding_roles=$findingRoles}
}
function Test-EvidenceReferences {
    param($Ids,$Index,[string]$Location,$Errors,[switch]$Required)
    $references=@($Ids)
    if ($Required -and ($references.Count -eq 0 -or $null -eq $references[0])) { $Errors.Add("${Location}: evidence_ids must contain a source") | Out-Null }
    foreach ($id in $references) {
        if (-not (Test-Nonblank $id) -or -not $Index.sources.ContainsKey($id)) { $Errors.Add("${Location}: unknown evidence source '$id'") | Out-Null }
        elseif ($Index.sources[$id].access -eq 'unavailable') { $Errors.Add("${Location}: unavailable source '$id' cannot support a claim") | Out-Null }
    }
}
function Test-Claim {
    param($Claim,$Index,[string]$Location,$Errors)
    if (-not (Test-Nonblank $Claim.claim) -and -not (Test-Nonblank $Claim.text)) { $Errors.Add("${Location}: claim/text is required") | Out-Null }
    if ($Claim.kind -notin @('fact','estimate','assumption')) { $Errors.Add("${Location}: kind must be fact, estimate or assumption") | Out-Null }
    Test-EvidenceReferences -Ids $Claim.evidence_ids -Index $Index -Location $Location -Errors $Errors -Required:($Claim.kind -eq 'fact')
}
function Test-FinancialRange {
    param($Range,$Index,[string]$Location,$Errors)
    if (-not (Test-Number $Range.low) -or -not (Test-Number $Range.high)) { $Errors.Add("${Location}: low/high must be finite numbers") | Out-Null }
    elseif ($Range.low -lt 0 -or $Range.high -lt $Range.low) { $Errors.Add("${Location}: expected 0 <= low <= high") | Out-Null }
    if ($Range.kind -ne 'estimate') { $Errors.Add("${Location}: financial forecasts must be explicitly labeled estimate") | Out-Null }
    if (-not (Test-Nonblank $Range.basis)) { $Errors.Add("${Location}: basis/formula is required") | Out-Null }
    if (@($Range.assumptions).Count -eq 0) { $Errors.Add("${Location}: explicit assumptions are required") | Out-Null }
    foreach ($assumption in @($Range.assumptions)) { if (-not(Test-Nonblank $assumption)) { $Errors.Add("${Location}: assumptions must be nonblank strings") | Out-Null } }
    Test-EvidenceReferences -Ids $Range.evidence_ids -Index $Index -Location $Location -Errors $Errors
}

function Initialize-Run {
    param([Parameter(Mandatory=$true)][string]$RunPath,[string]$AsOf,[string]$Country,[string]$Industry,[Nullable[decimal]]$Budget,[string]$Currency='USD',[string]$BusinessType)
    $path=Join-Path $RunPath 'state.json'
    if (Test-Path -LiteralPath $path) { throw 'Refusing to overwrite an existing state.json; use a new run directory.' }
    if (-not $AsOf) { $AsOf=[DateTimeOffset]::UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ") }
    $anchor=Convert-UtcTimestamp $AsOf
    if ($null -eq $anchor) { throw 'AsOf must be an ISO timestamp with timezone.' }
    if ($anchor -gt [DateTimeOffset]::UtcNow.AddMinutes(1)) { throw 'AsOf cannot be in the future.' }
    if ($null -ne $Budget -and $Budget -lt 0) { throw 'Budget must be nonnegative.' }
    if ($Currency -notmatch '^[A-Z]{3}$') { throw 'Currency must be an uppercase three-letter code.' }
    $budgetValue=$null
    if ($null -ne $Budget) { $budgetValue=[ordered]@{amount=$Budget;currency=$Currency} }
    $state=[ordered]@{
        schema_version=1
        config=[ordered]@{
            run_id=[Guid]::NewGuid().ToString('N');as_of=$anchor.ToString("yyyy-MM-ddTHH:mm:ssZ")
            window_days=30;priority_days=7
            filters=[ordered]@{country=$Country;industry=$Industry;business_type=$BusinessType;startup_budget=$budgetValue}
            quality_threshold=70;min_rounds=3;max_rounds=5;max_replenishments=2
        }
        capabilities=[ordered]@{agent_mode='sequential_roles';research_tools=@();limitations=@('Capability discovery has not been recorded yet.')}
        research=@();candidates=@();debates=@();evaluations=@();replenishments=0
    }
    Write-JsonAtomic -Path $path -Value $state
    foreach ($dir in @('research','candidates','debates','raw')) { [IO.Directory]::CreateDirectory((Join-Path $RunPath $dir)) | Out-Null }
    return [pscustomobject]@{status='initialized';run_path=[IO.Path]::GetFullPath($RunPath);state=$state}
}

function Get-WeightedScore {
    param([Parameter(Mandatory=$true)]$Scores)
    $total=0.0
    foreach ($metric in $script:Weights.Keys) {
        $value=$Scores.$metric
        if (-not(Test-Number $value) -or $value -lt 0 -or $value -gt 100) { throw "Invalid or missing score: $metric" }
        $total += ([double]$value * $script:Weights[$metric] / 100.0)
    }
    # Keep full precision for thresholds and ranking; round only the display.
    return $total
}

function Validate-State {
    param([Parameter(Mandatory=$true)]$State)
    $errors=New-Object 'System.Collections.Generic.List[string]'
    if ($State.schema_version -ne 1) { $errors.Add('schema_version must be 1') | Out-Null }
    foreach ($field in @('window_days','priority_days','min_rounds','max_rounds','max_replenishments')) {
        $value=$State.config.$field
        if (-not(Test-Number $value) -or [int]$value -ne $value) { $errors.Add("config.$field must be an integer") | Out-Null }
    }
    if (-not (Test-Nonblank $State.config.run_id)) { $errors.Add('config.run_id is required') | Out-Null }
    $anchor=Convert-UtcTimestamp $State.config.as_of
    if ($null -eq $anchor) { $errors.Add('config.as_of must be an ISO timestamp with timezone') | Out-Null }
    elseif ($anchor -gt [DateTimeOffset]::UtcNow.AddMinutes(1)) { $errors.Add('config.as_of cannot be in the future') | Out-Null }
    if (-not(Test-Number $State.config.window_days) -or $State.config.window_days -lt 1) { $errors.Add('window_days must be positive') | Out-Null }
    if (-not(Test-Number $State.config.priority_days) -or $State.config.priority_days -lt 1 -or $State.config.priority_days -gt $State.config.window_days) { $errors.Add('priority_days must be within the research window') | Out-Null }
    if ($State.config.min_rounds -lt 3 -or $State.config.max_rounds -gt 5 -or $State.config.min_rounds -gt $State.config.max_rounds) { $errors.Add('Debate bounds must satisfy 3 <= min_rounds <= max_rounds <= 5') | Out-Null }
    if (-not(Test-Number $State.config.quality_threshold) -or $State.config.quality_threshold -lt 70 -or $State.config.quality_threshold -gt 100) { $errors.Add('quality_threshold must be 70..100') | Out-Null }
    if ($State.config.max_replenishments -lt 0 -or $State.config.max_replenishments -gt 2) { $errors.Add('max_replenishments must be 0..2') | Out-Null }
    if (-not(Test-Number $State.replenishments) -or $State.replenishments -lt 0 -or $State.replenishments -gt $State.config.max_replenishments -or [int]$State.replenishments -ne $State.replenishments) { $errors.Add('replenishments exceeds its integer bound') | Out-Null }
    if ($State.capabilities.agent_mode -notin @('parallel_independent','sequential_independent','sequential_roles')) { $errors.Add('Unknown agent_mode') | Out-Null }
    if ($State.capabilities.agent_mode -eq 'sequential_roles' -and @($State.capabilities.limitations).Count -eq 0) { $errors.Add('Sequential role emulation must disclose the lack of independent agents') | Out-Null }
    $budgetFilter=$State.config.filters.startup_budget
    if ($null -ne $budgetFilter -and (-not(Test-Number $budgetFilter.amount) -or $budgetFilter.amount -lt 0 -or $budgetFilter.currency -notmatch '^[A-Z]{3}$')) { $errors.Add('Invalid startup_budget amount or currency') | Out-Null }
    $seenSources=@{};$seenFindings=@{};$seenRoles=@{};$seenCandidates=@{};$seenDebates=@{};$seenEvaluations=@{}
    $candidateCount=@($State.candidates).Count
    if ($candidateCount -gt 0 -and ($candidateCount -lt 10 -or $candidateCount -gt (15+5*[int]$State.replenishments))) { $errors.Add('Candidate breadth must be initial 10..15 plus at most five per replenishment') | Out-Null }
    $index=Get-StateIndex $State
    foreach ($report in @($State.research)) {
        if ($report.role -notin @('news','markets','consumers') -or $seenRoles.ContainsKey([string]$report.role)) { $errors.Add("Invalid or duplicate research role '$($report.role)'") | Out-Null }
        else { $seenRoles[$report.role]=$true }
        if ($report.status -notin @('complete','partial','failed')) { $errors.Add("Research $($report.role): invalid status") | Out-Null }
        if ($report.status -eq 'failed' -and @($report.failures).Count -eq 0) { $errors.Add("Research $($report.role): failed status must preserve failures") | Out-Null }
        if ($report.status -eq 'complete' -and (@($report.findings).Count -eq 0 -or @($report.sources | Where-Object { $_.access -ne 'unavailable' }).Count -eq 0)) { $errors.Add("Research $($report.role): complete status requires usable sources and findings") | Out-Null }
        foreach ($source in @($report.sources)) {
            $location="Source $($source.id)"
            if (-not(Test-Nonblank $source.id) -or $seenSources.ContainsKey([string]$source.id)) { $errors.Add("${location}: invalid/duplicate id") | Out-Null }
            else { $seenSources[$source.id]=$true }
            if (-not(Test-PublicUrl $source.url)) { $errors.Add("${location}: URL must be public HTTP(S) without credentials") | Out-Null }
            foreach ($field in @('title','publisher','independence_key')) { if (-not(Test-Nonblank $source.$field)) { $errors.Add("${location}: $field is required") | Out-Null } }
            if ($source.source_type -notin @('primary','news','community','market_data','competitor')) { $errors.Add("${location}: invalid source_type") | Out-Null }
            if ($source.access -notin @('direct','excerpt_only','unavailable')) { $errors.Add("${location}: invalid access") | Out-Null }
            if ($source.access -ne 'unavailable' -and -not(Test-Nonblank $source.excerpt)) { $errors.Add("${location}: exact supporting excerpt is required") | Out-Null }
            if ($source.historical -isnot [bool]) { $errors.Add("${location}: historical must be Boolean") | Out-Null }
            $retrieved=Convert-UtcTimestamp $source.retrieved_at
            if ($null -eq $retrieved) { $errors.Add("${location}: retrieved_at needs an ISO timestamp with timezone") | Out-Null }
            elseif ($retrieved -gt [DateTimeOffset]::UtcNow.AddMinutes(1)) { $errors.Add("${location}: retrieval timestamp is in the future") | Out-Null }
            if ($null -ne $source.published_at) {
                $published=Convert-UtcTimestamp $source.published_at
                if ($null -eq $published) { $errors.Add("${location}: published_at needs an ISO timestamp or null") | Out-Null }
                elseif ($null -ne $anchor) {
                    if ($published -gt $anchor) { $errors.Add("${location}: publication is after research as_of") | Out-Null }
                    if ($null -ne $retrieved -and $published -gt $retrieved) { $errors.Add("${location}: publication is after retrieval") | Out-Null }
                    if ($published -lt $anchor.AddDays(-[double]$State.config.window_days) -and -not $source.historical) { $errors.Add("${location}: stale publication must be marked historical") | Out-Null }
                }
            } elseif (-not $source.historical) { $errors.Add("${location}: an undated source must be historical; it cannot prove current demand") | Out-Null }
        }
        foreach ($finding in @($report.findings)) {
            if (-not(Test-Nonblank $finding.id) -or $seenFindings.ContainsKey([string]$finding.id)) { $errors.Add("Finding $($finding.id): invalid/duplicate id") | Out-Null }
            else { $seenFindings[$finding.id]=$true }
            Test-Claim $finding $index "Finding $($finding.id)" $errors
        }
    }
    foreach ($idea in @($State.candidates)) {
        $location="Idea $($idea.id)"
        if (-not(Test-Nonblank $idea.id) -or $seenCandidates.ContainsKey([string]$idea.id)) { $errors.Add("${location}: invalid/duplicate id") | Out-Null }
        else { $seenCandidates[$idea.id]=$true }
        foreach ($field in @('name','overview','problem','target_customers','solution','revenue_model')) { if (-not(Test-Nonblank $idea.$field)) { $errors.Add("${location}: $field is required") | Out-Null } }
        if ($idea.startup_complexity -notin @('low','medium','high')) { $errors.Add("${location}: invalid startup_complexity") | Out-Null }
        if ($idea.shortlisted -isnot [bool]) { $errors.Add("${location}: shortlisted must be Boolean") | Out-Null }
        Test-EvidenceReferences $idea.supporting_evidence_ids $index "${location} supporting evidence" $errors -Required
        foreach ($id in @($idea.research_connections)) { if (-not(Test-Nonblank $id) -or -not $index.findings.ContainsKey($id)) { $errors.Add("${location}: unknown research connection '$id'") | Out-Null } }
        Test-Claim $idea.market_opportunity $index "${location} market opportunity" $errors
        if (@($idea.competitors).Count -eq 0) { $errors.Add("${location}: at least one researched competitor or alternative is required") | Out-Null }
        if (@($idea.remaining_risks).Count -eq 0) { $errors.Add("${location}: remaining risks must be explicit") | Out-Null }
        foreach ($risk in @($idea.remaining_risks)) { if (-not(Test-Nonblank $risk)) { $errors.Add("${location}: risks must be nonblank strings") | Out-Null } }
        foreach ($competitor in @($idea.competitors)) {
            if (-not(Test-Nonblank $competitor.name) -or -not(Test-PublicUrl $competitor.url)) { $errors.Add("${location}: competitors require names and public URLs") | Out-Null }
            Test-EvidenceReferences $competitor.evidence_ids $index "${location} competitor $($competitor.name)" $errors -Required
        }
        if ($idea.finances.currency -notmatch '^[A-Z]{3}$') { $errors.Add("${location}: financial currency must be a three-letter uppercase code") | Out-Null }
        Test-FinancialRange $idea.finances.startup_cost $index "${location} startup_cost" $errors
        Test-FinancialRange $idea.finances.monthly_revenue $index "${location} monthly_revenue" $errors
        foreach ($step in @($idea.action_plan)) {
            if (-not(Test-Nonblank $step.days) -or -not(Test-Nonblank $step.action) -or -not(Test-Nonblank $step.success_metric)) { $errors.Add("${location}: action_plan entries require days, action and success_metric") | Out-Null }
        }
    }
    foreach ($debate in @($State.debates)) {
        $key="$($debate.idea_id):$($debate.round):$($debate.role)"
        if (-not $seenCandidates.ContainsKey([string]$debate.idea_id)) { $errors.Add("Debate ${key}: unknown idea") | Out-Null }
        if ($seenDebates.ContainsKey($key)) { $errors.Add("Debate ${key}: duplicate role/round") | Out-Null } else { $seenDebates[$key]=$true }
        if (-not(Test-Number $debate.round) -or $debate.round -lt 1 -or $debate.round -gt $State.config.max_rounds -or [int]$debate.round -ne $debate.round) { $errors.Add("Debate ${key}: invalid round") | Out-Null }
        if ($debate.role -notin @('defender','attacker') -or $debate.status -notin @('complete','failed')) { $errors.Add("Debate ${key}: invalid role/status") | Out-Null }
        if ($debate.status -eq 'complete') {
            if (@($debate.arguments).Count -eq 0 -or -not(Test-Nonblank $debate.strongest_argument)) { $errors.Add("Debate ${key}: complete records need arguments and strongest_argument") | Out-Null }
            foreach ($argument in @($debate.arguments)) { Test-Claim $argument $index "Debate $key" $errors }
            $supported=@($debate.arguments | Where-Object {
                $argument=$_
                $accessible=@($argument.evidence_ids | Where-Object { $index.sources.ContainsKey($_) -and $index.sources[$_].access -ne 'unavailable' })
                $argument.kind -in @('fact','estimate') -and $accessible.Count -gt 0
            })
            if ($supported.Count -eq 0) { $errors.Add("Debate ${key}: at least one fact or estimate argument needs accessible evidence; assumptions alone are insufficient") | Out-Null }
        }
    }
    foreach ($evaluation in @($State.evaluations)) {
        $location="Evaluation $($evaluation.idea_id)"
        if (-not $seenCandidates.ContainsKey([string]$evaluation.idea_id)) { $errors.Add("${location}: unknown idea") | Out-Null }
        if ($seenEvaluations.ContainsKey([string]$evaluation.idea_id)) { $errors.Add("${location}: duplicate evaluation") | Out-Null } else { $seenEvaluations[[string]$evaluation.idea_id]=$true }
        try { $null=Get-WeightedScore $evaluation.scores } catch { $errors.Add("${location}: $($_.Exception.Message)") | Out-Null }
        foreach ($metric in $script:Weights.Keys) {
            if (-not(Test-Nonblank $evaluation.rationale.$metric.text)) { $errors.Add("${location}: rationale for $metric is required") | Out-Null }
            Test-EvidenceReferences $evaluation.rationale.$metric.evidence_ids $index "${location} $metric" $errors -Required
        }
        if ($evaluation.fatal_flaw -isnot [bool]) { $errors.Add("${location}: fatal_flaw must be Boolean") | Out-Null }
        if (-not(Test-Nonblank $evaluation.verdict)) { $errors.Add("${location}: verdict is required") | Out-Null }
    }
    return [pscustomobject]@{valid=($errors.Count -eq 0);errors=@($errors.ToArray())}
}

function Get-EligibleIdeas {
    param([Parameter(Mandatory=$true)]$State)
    $index=Get-StateIndex $State
    $eligible=New-Object 'System.Collections.Generic.List[object]'
    $rejected=New-Object 'System.Collections.Generic.List[object]'
    $anchor=Convert-UtcTimestamp $State.config.as_of
    foreach ($idea in @($State.candidates | Where-Object {$_.shortlisted})) {
        $reasons=New-Object 'System.Collections.Generic.List[string]'
        $evaluations=@($State.evaluations | Where-Object {$_.idea_id -eq $idea.id})
        $evaluation=$evaluations | Select-Object -First 1
        $score=$null
        Test-FinancialRange $idea.finances.startup_cost $index "Idea $($idea.id) startup_cost" $reasons
        Test-FinancialRange $idea.finances.monthly_revenue $index "Idea $($idea.id) monthly_revenue" $reasons
        if (@($idea.competitors).Count -eq 0) { $reasons.Add('At least one verified competitor or substitute is required') | Out-Null }
        if ($evaluations.Count -ne 1) { $reasons.Add('Exactly one complete evaluation is required') | Out-Null }
        else {
            try { $score=Get-WeightedScore $evaluation.scores } catch { $reasons.Add($_.Exception.Message) | Out-Null }
            if ($null -ne $score -and $score -lt $State.config.quality_threshold) { $reasons.Add('Weighted score below quality threshold') | Out-Null }
            if ($evaluation.scores.customer_demand -lt 60) { $reasons.Add('Customer demand score below 60') | Out-Null }
            if ($evaluation.scores.feasibility -lt 60) { $reasons.Add('Feasibility score below 60') | Out-Null }
            if ($evaluation.fatal_flaw) { $reasons.Add('Unresolved fatal flaw') | Out-Null }
        }
        $sources=@($idea.supporting_evidence_ids | ForEach-Object { if ($index.sources.ContainsKey($_)) { $index.sources[$_] } })
        $independent=@($sources | Where-Object {$_.access -ne 'unavailable'} | Select-Object -ExpandProperty independence_key -Unique)
        if ($independent.Count -lt 3) { $reasons.Add('Fewer than three independent evidence sources') | Out-Null }
        $communities=@($sources | Where-Object {$_.source_type -eq 'community' -and $_.access -ne 'unavailable'} | Select-Object -ExpandProperty independence_key -Unique)
        if ($communities.Count -lt 2) { $reasons.Add('Fewer than two independent customer/community threads') | Out-Null }
        $fresh=@($sources | Where-Object {
            $published=Convert-UtcTimestamp $_.published_at
            $_.source_type -eq 'community' -and $_.access -eq 'direct' -and -not $_.historical -and $null -ne $published -and $null -ne $anchor -and $published -ge $anchor.AddDays(-[double]$State.config.window_days) -and $published -le $anchor
        })
        $freshKeys=@($fresh | Select-Object -ExpandProperty independence_key -Unique)
        if ($freshKeys.Count -lt 2) { $reasons.Add('Two independent direct, dated community demand sources in the research window are required') | Out-Null }
        $roles=@($idea.research_connections | ForEach-Object { if ($index.finding_roles.ContainsKey($_)) { $index.finding_roles[$_] } } | Select-Object -Unique)
        if ($roles.Count -lt 2) { $reasons.Add('Fewer than two research roles connected to the idea') | Out-Null }
        $rounds=@($State.debates | Where-Object {$_.idea_id -eq $idea.id})
        $numbers=@($rounds | Select-Object -ExpandProperty round -Unique | Sort-Object)
        if ($numbers.Count -lt $State.config.min_rounds -or $numbers.Count -gt $State.config.max_rounds) { $reasons.Add('Debate needs three to five rounds') | Out-Null }
        for ($round=1;$round -le $numbers.Count;$round++) {
            foreach ($role in @('defender','attacker')) {
                $paired=@($rounds | Where-Object {$_.round -eq $round -and $_.role -eq $role -and $_.status -eq 'complete'})
                if ($paired.Count -ne 1) { $reasons.Add("Missing/duplicate complete $role record for round $round") | Out-Null }
            }
        }
        $budgetValue=$State.config.filters.startup_budget
        if ($null -ne $budgetValue) {
            if ($idea.finances.currency -ne $budgetValue.currency) { $reasons.Add('Startup budget currency differs; a sourced conversion is required') | Out-Null }
            elseif ($idea.finances.startup_cost.low -gt $budgetValue.amount) { $reasons.Add('Even the low startup cost estimate exceeds the budget') | Out-Null }
        }
        $coverage=@{}
        foreach ($step in @($idea.action_plan)) {
            if ($step.days -match '^(\d{1,2})(?:-(\d{1,2}))?$') {
                $start=[int]$Matches[1];$end=$start
                if ($Matches[2]) { $end=[int]$Matches[2] }
                if ($start -ge 1 -and $end -le 30 -and $end -ge $start) { for ($day=$start;$day -le $end;$day++) { $coverage[$day]=$true } }
                else { $reasons.Add('Action plan range must be within days 1..30') | Out-Null }
            } else { $reasons.Add('Action plan days must be inclusive ranges such as 1-7') | Out-Null }
        }
        if ($coverage.Count -ne 30) { $reasons.Add('Action plan must cover all first 30 days') | Out-Null }
        if ($reasons.Count -eq 0) { $eligible.Add([pscustomobject]@{idea_id=$idea.id;score=$score;candidate=$idea;evaluation=$evaluation}) | Out-Null }
        else { $rejected.Add([pscustomobject]@{idea_id=$idea.id;reasons=@($reasons.ToArray())}) | Out-Null }
    }
    return [pscustomobject]@{eligible=@($eligible.ToArray());rejected=@($rejected.ToArray())}
}

function Format-SourceLinks {
    param($Ids,$Index)
    $links=@($Ids | Select-Object -Unique | ForEach-Object {
        if ($Index.sources.ContainsKey($_)) {
            $source=$Index.sources[$_];$published=$source.published_at
            if (-not $published) { $published='publication date unknown'; if ($source.published_date) { $published="$($source.published_date) (calendar date only; timestamp unknown)" } }
            "[$($source.id)]($($source.url)) (published: $published; retrieved: $($source.retrieved_at); access: $($source.access))"
        }
    })
    return $links -join '; '
}

function Write-FinalReport {
    param($State,$Selected,[string]$Path)
    $index=Get-StateIndex $State
    $lines=New-Object 'System.Collections.Generic.List[string]'
    if ($State.test_fixture) { $lines.Add('SYNTHETIC TEST FIXTURE - not market research');$lines.Add('') }
    $lines.Add('# Three business opportunities');$lines.Add('')
    $lines.Add("Research as of $($State.config.as_of). Window: previous $($State.config.window_days) days, prioritizing $($State.config.priority_days) days.")
    $lines.Add("Execution mode: $($State.capabilities.agent_mode). Source validation checks preserved artifacts; it cannot establish truth or market demand.")
    $lines.Add('Facts are cited observations. Estimates are conditional projections. Assumptions require validation. A high risk score means lower risk.');$lines.Add('')
    $lines.Add('Filters: ' + (ConvertTo-Json -InputObject $State.config.filters -Compress -Depth 10));$lines.Add('')
    foreach ($limitation in @($State.capabilities.limitations)) { $lines.Add("- Limitation: $limitation") }
    foreach ($report in @($State.research)) {
        if ($report.status -ne 'complete') { $lines.Add("- Research coverage: $($report.role) is $($report.status).") }
        foreach ($gap in @($report.gaps)) { $lines.Add("- $($report.role) gap: $gap") }
        foreach ($failure in @($report.failures)) { $lines.Add('- Access/research failure ('+$report.role+'): '+(ConvertTo-Json -InputObject $failure -Compress -Depth 10)) }
    }
    $position=0
    foreach ($entry in @($Selected)) {
        $position++;$idea=$entry.candidate;$evaluation=$entry.evaluation
        $lines.Add('');$lines.Add("## $position. $($idea.name)");$lines.Add('')
        $lines.Add("**Business overview (proposal):** $($idea.overview)")
        $lines.Add("**Problem (research interpretation):** $($idea.problem)")
        $lines.Add("**Proposed solution:** $($idea.solution)")
        $lines.Add("**Target market (assumption):** $($idea.target_customers)")
        $lines.Add("**Revenue model (proposal):** $($idea.revenue_model)")
        $lines.Add("**Market opportunity ($($idea.market_opportunity.kind)):** $($idea.market_opportunity.text) " + (Format-SourceLinks $idea.market_opportunity.evidence_ids $index))
        $lines.Add("**Startup complexity (estimate):** $($idea.startup_complexity)");$lines.Add('')
        $lines.Add('**Competitors (facts requiring source review):**');$lines.Add('')
        foreach ($competitor in @($idea.competitors)) { $lines.Add("- [$($competitor.name)]($($competitor.url)): " + (Format-SourceLinks $competitor.evidence_ids $index)) }
        $lines.Add('');$lines.Add('**Market research:**');$lines.Add('')
        foreach ($findingId in @($idea.research_connections)) {
            $finding=$index.findings[$findingId]
            if ($null -ne $finding) { $lines.Add("- [$($finding.kind)] $($finding.claim) " + (Format-SourceLinks $finding.evidence_ids $index)) }
        }
        $lines.Add('');$lines.Add('**Financial estimates:**');$lines.Add('')
        foreach ($name in @('startup_cost','monthly_revenue')) {
            $range=$idea.finances.$name
            $label='Startup costs';if ($name -eq 'monthly_revenue') { $label='Monthly revenue at the stated maturity and customer assumptions' }
            $lines.Add("- $label (estimate): $($idea.finances.currency) $($range.low)-$($range.high). Basis: $($range.basis) " + (Format-SourceLinks $range.evidence_ids $index))
            foreach ($assumption in @($range.assumptions)) { $lines.Add("  - Assumption: $assumption") }
        }
        $lines.Add('');$lines.Add('**Debate:**');$lines.Add('')
        foreach ($role in @('defender','attacker')) {
            $debate=$State.debates | Where-Object {$_.idea_id -eq $idea.id -and $_.role -eq $role -and $_.status -eq 'complete'} | Sort-Object round -Descending | Select-Object -First 1
            $label='Defender strongest argument';if ($role -eq 'attacker') { $label='Attacker strongest criticism' }
            $lines.Add("$label (round $($debate.round)): $($debate.strongest_argument)")
            foreach ($argument in @($debate.arguments)) { $lines.Add("- [$($argument.kind)] $($argument.claim) " + (Format-SourceLinks $argument.evidence_ids $index)) }
            foreach ($question in @($debate.unresolved_questions)) { $lines.Add("- Open question: $question") }
            foreach ($criterion in @($debate.kill_criteria)) { $lines.Add("- Kill criterion: $criterion") }
            $lines.Add('')
        }
        $lines.Add('**Remaining risks:**');$lines.Add('')
        foreach ($risk in @($idea.remaining_risks)) { $lines.Add("- $risk") }
        $lines.Add('');$lines.Add('**First 30 days:**');$lines.Add('')
        foreach ($step in @($idea.action_plan)) { $lines.Add("- Days $($step.days): $($step.action). Success metric: $($step.success_metric)") }
        $lines.Add('');$lines.Add('| Criterion | Weight | Score | Evidence and rationale |');$lines.Add('| --- | ---: | ---: | --- |')
        foreach ($metric in $script:Weights.Keys) {
            $rationale=$evaluation.rationale.$metric
            $text=([string]$rationale.text).Replace('|','\|').Replace("`r",' ').Replace("`n",' ')
            $lines.Add("| $metric | $($script:Weights[$metric])% | $($evaluation.scores.$metric) | $text " + (Format-SourceLinks $rationale.evidence_ids $index) + ' |')
        }
        $lines.Add('');$lines.Add("**Final score:** $([Math]::Round($entry.score,2))/100. **Verdict (evaluation):** $($evaluation.verdict)")
    }
    $lines.Add('');$lines.Add('## Preserved source ledger');$lines.Add('')
    foreach ($source in @($index.sources.Values | Sort-Object id)) {
        $lines.Add("- [$($source.id): $($source.title)]($($source.url)) - $($source.publisher); published: $($source.published_at); retrieved: $($source.retrieved_at); access: $($source.access); historical: $($source.historical); independence key: $($source.independence_key).")
        $lines.Add('  - Preserved excerpt (source text): '+$source.excerpt)
    }
    [IO.File]::WriteAllText($Path,($lines -join "`n"),(New-Object Text.UTF8Encoding($false)))
}

function Complete-Run {
    param([Parameter(Mandatory=$true)][string]$RunPath)
    # Generated outputs from an older state cannot survive a failed rerun.
    # These are exact, nonrecursive paths inside the explicitly named run.
    foreach ($generated in @('final.json','report.md','shortage.json')) {
        $generatedPath=Join-Path ([IO.Path]::GetFullPath($RunPath)) $generated
        if ([IO.File]::Exists($generatedPath)) { [IO.File]::Delete($generatedPath) }
    }
    $state=Read-State $RunPath
    $validation=Validate-State $state
    Write-JsonAtomic -Path (Join-Path $RunPath 'validation.json') -Value $validation
    if (-not $validation.valid) { return [pscustomobject]@{status='invalid';exit_code=1;errors=$validation.errors} }
    $globalReasons=New-Object 'System.Collections.Generic.List[string]'
    $roles=@($state.research | Select-Object -ExpandProperty role -Unique)
    if ($roles.Count -ne 3) { $globalReasons.Add('All three research role reports are required, including failed reports') | Out-Null }
    $count=@($state.candidates).Count
    if ($count -lt 10 -or $count -gt (15 + 5*[int]$state.replenishments)) { $globalReasons.Add('Expected initial 10..15 candidates, plus at most five per replenishment') | Out-Null }
    $shortlistCount=@($state.candidates | Where-Object {$_.shortlisted}).Count
    if ($shortlistCount -lt 3 -or $shortlistCount -gt (6+5*[int]$state.replenishments)) { $globalReasons.Add('Shortlist must contain initial three to six ideas, plus at most five per replenishment') | Out-Null }
    foreach ($idea in @($state.candidates | Where-Object {$_.shortlisted})) {
        $records=@($state.debates | Where-Object {$_.idea_id -eq $idea.id})
        $numbers=@($records | Select-Object -ExpandProperty round -Unique | Sort-Object)
        $incomplete=($numbers.Count -lt $state.config.min_rounds -or $numbers.Count -gt $state.config.max_rounds)
        for ($round=1;$round -le $numbers.Count;$round++) {
            foreach ($role in @('defender','attacker')) {
                $paired=@($records | Where-Object {$_.round -eq $round -and $_.role -eq $role -and $_.status -eq 'complete'})
                if ($paired.Count -ne 1) { $incomplete=$true }
            }
        }
        if ($incomplete) { $globalReasons.Add("Shortlisted idea $($idea.id) lacks three to five contiguous complete paired debate rounds. Complete its debate, or remove it from the active shortlist and preserve the audit reason.") | Out-Null }
    }
    $selection=Get-EligibleIdeas $state
    $ranked=@($selection.eligible | Sort-Object @{Expression={$_.score};Descending=$true},@{Expression={$_.evaluation.scores.customer_demand};Descending=$true},@{Expression={$_.idea_id};Descending=$false})
    if ($ranked.Count -lt 3 -or $globalReasons.Count -gt 0) {
        $shortage=[ordered]@{status='insufficient_evidence';run_id=$state.config.run_id;as_of=$state.config.as_of;eligible_count=$ranked.Count;required_count=3;replenishments_remaining=([int]$state.config.max_replenishments-[int]$state.replenishments);reasons=@($globalReasons.ToArray());rejected=$selection.rejected;test_fixture=[bool]$state.test_fixture}
        $shortage.capabilities=$state.capabilities
        $shortage.research_coverage=@($state.research | Select-Object role,status,gaps,failures)
        Write-JsonAtomic -Path (Join-Path $RunPath 'shortage.json') -Value $shortage
        return [pscustomobject]@{status='insufficient_evidence';exit_code=2;eligible_count=$ranked.Count;shortage=$shortage}
    }
    $selected=@($ranked | Select-Object -First 3)
    $final=[ordered]@{status='complete';run_id=$state.config.run_id;as_of=$state.config.as_of;config=$state.config;capabilities=$state.capabilities;ideas=$selected;research=$state.research;debates=$state.debates;rejected=$selection.rejected;test_fixture=[bool]$state.test_fixture}
    $reportPath=Join-Path $RunPath 'report.md'
    $finalPath=Join-Path $RunPath 'final.json'
    $temporaryReport=Join-Path $RunPath ('.report-'+[Guid]::NewGuid().ToString('N')+'.tmp')
    try {
        # Render first; final.json is the completion marker committed last.
        Write-FinalReport -State $state -Selected $selected -Path $temporaryReport
        [IO.File]::Move($temporaryReport,$reportPath)
        Write-JsonAtomic -Path $finalPath -Value $final
    } catch {
        foreach ($generatedPath in @($reportPath,$finalPath)) { if ([IO.File]::Exists($generatedPath)) { [IO.File]::Delete($generatedPath) } }
        throw
    } finally { if ([IO.File]::Exists($temporaryReport)) { [IO.File]::Delete($temporaryReport) } }
    return [pscustomobject]@{status='complete';exit_code=0;eligible_count=$ranked.Count;ideas=$selected;report_path=(Join-Path $RunPath 'report.md')}
}

if ($Command) {
    try {
        if (-not $RunPath) { throw 'RunPath is required.' }
        switch ($Command) {
            'init' { $result=Initialize-Run -RunPath $RunPath -AsOf $AsOf -Country $Country -Industry $Industry -Budget $Budget -Currency $Currency -BusinessType $BusinessType; $code=0 }
            'validate' { $result=Validate-State (Read-State $RunPath);Write-JsonAtomic -Path (Join-Path $RunPath 'validation.json') -Value $result;$code=0;if (-not $result.valid) {$code=1} }
            'finalize' { $result=Complete-Run $RunPath;$code=$result.exit_code }
        }
        ConvertTo-Json -InputObject $result -Depth 100
        exit $code
    } catch { Write-Error $_;exit 1 }
}
