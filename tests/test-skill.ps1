param([string]$SkillPath = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
# Dependency-free checks for this skill's simple YAML and local resource links.
$skill = Get-Content -LiteralPath (Join-Path $SkillPath 'SKILL.md') -Raw -Encoding UTF8
if ($skill -notmatch '\A---\r?\n(?<front>[\s\S]*?)\r?\n---\r?\n') { throw 'Missing valid frontmatter boundary.' }
$front = $Matches.front
if ($front -notmatch '(?m)^name: (?<name>[a-z0-9]+(?:-[a-z0-9]+)*)\r?$') { throw 'Invalid skill name.' }
$name = $Matches.name
if ($name.Length -ge 64 -or (Split-Path -Leaf $SkillPath) -ne $name) { throw 'Skill directory/name mismatch.' }
if ($front -notmatch '(?m)^description: (?<description>[^\r\n]+)\r?$') { throw 'Missing discovery description.' }
$description = $Matches.description
if ($description.Length -gt 1024 -or $description -match '[<>]' -or $description -notmatch 'Use when') { throw 'Invalid discovery description.' }
if (@(($front -split '\r?\n') | Where-Object { $_ -notmatch '^(name|description): ' }).Count) { throw 'Unexpected frontmatter for this skill.' }
$yaml = Get-Content -LiteralPath (Join-Path $SkillPath 'agents\openai.yaml') -Raw -Encoding UTF8
if ($yaml -notmatch '(?m)^  default_prompt: "[^\r\n]*\$ai-business-intelligence[^\r\n]*"\r?$') { throw 'UI prompt must invoke the skill.' }
if ($yaml -notmatch '(?m)^  short_description: "(?<short>[^\r\n"]*)"\r?$') { throw 'Missing UI description.' }
if ($Matches.short.Length -lt 25 -or $Matches.short.Length -gt 64) { throw 'UI description outside25..64 characters.' }
$documents = @((Join-Path $SkillPath 'SKILL.md')) + @(Get-ChildItem -LiteralPath (Join-Path $SkillPath 'references') -Filter '*.md' -File | ForEach-Object FullName)
foreach ($document in $documents) {
    $text = Get-Content -LiteralPath $document -Raw -Encoding UTF8
    foreach ($match in [regex]::Matches($text,'\]\(([^)]+\.md)\)')) {
        $relative = $match.Groups[1].Value
        if ($relative -match '^[a-z]+://' ) { continue }
        $target = Join-Path (Split-Path -Parent $document) $relative
        if (-not (Test-Path -LiteralPath $target -PathType Leaf)) { throw "Missing referenced resource: $relative" }
    }
    if ($text -match '(?m)^\s*\[TODO:[^\n]*\]\s*$') { throw "Unfinished scaffold in $document" }
}
foreach ($scriptFile in @(Get-ChildItem -LiteralPath $SkillPath -Filter '*.ps1' -Recurse -File)) {
    $tokens=$null; $parseErrors=$null
    [System.Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName,[ref]$tokens,[ref]$parseErrors) | Out-Null
    if ($parseErrors.Count) { throw ($parseErrors.Message -join '; ') }
}
Write-Output 'PASS skill discovery metadata, resource links, and PowerShell syntax.'
