#requires -Version 5.1
<#
.SYNOPSIS
  Pre-execution git sync check for kanbantic-issue-execute (KBT-F238 / KBT-SR302).

.DESCRIPTION
  Determines whether the local worktree's base branch is behind origin/<default>
  and reports an actionable result to the caller. The function does NOT mutate
  Kanbantic state directly — it returns a structured object that the calling
  skill turns into MCP discussion-entries. This keeps the function pure,
  testable, and free of MCP/I-O coupling.

  Three "happy" paths:
    - up-to-date    : behindCount == 0, no action
    - pulled        : behindCount > 0, default action rebased feature-branch
    - skipped-env   : KANBANTIC_SKIP_GIT_SYNC=1 opt-out

  Three graceful-degradation paths:
    - no-origin     : repo has no 'origin' remote
    - detached-head : HEAD is not on any branch
    - fetch-failed  : `git fetch origin <default>` returned non-zero
    - not-a-repo    : Path is outside any git working tree

  The function is non-interactive. The default action when behindCount > 0
  is governed by -DefaultAction (Pull|Force|Abort). The caller is responsible
  for translating the result into a user-prompt where applicable.

.PARAMETER Path
  Filesystem path to a git worktree. Defaults to the current directory.

.PARAMETER DefaultAction
  What to do when behindCount > 0 in non-interactive mode.
    Pull  (default) — rebase the feature-branch on origin/<default>
    Force            — skip the rebase, leave the base stale, log a Decision
    Abort            — return action='aborted'; caller must stop the skill

.PARAMETER FetchTimeoutSec
  Hard timeout for the `git fetch` call. Defaults to 30s.

.OUTPUTS
  A PSCustomObject with shape:
    {
      ok             : [bool]   # the check finished cleanly (true for skipped too)
      skipped        : [bool]   # the check did not actually compare HEAD to origin
      action         : [string] # up-to-date | pulled | force-continue | aborted |
                                #   skipped-env | no-origin | detached-head |
                                #   fetch-failed | not-a-repo | rebase-conflict
      behindCount    : [int]    # number of commits origin is ahead of merge-base
      defaultBranch  : [string] # e.g. 'main' (empty when no origin)
      branch         : [string] # current local branch (empty when detached)
      originSha      : [string] # tip sha of origin/<default> (empty when no origin)
      localSha       : [string] # tip sha of the current branch
      messages       : [string[]] # human-readable log lines
    }

.EXAMPLE
  $r = Invoke-GitSyncCheck -Path 'C:\repo' -DefaultAction Pull
  if ($r.action -eq 'pulled') { Write-Host "Rebased on origin/$($r.defaultBranch)" }
#>

Set-StrictMode -Version 3.0
$ErrorActionPreference = 'Stop'

function Invoke-Git {
    <#
    .SYNOPSIS Internal helper — runs git with the given args and captures stdout/stderr.
    Returns @{ ExitCode; StdOut; StdErr }.
    #>
    param(
        [Parameter(Mandatory)] [string] $WorkingDir,
        [Parameter(Mandatory)] [string[]] $Args,
        [int] $TimeoutSec = 0
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'git'
    foreach ($a in $Args) { [void] $psi.ArgumentList.Add($a) }
    $psi.WorkingDirectory = $WorkingDir
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true

    $p = [System.Diagnostics.Process]::Start($psi)
    if ($TimeoutSec -gt 0) {
        if (-not $p.WaitForExit($TimeoutSec * 1000)) {
            try { $p.Kill($true) } catch { }
            return @{ ExitCode = 124; StdOut = ''; StdErr = "git command timed out after ${TimeoutSec}s" }
        }
    } else {
        $p.WaitForExit()
    }
    return @{
        ExitCode = $p.ExitCode
        StdOut   = $p.StandardOutput.ReadToEnd().Trim()
        StdErr   = $p.StandardError.ReadToEnd().Trim()
    }
}

function New-SyncResult {
    param(
        [bool] $Ok = $true,
        [bool] $Skipped = $false,
        [Parameter(Mandatory)][string] $Action,
        [int] $BehindCount = 0,
        [string] $DefaultBranch = '',
        [string] $Branch = '',
        [string] $OriginSha = '',
        [string] $LocalSha = '',
        [string[]] $Messages = @()
    )
    return [pscustomobject]@{
        ok            = $Ok
        skipped       = $Skipped
        action        = $Action
        behindCount   = $BehindCount
        defaultBranch = $DefaultBranch
        branch        = $Branch
        originSha     = $OriginSha
        localSha      = $LocalSha
        messages      = @($Messages)
    }
}

function Invoke-GitSyncCheck {
    [CmdletBinding()]
    param(
        [string] $Path = (Get-Location).Path,
        [ValidateSet('Pull', 'Force', 'Abort')]
        [string] $DefaultAction = 'Pull',
        [int] $FetchTimeoutSec = 30
    )

    $messages = New-Object System.Collections.Generic.List[string]

    # 0. Honor opt-out env-var first — cheapest path.
    if ($env:KANBANTIC_SKIP_GIT_SYNC -eq '1') {
        $messages.Add('Sync check skipped (KANBANTIC_SKIP_GIT_SYNC=1).')
        return New-SyncResult -Skipped $true -Action 'skipped-env' -Messages $messages
    }

    # 1. Are we even in a git working tree?
    $r = Invoke-Git -WorkingDir $Path -Args @('rev-parse', '--is-inside-work-tree')
    if ($r.ExitCode -ne 0 -or $r.StdOut -ne 'true') {
        $messages.Add("Path '$Path' is not inside a git working tree — sync check skipped.")
        return New-SyncResult -Skipped $true -Action 'not-a-repo' -Messages $messages
    }

    # 2. Is HEAD on a branch?
    $branchResult = Invoke-Git -WorkingDir $Path -Args @('symbolic-ref', '--quiet', '--short', 'HEAD')
    $branch = ''
    if ($branchResult.ExitCode -eq 0) {
        $branch = $branchResult.StdOut
    } else {
        $messages.Add('HEAD is detached — sync check skipped (origin comparison undefined).')
        return New-SyncResult -Skipped $true -Action 'detached-head' -Messages $messages
    }

    # 3. Is there an 'origin' remote?
    $remoteResult = Invoke-Git -WorkingDir $Path -Args @('remote')
    if ($remoteResult.ExitCode -ne 0 -or ($remoteResult.StdOut -split "`n") -notcontains 'origin') {
        $messages.Add('No origin remote configured — sync check skipped.')
        return New-SyncResult -Skipped $true -Action 'no-origin' -Branch $branch -Messages $messages
    }

    # 4. Determine the default branch of origin.
    $defaultBranch = 'main'
    $headRefResult = Invoke-Git -WorkingDir $Path -Args @('symbolic-ref', '--quiet', '--short', 'refs/remotes/origin/HEAD')
    if ($headRefResult.ExitCode -eq 0 -and $headRefResult.StdOut) {
        # Result format: 'origin/main' — strip the 'origin/' prefix.
        $defaultBranch = $headRefResult.StdOut -replace '^origin/', ''
    }

    # 5. Fetch the default branch.
    $fetchResult = Invoke-Git -WorkingDir $Path -Args @('fetch', 'origin', $defaultBranch, '--quiet') -TimeoutSec $FetchTimeoutSec
    if ($fetchResult.ExitCode -ne 0) {
        $err = if ($fetchResult.StdErr) { $fetchResult.StdErr } else { 'unknown fetch error' }
        $messages.Add("git fetch origin $defaultBranch failed: $err — sync check skipped.")
        return New-SyncResult -Skipped $true -Action 'fetch-failed' -Branch $branch -DefaultBranch $defaultBranch -Messages $messages
    }

    # 6. Compute behindCount = commits in origin/<default> that aren't in our merge-base.
    $mbResult = Invoke-Git -WorkingDir $Path -Args @('merge-base', 'HEAD', "origin/$defaultBranch")
    if ($mbResult.ExitCode -ne 0) {
        $messages.Add("Could not compute merge-base against origin/$defaultBranch — sync check skipped.")
        return New-SyncResult -Skipped $true -Action 'fetch-failed' -Branch $branch -DefaultBranch $defaultBranch -Messages $messages
    }
    $mergeBase = $mbResult.StdOut

    $countResult = Invoke-Git -WorkingDir $Path -Args @('rev-list', '--count', "$mergeBase..origin/$defaultBranch")
    $behindCount = 0
    if ($countResult.ExitCode -eq 0) {
        $behindCount = [int]$countResult.StdOut
    }

    $localSha = (Invoke-Git -WorkingDir $Path -Args @('rev-parse', 'HEAD')).StdOut
    $originSha = (Invoke-Git -WorkingDir $Path -Args @('rev-parse', "origin/$defaultBranch")).StdOut

    if ($behindCount -eq 0) {
        $messages.Add("Local base up-to-date with origin/$defaultBranch.")
        return New-SyncResult `
            -Action 'up-to-date' `
            -BehindCount 0 `
            -Branch $branch `
            -DefaultBranch $defaultBranch `
            -OriginSha $originSha `
            -LocalSha $localSha `
            -Messages $messages
    }

    $messages.Add("Local base is behind origin/$defaultBranch by $behindCount commit(s). Risk: stale base produces avoidable merge conflicts at review-time.")

    switch ($DefaultAction) {
        'Abort' {
            $messages.Add('Operator chose Abort — skill must stop without claiming the issue.')
            return New-SyncResult `
                -Ok $false `
                -Action 'aborted' `
                -BehindCount $behindCount `
                -Branch $branch `
                -DefaultBranch $defaultBranch `
                -OriginSha $originSha `
                -LocalSha $localSha `
                -Messages $messages
        }
        'Force' {
            $messages.Add('Operator chose Force-continue — stale base accepted. Log a Decision entry on the issue (KBT-RL063).')
            return New-SyncResult `
                -Action 'force-continue' `
                -BehindCount $behindCount `
                -Branch $branch `
                -DefaultBranch $defaultBranch `
                -OriginSha $originSha `
                -LocalSha $localSha `
                -Messages $messages
        }
        Default { # Pull
            $rebaseResult = Invoke-Git -WorkingDir $Path -Args @('rebase', "origin/$defaultBranch")
            if ($rebaseResult.ExitCode -ne 0) {
                # Conflict — abort rebase and degrade to force-continue with a warning.
                [void] (Invoke-Git -WorkingDir $Path -Args @('rebase', '--abort'))
                $messages.Add('Rebase produced conflicts; aborted. Degrading to force-continue — manual merge may be needed later.')
                return New-SyncResult `
                    -Action 'rebase-conflict' `
                    -BehindCount $behindCount `
                    -Branch $branch `
                    -DefaultBranch $defaultBranch `
                    -OriginSha $originSha `
                    -LocalSha $localSha `
                    -Messages $messages
            }
            $newLocalSha = (Invoke-Git -WorkingDir $Path -Args @('rev-parse', 'HEAD')).StdOut
            $messages.Add("Rebased feature-branch on origin/$defaultBranch ($behindCount commits). HEAD: $localSha -> $newLocalSha.")
            return New-SyncResult `
                -Action 'pulled' `
                -BehindCount $behindCount `
                -Branch $branch `
                -DefaultBranch $defaultBranch `
                -OriginSha $originSha `
                -LocalSha $newLocalSha `
                -Messages $messages
        }
    }
}

# When run as a script (not dot-sourced), invoke the function once with default args
# and emit the result as JSON. This lets non-PowerShell callers (e.g. Node.js tests
# in plugin/tests/) parse the output trivially.
if ($MyInvocation.InvocationName -ne '.' -and -not $MyInvocation.ExpectingInput) {
    $defaultAction = if ($args.Count -ge 1 -and $args[0]) { $args[0] } else { 'Pull' }
    $path          = if ($args.Count -ge 2 -and $args[1]) { $args[1] } else { (Get-Location).Path }
    $result = Invoke-GitSyncCheck -Path $path -DefaultAction $defaultAction
    $result | ConvertTo-Json -Depth 5 -Compress
}
