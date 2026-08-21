param(
    [switch]$ConfigureOnly,
    [switch]$SkipLocal
)

$ErrorActionPreference = 'Stop'

# herdr.exe のJSON出力はUTF-8。Windows PowerShell 5.1 はネイティブコマンドの出力を
# 既定でcp932として解釈するため、端末タイトルに日本語が入るとJSONが壊れ
# ConvertFrom-Json が「無効なオブジェクト」で失敗する(2026-08-20)。
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$herdrExe = Join-Path $env:LOCALAPPDATA 'Programs\Herdr\bin\herdr.exe'
$codexAccountScript = Join-Path $env:USERPROFILE 'dotfiles\wezterm\codex-account.ps1'

function Get-HerdrJson {
    param([string[]]$Arguments)

    $raw = & $herdrExe @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Herdr command failed: $($Arguments -join ' ')"
    }
    return ($raw | ConvertFrom-Json)
}

function Test-HerdrServer {
    $result = & $herdrExe status server 2>$null | Out-String
    return ($LASTEXITCODE -eq 0 -and $result -match 'status:\s+running')
}

function Start-HerdrServer {
    if (Test-HerdrServer) {
        return
    }

    Start-Process -FilePath $herdrExe -ArgumentList @('server') -WindowStyle Hidden
    foreach ($attempt in 1..40) {
        Start-Sleep -Milliseconds 250
        if (Test-HerdrServer) {
            return
        }
    }
    throw 'Herdr server did not become ready within 10 seconds.'
}

function Get-WorkspaceByLabel {
    param([string]$Label)

    $response = Get-HerdrJson @('workspace', 'list')
    return @($response.result.workspaces) |
        Where-Object label -eq $Label |
        Select-Object -First 1
}

function Get-PaneByLabel {
    param(
        [string]$WorkspaceId,
        [string]$Label
    )

    $response = Get-HerdrJson @('pane', 'list', '--workspace', $WorkspaceId)
    return @($response.result.panes) |
        Where-Object label -eq $Label |
        Select-Object -First 1
}

function Get-LiveAgentPaneIds {
    $response = Get-HerdrJson @('agent', 'list')
    return @($response.result.agents | ForEach-Object pane_id)
}

function Start-AgentIfMissing {
    param(
        [object]$Pane,
        [string]$Command,
        [string]$DisplayName,
        [string[]]$LiveAgentPaneIds
    )

    if (-not $Pane) {
        throw "Required pane is missing: $DisplayName"
    }
    if ($LiveAgentPaneIds -contains $Pane.pane_id) {
        Write-Host "Already running: $DisplayName" -ForegroundColor DarkGray
        return
    }

    Write-Host "Starting: $DisplayName" -ForegroundColor Cyan
    & $herdrExe pane run $Pane.pane_id $Command
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to start: $DisplayName"
    }
}

Start-HerdrServer

$core = Get-WorkspaceByLabel 'Core Agents'
$extra = Get-WorkspaceByLabel 'Extra Agents'
$local = Get-WorkspaceByLabel 'Local LLM'

if (-not $core -or -not $extra -or -not $local) {
    throw 'Herdr topology is incomplete. Expected Core Agents, Extra Agents, and Local LLM.'
}

$liveAgentPaneIds = Get-LiveAgentPaneIds
$userRoot = $env:USERPROFILE

$claudeWork = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:AGMSG_AGENT commander; Set-Location C:\claude; claude --name commander"
$claudePersonal = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude-personal; Set-Item Env:AGMSG_AGENT jikko; Set-Location C:\claude; claude --model claude-opus-4-6 --name jikko"
$codexPersonal = "Set-Item Env:AGMSG_AGENT codex-sol; Set-Location C:\claude; & $codexAccountScript -Account personal"
$codexWork = "Set-Item Env:AGMSG_AGENT codex-luna; Set-Location C:\claude; & $codexAccountScript -Account work"
$claudeWorkExtra = "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:AGMSG_AGENT claude-extra; Set-Location C:\claude; claude --name claude-extra"
$grok = 'Set-Location C:\claude; grok'
$antigravity = "Set-Location C:\claude; & $userRoot\AppData\Local\agy\bin\agy.exe"
$localLlm = 'lms server start; lms unload --all; lms load lfm2.5-2.6b --context-length 32768 --yes; Set-Location C:\claude; opencode --model lmstudio/lfm2.5-2.6b'
$localLlmExtra = 'Set-Location C:\claude; opencode --model lmstudio/lfm2.5-2.6b'

Start-AgentIfMissing (Get-PaneByLabel $core.workspace_id 'Claude Work - Commander') $claudeWork 'Claude Work - Commander' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $core.workspace_id 'Codex Personal - Sol') $codexPersonal 'Codex Personal - Sol' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $core.workspace_id 'Claude Personal - Jikko') $claudePersonal 'Claude Personal - Jikko' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $core.workspace_id 'Codex Work - Luna') $codexWork 'Codex Work - Luna' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $extra.workspace_id 'Grok') $grok 'Grok' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $extra.workspace_id 'Antigravity CLI') $antigravity 'Antigravity CLI' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $extra.workspace_id 'Claude Work - Extra') $claudeWorkExtra 'Claude Work - Extra' $liveAgentPaneIds

if (-not $SkipLocal) {
    Start-AgentIfMissing (Get-PaneByLabel $local.workspace_id 'Local LLM slot (LFM/Qwen/Gemma/Nemotron)') $localLlm 'Local LLM - LFM 2.5' $liveAgentPaneIds
    Start-AgentIfMissing (Get-PaneByLabel $extra.workspace_id 'Local LLM - Extra') $localLlmExtra 'Local LLM - Extra' $liveAgentPaneIds
}

& $herdrExe workspace focus $core.workspace_id | Out-Null

if (-not $ConfigureOnly) {
    & $herdrExe
}
