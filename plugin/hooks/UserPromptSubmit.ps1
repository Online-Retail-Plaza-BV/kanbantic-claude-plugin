#requires -Version 5.1
# Hook: UserPromptSubmit — fires when the user submits a prompt to Claude Code.
# Posts the prompt as a TranscriptUserPrompt event to the Kanbantic AgentChannel
# so the Kanbantic UI shows it as a transcript-event in real time.

. (Join-Path $PSScriptRoot 'transcript-helpers.ps1')

$event = Read-HookInput
if (-not $event) { exit 0 }

$prompt = $event.prompt
if (-not $prompt) { exit 0 }

Send-TranscriptEvent `
    -MessageType 'TranscriptUserPrompt' `
    -Content $prompt
