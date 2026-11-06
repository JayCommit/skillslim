# Copy a skill directory into one host path without nesting the folder twice.
# Windows PowerShell. macOS or Linux uses scripts/install-skill.sh.
$ErrorActionPreference = 'Stop'

function Show-Usage {
  @"
Usage: install-skill.ps1 [SKILL_DIR] --host HOST [--scope user|project] [--name NAME]

Copy a skill directory into a host skill path. The destination contains the
skill's files directly (SKILL.md at the top); it does not nest <name>/<name>.

SKILL_DIR must be a directory containing SKILL.md. If omitted, the packaged
template (src/skillslim/template next to this script, otherwise the installed
skillslim template) is used only when that directory contains SKILL.md.

--host   grok | grok-bot | cursor | openai | antigravity | claude | all
--scope  project (default, current directory) or user (USERPROFILE)
--name   skill folder name. Default: frontmatter name, else the directory name.
         {{name}} in copied files is replaced with this name.

Paths, with <name> replaced by the skill folder name:
  Grok          .grok/skills/<name>/                         ~/.grok/skills/<name>/
                Invoke /<name>.
  Grok Bot      ~/.grok/skills/<name>/ on the bot computer, plus a paste-in prompt.
                Same SKILL.md. Either scope uses that user path.
  Cursor        .cursor/skills/<name>/                       ~/.cursor/skills/<name>/
                Invoke /<name>. name matches folder.
  OpenAI        .agents/skills/<name>/                       ~/.agents/skills/<name>/
                Zip upload via Plugins → Skills → Add. Codex $<name>.
  Antigravity   .agents/skills/<name>/ one level
                ~/.gemini/config/skills/<name>/
                CLI ~/.gemini/antigravity-cli/skills/<name>/
                description required. User scope writes both home paths.
  Claude        .claude/skills/<name>/                       ~/.claude/skills/<name>/
                Invoke /<name>.
"@
}

function Fail([string]$Message) {
  [Console]::Error.WriteLine("install-skill: $Message")
  exit 2
}

function Unquote-Value([string]$Raw) {
  if ($null -eq $Raw) { return '' }
  $value = $Raw.Trim()
  if ($value.Length -ge 2) {
    $quote = $value.Substring(0, 1)
    if (($quote -eq '"' -or $quote -eq "'") -and $value.Substring($value.Length - 1, 1) -eq $quote) {
      return $value.Substring(1, $value.Length - 2).Trim()
    }
  }
  return $value
}

function Get-FrontmatterValue([string]$Text, [string]$Key) {
  $lines = [regex]::Split($Text, '\r?\n')
  if ($lines.Count -lt 1 -or $lines[0] -ne '---') { return $null }
  $value = $null
  $collecting = $false
  $have = $false
  for ($i = 1; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    if ($line -eq '---') { break }
    if ($collecting) {
      if ($line -match '^[ \t]') {
        $piece = $line.Trim()
        if ($piece) {
          if ([string]::IsNullOrEmpty($value)) { $value = $piece } else { $value = "$value $piece" }
        }
        continue
      }
      $collecting = $false
    }
    if (-not $have -and $line -match "^${Key}:[ \t]*(.*)$") {
      $raw = $Matches[1].Trim()
      if ($raw -eq '|' -or $raw -eq '>' -or $raw -eq '|-' -or $raw -eq '>-' -or $raw -eq '|+' -or $raw -eq '>+') {
        $collecting = $true
        $have = $true
        $value = ''
        continue
      }
      $value = Unquote-Value $raw
      $have = $true
    }
  }
  if (-not $have -or $null -eq $value) { return $null }
  $value = Unquote-Value $value
  if ($value -eq '' -or $value -eq 'null' -or $value -eq '~') { return $null }
  return $value
}

function Test-EmptyValue($Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
  if ($Value -eq '""' -or $Value -eq "''" -or $Value -eq 'null' -or $Value -eq '~' -or $Value -eq '|' -or $Value -eq '>' -or $Value -eq '|-' -or $Value -eq '>-' -or $Value -eq '|+' -or $Value -eq '>+') {
    return $true
  }
  return $false
}

function Get-UserHome {
  if ($env:USERPROFILE) { return $env:USERPROFILE.TrimEnd('\', '/') }
  if ($env:HOME) { return $env:HOME.TrimEnd('\', '/') }
  Fail 'USERPROFILE is not set'
  return $null
}

function Resolve-InstalledTemplate {
  $candidates = @('python3.11', 'python3', 'python', 'py')
  foreach ($py in $candidates) {
    if (-not (Get-Command $py -ErrorAction SilentlyContinue)) { continue }
    $code = @'
from pathlib import Path
try:
    import skillslim
except Exception:
    raise SystemExit(1)
path = Path(skillslim.__file__).resolve().parent / "template"
skill = path / "SKILL.md"
if skill.is_file() and skill.stat().st_size > 0:
    print(path)
else:
    raise SystemExit(1)
'@
    $output = & $py -c $code 2>$null
    if ($LASTEXITCODE -eq 0 -and $output) {
      $candidate = ($output | Select-Object -Last 1).ToString().Trim()
      $skill = Join-Path $candidate 'SKILL.md'
      if ((Test-Path -LiteralPath $skill -PathType Leaf) -and ((Get-Item -LiteralPath $skill).Length -gt 0)) {
        return (Resolve-Path -LiteralPath $candidate).Path
      }
    }
  }
  return $null
}

$HostName = $null
$Scope = 'project'
$Name = $null
$SkillDir = $null
$argList = @($args)
for ($i = 0; $i -lt $argList.Count; $i++) {
  $arg = [string]$argList[$i]
  switch -Regex ($arg) {
    '^(--help|-h)$' { Show-Usage; exit 0 }
    '^--host$' {
      if ($i + 1 -ge $argList.Count) { Fail '--host requires a value' }
      $i++
      $HostName = [string]$argList[$i]
      break
    }
    '^--host=(.*)$' { $HostName = $Matches[1]; break }
    '^--scope$' {
      if ($i + 1 -ge $argList.Count) { Fail '--scope requires a value' }
      $i++
      $Scope = [string]$argList[$i]
      break
    }
    '^--scope=(.*)$' { $Scope = $Matches[1]; break }
    '^--name$' {
      if ($i + 1 -ge $argList.Count) { Fail '--name requires a value' }
      $i++
      $Name = [string]$argList[$i]
      break
    }
    '^--name=(.*)$' { $Name = $Matches[1]; break }
    '^--$' {
      if ($i + 1 -lt $argList.Count) {
        if ($SkillDir) { Fail "unexpected argument: $($argList[$i + 1])" }
        $SkillDir = [string]$argList[$i + 1]
        if ($i + 2 -lt $argList.Count) { Fail "unexpected argument: $($argList[$i + 2])" }
      }
      break
    }
    '^-' { Fail "unknown flag: $arg" }
    default {
      if ($SkillDir) { Fail "unexpected argument: $arg" }
      $SkillDir = $arg
      break
    }
  }
}

$allowedHosts = @('grok', 'grok-bot', 'cursor', 'openai', 'antigravity', 'claude', 'all')
if (-not $HostName) { Fail '--host is required (grok|grok-bot|cursor|openai|antigravity|claude|all)' }
if ($allowedHosts -cnotcontains $HostName) { Fail "unknown --host: $HostName" }
if (@('user', 'project') -cnotcontains $Scope) { Fail "unknown --scope: $Scope (use user or project)" }

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $ScriptDir
$Packaged = Join-Path $RepoRoot 'src/skillslim/template'

if (-not $SkillDir) {
  if (Test-Path -LiteralPath $Packaged -PathType Container) {
    $packagedSkill = Join-Path $Packaged 'SKILL.md'
    if ((Test-Path -LiteralPath $packagedSkill -PathType Leaf) -and ((Get-Item -LiteralPath $packagedSkill).Length -gt 0)) {
      $SkillDir = $Packaged
    } else {
      Fail "packaged template is not a valid skill (missing SKILL.md): $Packaged"
    }
  } else {
    $SkillDir = Resolve-InstalledTemplate
    if (-not $SkillDir) { Fail 'no skill directory given and the packaged template is not a valid skill with SKILL.md' }
  }
}

if ((Test-Path -LiteralPath $SkillDir -PathType Leaf) -and ((Split-Path -Leaf $SkillDir) -eq 'SKILL.md')) {
  $SkillDir = Split-Path -Parent $SkillDir
}
if (-not (Test-Path -LiteralPath $SkillDir -PathType Container)) { Fail "skill directory not found: $SkillDir" }
$SkillDir = (Resolve-Path -LiteralPath $SkillDir).Path
$entry = Join-Path $SkillDir 'SKILL.md'
if (-not (Test-Path -LiteralPath $entry -PathType Leaf) -or (Get-Item -LiteralPath $entry).Length -eq 0) {
  Fail "not a valid skill (SKILL.md is missing or empty): $SkillDir"
}

$utf8 = New-Object System.Text.UTF8Encoding $false
$originalText = [System.IO.File]::ReadAllText($entry)
$rawName = Get-FrontmatterValue $originalText 'name'
if (-not $Name) {
  if ($rawName -and ($rawName -cmatch '^[a-z0-9]+(-[a-z0-9]+)*$') -and $rawName.Length -le 64) {
    $Name = $rawName
  } else {
    $Name = Split-Path -Leaf $SkillDir
  }
}
if (-not ($Name -cmatch '^[a-z0-9]+(-[a-z0-9]+)*$') -or $Name.Length -gt 64 -or $Name.Length -lt 1) {
  Fail "name must be 1-64 lowercase letters, digits, and single hyphens: $Name"
}

$stage = Join-Path ([System.IO.Path]::GetTempPath()) ("skillslim-install-" + [guid]::NewGuid().ToString('n'))
New-Item -ItemType Directory -Path $stage | Out-Null
try {
  Get-ChildItem -Force -LiteralPath $SkillDir | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $stage -Recurse -Force
  }
  Get-ChildItem -Force -LiteralPath $stage -Recurse -File | ForEach-Object {
    $text = [System.IO.File]::ReadAllText($_.FullName)
    if ($text.Contains('{{name}}')) {
      $text = $text.Replace('{{name}}', $Name)
      [System.IO.File]::WriteAllText($_.FullName, $text, $utf8)
    }
  }

  $stagedEntry = Join-Path $stage 'SKILL.md'
  $stagedText = [System.IO.File]::ReadAllText($stagedEntry)
  $installedName = Get-FrontmatterValue $stagedText 'name'
  $installedDescription = Get-FrontmatterValue $stagedText 'description'

  $want = @{
    grok = $false
    'grok-bot' = $false
    cursor = $false
    openai = $false
    antigravity = $false
    claude = $false
  }
  if ($HostName -ceq 'all') {
    foreach ($key in @($want.Keys)) { $want[$key] = $true }
  } else {
    $want[$HostName] = $true
  }

  if ($want['cursor'] -and $installedName -and ($installedName -cne $Name)) {
    Fail "Cursor requires the frontmatter name to match the folder ($Name); SKILL.md name is $installedName"
  }
  if ($want['antigravity'] -and (Test-EmptyValue $installedDescription)) {
    Fail 'Antigravity requires a non-empty description in SKILL.md'
  }

  $projectRoot = (Get-Location).Path.TrimEnd('\', '/')
  $userRoot = $null
  if ($Scope -ceq 'user' -or $want['grok-bot']) { $userRoot = Get-UserHome }

  function Join-SkillPath([string]$Root, [string]$Relative) {
    $path = $Root
    foreach ($part in ($Relative -split '/')) {
      if ($part) { $path = Join-Path $path $part }
    }
    return $path
  }
  function Add-Dest([string]$Dest) {
    if (-not $script:InstallDests.Contains($Dest)) { [void]$script:InstallDests.Add($Dest) }
  }
  $script:InstallDests = New-Object System.Collections.Generic.List[string]

  if ($want['grok']) {
    if ($Scope -ceq 'project') { Add-Dest (Join-SkillPath $projectRoot ".grok/skills/$Name") }
    else { Add-Dest (Join-SkillPath $userRoot ".grok/skills/$Name") }
  }
  if ($want['grok-bot']) { Add-Dest (Join-SkillPath $userRoot ".grok/skills/$Name") }
  if ($want['cursor']) {
    if ($Scope -ceq 'project') { Add-Dest (Join-SkillPath $projectRoot ".cursor/skills/$Name") }
    else { Add-Dest (Join-SkillPath $userRoot ".cursor/skills/$Name") }
  }
  if ($want['openai']) {
    if ($Scope -ceq 'project') { Add-Dest (Join-SkillPath $projectRoot ".agents/skills/$Name") }
    else { Add-Dest (Join-SkillPath $userRoot ".agents/skills/$Name") }
  }
  if ($want['antigravity']) {
    if ($Scope -ceq 'project') { Add-Dest (Join-SkillPath $projectRoot ".agents/skills/$Name") }
    else {
      Add-Dest (Join-SkillPath $userRoot ".gemini/config/skills/$Name")
      Add-Dest (Join-SkillPath $userRoot ".gemini/antigravity-cli/skills/$Name")
    }
  }
  if ($want['claude']) {
    if ($Scope -ceq 'project') { Add-Dest (Join-SkillPath $projectRoot ".claude/skills/$Name") }
    else { Add-Dest (Join-SkillPath $userRoot ".claude/skills/$Name") }
  }

  function Assert-SafeDest([string]$Dest) {
    $norm = $Dest -replace '\\', '/'
    $suffixes = @(
      "/.grok/skills/$Name",
      "/.cursor/skills/$Name",
      "/.agents/skills/$Name",
      "/.claude/skills/$Name",
      "/.gemini/config/skills/$Name",
      "/.gemini/antigravity-cli/skills/$Name"
    )
    foreach ($suffix in $suffixes) {
      if ($norm.EndsWith($suffix)) { return }
    }
    Fail "refusing unexpected destination: $Dest"
  }

  $sourcePrefix = $SkillDir.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
  foreach ($dest in $script:InstallDests) {
    Assert-SafeDest $dest
    $destPrefix = $dest.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
    if ($destPrefix.StartsWith($sourcePrefix)) { Fail "destination is inside the source skill: $dest" }
    if ($sourcePrefix.StartsWith($destPrefix)) { Fail "source skill is inside the destination: $dest" }
    if (Test-Path -LiteralPath $dest) { Remove-Item -LiteralPath $dest -Recurse -Force }
    New-Item -ItemType Directory -Path $dest -Force | Out-Null
    Get-ChildItem -Force -LiteralPath $stage | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination $dest -Recurse -Force
    }
    Write-Output "Installed $dest"
  }

  if ($want['grok']) { Write-Output "Grok: invoke /$Name." }
  if ($want['grok-bot']) {
    Write-Output "Grok Bot paste-in prompt (same SKILL.md). On the bot computer the folder is ~/.grok/skills/$Name/."
    Write-Output 'If that computer cannot read the copied folder, paste the prompt below.'
    Write-Output ''
    Write-Output '----- BEGIN paste-in prompt -----'
    Write-Output "Follow the $Name skill. The instructions are this SKILL.md; do not invent a different procedure."
    Write-Output ''
    Write-Output $stagedText
    Write-Output ''
    Write-Output '----- END paste-in prompt -----'
  }
  if ($want['cursor']) { Write-Output "Cursor: invoke /$Name. name matches folder." }
  if ($want['openai']) {
    Write-Output 'OpenAI / ChatGPT app: zip the skill folder and upload it via Plugins → Skills → Add.'
    Write-Output "Codex: `$$Name"
  }
  if ($want['antigravity']) {
    Write-Output "Antigravity: description required. Project path is .agents/skills/$Name/ (one level). User path is ~/.gemini/config/skills/$Name/. CLI path is ~/.gemini/antigravity-cli/skills/$Name/."
  }
  if ($want['claude']) { Write-Output "Claude: invoke /$Name." }
} finally {
  if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
}

exit 0
