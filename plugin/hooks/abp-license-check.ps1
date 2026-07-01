#requires -Version 5.1
<#
.SYNOPSIS
  Pre-execution ABP Pro license freshness check for kanbantic-issue-execute
  (KBT-F263 / KBT-SR307 / KBT-RL066).

.DESCRIPTION
  Validates that the local environment can satisfy the ABP Pro license-runtime
  check that fires when `dotnet run` starts the Kanbantic API or MCP host.
  The check is performed BEFORE `claim_issue` so a stale auth-token does not
  produce an orphan InProgress claim mid-startup.

  Source of the check-logic: KBT-CMND007 (manual PowerShell pre-flight). This
  hook automates that snippet and emits a structured JSON result so callers
  (Node.js tests, lane-skills) can act without parsing free-text.

  Scope gate (cheap, runs first):
    - applicationSlug in { kanbantic-api, kanbantic-mcp }     OR
    - tagsCsv contains  'backend' or 'live-stack'
  Otherwise action='out-of-scope' and exits 0 — frontend/plugin-only work is
  not blocked.

  Three "happy" paths:
    - ok            : env-var present + token present + token fresh
    - skipped-env   : KANBANTIC_SKIP_ABP_CHECK=1 opt-out
    - out-of-scope  : issue doesn't touch ABP Pro license-runtime

  Three FAIL paths (exit 1 — skill must stop before claim_issue):
    - missing-env-var : ABP_LICENSE_CODE not set on User or Machine scope
    - missing-token   : $USERPROFILE\.abp\cli\access-token.bin missing
    - stale-token     : token LastWriteTime older than threshold

  The function is non-interactive. It does NOT mutate Kanbantic state — the
  caller (kanbantic-issue-execute) is responsible for translating the result
  into discussion-entries per KBT-RL066. This keeps the function pure,
  testable, and free of MCP/I-O coupling.

.PARAMETER ApplicationSlug
  Slug of the issue's application (e.g. 'kanbantic-api', 'kanbantic-angular').

.PARAMETER TagsCsv
  Comma-separated tag names on the issue (e.g. 'backend,live-stack').

.PARAMETER Path
  Filesystem path of the worktree (informational only — does not gate logic).
  Defaults to the current directory.

.PARAMETER MaxAgeDays
  Token-freshness threshold in days. Overridable via env-var
  KANBANTIC_ABP_TOKEN_MAX_AGE_DAYS. Default 7.

.OUTPUTS
  PSCustomObject with shape:
    {
      ok              : [bool]    # false only on a FAIL action
      skipped         : [bool]    # true for skipped-env / out-of-scope
      action          : [string]  # ok | skipped-env | out-of-scope |
                                  #   missing-env-var | missing-token |
                                  #   stale-token
      applicationSlug : [string]
      tagsCsv         : [string]
      tokenAgeDays    : [object]  # double or $null when not checked
      thresholdDays   : [int]
      messages        : [string[]] # human-readable log lines
    }

.EXAMPLE
  pwsh -NoProfile -File abp-license-check.ps1 'kanbantic-api' '' "$PWD"
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function New-AbpResult {
    param(
        [bool] $Ok = $true,
        [bool] $Skipped = $false,
        [Parameter(Mandatory)][string] $Action,
        [string] $ApplicationSlug = '',
        [string] $TagsCsv = '',
        [object] $TokenAgeDays = $null,
        [int] $ThresholdDays = 7,
        [string[]] $Messages = @()
    )
    return [pscustomobject]@{
        ok              = $Ok
        skipped         = $Skipped
        action          = $Action
        applicationSlug = $ApplicationSlug
        tagsCsv         = $TagsCsv
        tokenAgeDays    = $TokenAgeDays
        thresholdDays   = $ThresholdDays
        messages        = @($Messages)
    }
}

function Test-AbpInScope {
    <#
    .SYNOPSIS Scope-gate: does this issue touch the ABP Pro license-runtime?
    #>
    param(
        [string] $ApplicationSlug,
        [string] $TagsCsv
    )
    $slug = ($ApplicationSlug ?? '').Trim().ToLowerInvariant()
    if ($slug -in @('kanbantic-api', 'kanbantic-mcp')) { return $true }

    if (-not [string]::IsNullOrWhiteSpace($TagsCsv)) {
        $tags = $TagsCsv.Split(',') | ForEach-Object { $_.Trim().ToLowerInvariant() }
        if ($tags -contains 'backend' -or $tags -contains 'live-stack') { return $true }
    }
    return $false
}

function Invoke-AbpLicenseCheck {
    [CmdletBinding()]
    param(
        [string] $ApplicationSlug = '',
        [string] $TagsCsv = '',
        [string] $Path = (Get-Location).Path,
        [int] $MaxAgeDays = 0
    )

    $messages = New-Object System.Collections.Generic.List[string]

    # 0. Resolve threshold (env-var override, fallback to parameter, fallback to 7).
    #    Done before any return path so the output JSON always carries a sensible
    #    `thresholdDays` value — useful in audit logs even when the check was skipped.
    if ($MaxAgeDays -le 0) {
        $envThreshold = $env:KANBANTIC_ABP_TOKEN_MAX_AGE_DAYS
        if (-not [string]::IsNullOrWhiteSpace($envThreshold)) {
            [int]$parsed = 0
            if ([int]::TryParse($envThreshold, [ref]$parsed) -and $parsed -gt 0) {
                $MaxAgeDays = $parsed
            }
        }
        if ($MaxAgeDays -le 0) { $MaxAgeDays = 7 }
    }

    # 1. Honor opt-out env-var first — cheapest path.
    if ($env:KANBANTIC_SKIP_ABP_CHECK -eq '1') {
        $messages.Add('ABP license check skipped (KANBANTIC_SKIP_ABP_CHECK=1).')
        return New-AbpResult `
            -Skipped $true `
            -Action 'skipped-env' `
            -ApplicationSlug $ApplicationSlug `
            -TagsCsv $TagsCsv `
            -ThresholdDays $MaxAgeDays `
            -Messages $messages
    }

    # 2. Scope gate — frontend-only / plugin-only work doesn't touch the license-runtime.
    if (-not (Test-AbpInScope -ApplicationSlug $ApplicationSlug -TagsCsv $TagsCsv)) {
        $messages.Add("Application '$ApplicationSlug' and tags '$TagsCsv' do not require the ABP Pro license-runtime — check skipped.")
        return New-AbpResult `
            -Skipped $true `
            -Action 'out-of-scope' `
            -ApplicationSlug $ApplicationSlug `
            -TagsCsv $TagsCsv `
            -ThresholdDays $MaxAgeDays `
            -Messages $messages
    }

    # 3. Check ABP_LICENSE_CODE env-var. We read the User/Machine scope via
    #    [Environment]::GetEnvironmentVariable so this works even from a freshly
    #    spawned child-process. For testability we also accept the process-env
    #    value (env:ABP_LICENSE_CODE) — that allows the test-runner to override
    #    without touching User/Machine registry keys.
    $licenseProcess = $env:ABP_LICENSE_CODE
    $licenseUser    = $null
    $licenseMachine = $null
    try {
        $licenseUser    = [Environment]::GetEnvironmentVariable('ABP_LICENSE_CODE', 'User')
        $licenseMachine = [Environment]::GetEnvironmentVariable('ABP_LICENSE_CODE', 'Machine')
    } catch {
        # GetEnvironmentVariable can throw on non-Windows for 'User'/'Machine' scopes —
        # treat that as "not set on those scopes" and rely on process scope.
    }

    if ([string]::IsNullOrWhiteSpace($licenseProcess) -and
        [string]::IsNullOrWhiteSpace($licenseUser) -and
        [string]::IsNullOrWhiteSpace($licenseMachine)) {
        $messages.Add('ABP_LICENSE_CODE env-var is not set on Process, User, or Machine scope.')
        $messages.Add("Fix: [Environment]::SetEnvironmentVariable('ABP_LICENSE_CODE','<your-license>','User') and open a new shell.")
        return New-AbpResult `
            -Ok $false `
            -Action 'missing-env-var' `
            -ApplicationSlug $ApplicationSlug `
            -TagsCsv $TagsCsv `
            -ThresholdDays $MaxAgeDays `
            -Messages $messages
    }

    # 4. Check the abp CLI auth-token file. We honor USERPROFILE from process-env
    #    so the test-runner can point the hook at a temp fixture directory.
    $userProfile = $env:USERPROFILE
    if ([string]::IsNullOrWhiteSpace($userProfile)) {
        $userProfile = $env:HOME
    }
    $tokenPath = Join-Path $userProfile '.abp/cli/access-token.bin'

    if (-not (Test-Path -LiteralPath $tokenPath)) {
        $messages.Add("abp CLI auth-token missing at '$tokenPath'.")
        $messages.Add("Fix: run 'abp login <your-abp.io-username>' in a non-agent shell (interactive credentials required).")
        return New-AbpResult `
            -Ok $false `
            -Action 'missing-token' `
            -ApplicationSlug $ApplicationSlug `
            -TagsCsv $TagsCsv `
            -ThresholdDays $MaxAgeDays `
            -Messages $messages
    }

    # 5. Check token freshness.
    $tokenItem = Get-Item -LiteralPath $tokenPath
    $age = (Get-Date) - $tokenItem.LastWriteTime
    $ageDays = [math]::Round($age.TotalDays, 2)

    if ($age.TotalDays -gt $MaxAgeDays) {
        $messages.Add("abp CLI auth-token is $ageDays days old (threshold $MaxAgeDays days).")
        $messages.Add("Fix: run 'abp login <your-abp.io-username>' again to refresh — token lifetime is finite (see KBT-GTCH013).")
        return New-AbpResult `
            -Ok $false `
            -Action 'stale-token' `
            -ApplicationSlug $ApplicationSlug `
            -TagsCsv $TagsCsv `
            -TokenAgeDays $ageDays `
            -ThresholdDays $MaxAgeDays `
            -Messages $messages
    }

    # 6. All checks passed.
    $messages.Add("ABP license pre-flight OK — token is $ageDays days old (threshold $MaxAgeDays).")
    return New-AbpResult `
        -Action 'ok' `
        -ApplicationSlug $ApplicationSlug `
        -TagsCsv $TagsCsv `
        -TokenAgeDays $ageDays `
        -ThresholdDays $MaxAgeDays `
        -Messages $messages
}

# When run as a script (not dot-sourced), invoke the function once with default args
# and emit the result as JSON. This lets non-PowerShell callers (e.g. Node.js tests
# in plugin/tests/) parse the output trivially.
if ($MyInvocation.InvocationName -ne '.' -and -not $MyInvocation.ExpectingInput) {
    $appSlug = if ($args.Count -ge 1) { [string]$args[0] } else { '' }
    $tags    = if ($args.Count -ge 2) { [string]$args[1] } else { '' }
    $path    = if ($args.Count -ge 3 -and $args[2]) { [string]$args[2] } else { (Get-Location).Path }
    $result  = Invoke-AbpLicenseCheck -ApplicationSlug $appSlug -TagsCsv $tags -Path $path
    $result | ConvertTo-Json -Depth 5 -Compress
    if (-not $result.ok) { exit 1 } else { exit 0 }
}
