#requires -Version 5.1
# Hook: Stop — fires at the end of an agent turn (Claude has finished responding).
# Posts a TranscriptStop event marking the turn boundary in the Kanbantic UI.

. (Join-Path $PSScriptRoot 'transcript-helpers.ps1')

$event = Read-HookInput
if (-not $event) { exit 0 }

$content = "End of turn"
if ($event.stop_hook_active) {
    $content += " (stop_hook_active)"
}

Send-TranscriptEvent `
    -MessageType 'TranscriptStop' `
    -Content $content
