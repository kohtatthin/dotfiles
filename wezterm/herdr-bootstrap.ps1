param(
    [switch]$ConfigureOnly,
    [switch]$SkipLocal,
    [switch]$SkipReview
)

$ErrorActionPreference = 'Stop'

# herdr.exe のJSON出力はUTF-8。Windows PowerShell 5.1 はネイティブコマンドの出力を
# 既定でcp932として解釈するため、端末タイトルに日本語が入るとJSONが壊れ
# ConvertFrom-Json が「無効なオブジェクト」で失敗する(2026-08-20)。
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$herdrExe = Join-Path $env:LOCALAPPDATA 'Programs\Herdr\bin\herdr.exe'
$codexAccountScript = Join-Path $env:USERPROFILE 'dotfiles\wezterm\codex-account.ps1'
$workRoot = 'C:\claude'

# ワークスペースは「番号順 = この並び順」で扱う（2026-08-31 v2再編）。
#   w1 CORE   : 常用4枠
#   w2 REVIEW : 会社CCによる並列レビュー専用4枠
#   w3 EXTRA  : 予備枠
#   w4 Local LLM
# herdr には並べ替えコマンドが無く、番号は作成順で決まる。新規セッションでは
# この順に作られ、既存セッションでは不足分が末尾に追加される。
$workspacePlan = @(
    'Core Agents',
    'Review Agents',
    'Extra Agents',
    'Local LLM'
)

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

# ---------- ワークスペース ----------

function Get-WorkspaceList {
    $response = Get-HerdrJson @('workspace', 'list')
    return @($response.result.workspaces) | Sort-Object number
}

# 計画順にワークスペースを解決する。
#   1. 同じラベルが既にあればそれを使う
#   2. その位置に「計画外のラベル」のワークスペースがあれば採用してリネームする
#      （新規セッションの既定ワークスペースを w1 CORE として拾うため）
#   3. どちらでもなければ新規作成する（既存セッションでは末尾に付く）
function Resolve-Workspaces {
    $existing = @(Get-WorkspaceList)
    $resolved = [ordered]@{}

    for ($i = 0; $i -lt $workspacePlan.Count; $i++) {
        $label = $workspacePlan[$i]

        $match = $existing | Where-Object label -eq $label | Select-Object -First 1
        if ($match) {
            $resolved[$label] = $match.workspace_id
            continue
        }

        $candidate = $existing | Select-Object -Skip $i -First 1
        if ($candidate -and ($workspacePlan -notcontains $candidate.label)) {
            Write-Host "Renaming workspace: $($candidate.label) -> $label" -ForegroundColor Cyan
            & $herdrExe workspace rename $candidate.workspace_id $label | Out-Null
            if ($LASTEXITCODE -ne 0) {
                throw "Failed to rename workspace: $($candidate.workspace_id)"
            }
            $candidate.label = $label
            $resolved[$label] = $candidate.workspace_id
            continue
        }

        Write-Host "Creating workspace: $label" -ForegroundColor Cyan
        $created = Get-HerdrJson @('workspace', 'create', '--label', $label, '--cwd', $workRoot, '--no-focus')
        $workspaceId = $created.result.workspace.workspace_id
        $resolved[$label] = $workspaceId
        $existing = @($existing) + ([pscustomobject]@{
            workspace_id = $workspaceId
            label        = $label
            number       = 9999
        })
    }

    return $resolved
}

# ---------- ペイン ----------

# pane_id は "w1:p3" 形式。番号は作成順に採番されるため、番号順に並べると
# 左上 → 右上 → 左下 → 右下 になる（下の Initialize-PaneGrid の分割順に対応）。
function Get-SortedPaneIds {
    param([string]$WorkspaceId)

    $response = Get-HerdrJson @('pane', 'list', '--workspace', $WorkspaceId)
    return @(@($response.result.panes) |
        Sort-Object { [int](($_.pane_id -split ':p')[1]) } |
        ForEach-Object pane_id)
}

function Split-HerdrPane {
    param(
        [string]$PaneId,
        [ValidateSet('right', 'down')][string]$Direction
    )

    $response = Get-HerdrJson @('pane', 'split', '--pane', $PaneId, '--direction', $Direction, '--no-focus')
    return $response.result.pane.pane_id
}

# 目標枚数までペインを用意する。既に足りていれば何もしない（冪等）。
function Initialize-PaneGrid {
    param(
        [string]$WorkspaceId,
        [int]$Want = 4
    )

    $ids = @(Get-SortedPaneIds $WorkspaceId)
    if ($ids.Count -eq 1 -and $Want -eq 4) {
        $topLeft = $ids[0]
        $topRight = Split-HerdrPane $topLeft 'right'
        Split-HerdrPane $topLeft 'down' | Out-Null
        Split-HerdrPane $topRight 'down' | Out-Null
    }

    # 不足分は最後のペインを下に割って埋める
    while ((Get-SortedPaneIds $WorkspaceId).Count -lt $Want) {
        $last = @(Get-SortedPaneIds $WorkspaceId)[-1]
        Split-HerdrPane $last 'down' | Out-Null
    }
}

# ラベルを pane_id 昇順で割り当てる。以降のエージェント起動は並び順ではなく
# ラベルで引く（herdr pane list の返却順は作成順ではない。2026-08-30 の学び）。
function Set-PaneLabels {
    param(
        [string]$WorkspaceId,
        [string[]]$Labels
    )

    $ids = @(Get-SortedPaneIds $WorkspaceId)
    for ($i = 0; $i -lt $Labels.Count -and $i -lt $ids.Count; $i++) {
        & $herdrExe pane rename $ids[$i] $Labels[$i] | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to rename pane: $($ids[$i]) -> $($Labels[$i])"
        }
    }
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

# ---------- エージェント ----------

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

# ---------- メイン ----------

Start-HerdrServer

$workspaces = Resolve-Workspaces
$core   = $workspaces['Core Agents']
$review = $workspaces['Review Agents']
$extra  = $workspaces['Extra Agents']
$local  = $workspaces['Local LLM']

# CORE: 配置は現状維持。2026-08-31 に個人CCを Utility、個人Codex を Plan/Build へ改称。
Initialize-PaneGrid $core 4
Set-PaneLabels $core @(
    'Claude Work - Commander',
    'Codex Personal - Plan/Build',
    'Claude Personal - Utility',
    'Codex Work - Luna'
)

# REVIEW: 4枠すべて会社アカウント。並列レビュー前提（2026-08-31 新設）。
# 実装セッションに自分の成果をレビューさせないため、依頼は handoff / ai-delegate 経由で渡す。
Initialize-PaneGrid $review 4
Set-PaneLabels $review @(
    'Claude Work - Review A',
    'Claude Work - Review B',
    'Claude Work - Review C',
    'Claude Work - Review D'
)

# EXTRA: 構成変更なし（w2 から w3 へ繰り下げのみ）
Initialize-PaneGrid $extra 4
Set-PaneLabels $extra @(
    'Grok',
    'Antigravity CLI',
    'Claude Work - Extra',
    'Local LLM - Extra'
)

# Local LLM: 1枠（w3 から w4 へ繰り下げのみ）
Initialize-PaneGrid $local 1
Set-PaneLabels $local @('Local LLM slot (LFM/Qwen/Gemma/Nemotron)')

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

# REVIEW枠はすべて会社プロファイル（CLAUDE_CONFIG_DIR = $userRoot\.claude）。
function Get-ReviewCommand {
    param([string]$Slot)

    $name = "review-$($Slot.ToLower())"
    return "Set-Item Env:CLAUDE_CONFIG_DIR $userRoot\.claude; Set-Item Env:AGMSG_AGENT $name; Set-Location C:\claude; claude --name $name"
}

# --- CORE ---
Start-AgentIfMissing (Get-PaneByLabel $core 'Claude Work - Commander') $claudeWork 'Claude Work - Commander' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $core 'Codex Personal - Plan/Build') $codexPersonal 'Codex Personal - Plan/Build' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $core 'Claude Personal - Utility') $claudePersonal 'Claude Personal - Utility' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $core 'Codex Work - Luna') $codexWork 'Codex Work - Luna' $liveAgentPaneIds

# --- REVIEW ---
if (-not $SkipReview) {
    foreach ($slot in @('A', 'B', 'C', 'D')) {
        $label = "Claude Work - Review $slot"
        Start-AgentIfMissing (Get-PaneByLabel $review $label) (Get-ReviewCommand $slot) $label $liveAgentPaneIds
    }
}

# --- EXTRA ---
Start-AgentIfMissing (Get-PaneByLabel $extra 'Grok') $grok 'Grok' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $extra 'Antigravity CLI') $antigravity 'Antigravity CLI' $liveAgentPaneIds
Start-AgentIfMissing (Get-PaneByLabel $extra 'Claude Work - Extra') $claudeWorkExtra 'Claude Work - Extra' $liveAgentPaneIds

if (-not $SkipLocal) {
    Start-AgentIfMissing (Get-PaneByLabel $local 'Local LLM slot (LFM/Qwen/Gemma/Nemotron)') $localLlm 'Local LLM - LFM 2.5' $liveAgentPaneIds
    Start-AgentIfMissing (Get-PaneByLabel $extra 'Local LLM - Extra') $localLlmExtra 'Local LLM - Extra' $liveAgentPaneIds
}

& $herdrExe workspace focus $core | Out-Null

if (-not $ConfigureOnly) {
    & $herdrExe
}
