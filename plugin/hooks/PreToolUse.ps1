#requires -Version 5.1
# Hook: PreToolUse — fires before Claude Code invokes a tool. Posts a
# TranscriptToolCall event with the tool name + (best-effort) input arguments.

. (Join-Path $PSScriptRoot 'transcript-helpers.ps1')

$event = Read-HookInput
if (-not $event) { exit 0 }

$toolName = $event.tool_name
if (-not $toolName) { exit 0 }

$inputJson = ''
if ($event.tool_input) {
    $inputJson = $event.tool_input | ConvertTo-Json -Depth 6 -Compress
}

$content = "Tool: $toolName"
if ($inputJson) {
    $content += "`n`nInput:`n$inputJson"
}

Send-TranscriptEvent `
    -MessageType 'TranscriptToolCall' `
    -Content $content `
    -JsonlRecordUuid $event.tool_use_id
