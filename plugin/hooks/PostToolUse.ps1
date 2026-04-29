#requires -Version 5.1
# Hook: PostToolUse — fires after Claude Code receives a tool's result.
# Posts a TranscriptToolResult event with the tool name + result body, with
# truncation handled server-side at 32KB.

. (Join-Path $PSScriptRoot 'transcript-helpers.ps1')

$event = Read-HookInput
if (-not $event) { exit 0 }

$toolName = $event.tool_name
if (-not $toolName) { exit 0 }

$resultJson = ''
if ($event.tool_response) {
    $resultJson = $event.tool_response | ConvertTo-Json -Depth 6 -Compress
}

$content = "Tool: $toolName (result)"
if ($resultJson) {
    $content += "`n`nResult:`n$resultJson"
}

# tool_use_id pairs PreToolUse + PostToolUse for the same call — useful for
# server-side dedup if both this hook and the JSONL-tailer (Phase 5) report
# the same record.
Send-TranscriptEvent `
    -MessageType 'TranscriptToolResult' `
    -Content $content `
    -JsonlRecordUuid $event.tool_use_id
