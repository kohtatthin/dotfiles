# Herdr defaultセッションにいる全AIを、WezTermの細い⑤ペイン向けに一覧表示する。
# JSONをローカルで読むだけで、エージェントへの入力や外部通信は行わない。

param(
    [switch]$Once
)

# herdr.exe のJSON出力はUTF-8。Windows PowerShell 5.1 はネイティブコマンドの出力を
# 既定でcp932として解釈するため、端末タイトルに日本語が入るとJSONが壊れ
# ConvertFrom-Json が「無効なオブジェクト」で失敗する(2026-08-20)。
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$herdrExe = Join-Path $env:LOCALAPPDATA 'Programs\Herdr\bin\herdr.exe'
$esc = [char]27

while ($true) {
    try {
        $workspaceResponse = & $herdrExe workspace list | ConvertFrom-Json
        $agentResponse = & $herdrExe agent list | ConvertFrom-Json

        $workspaceNames = @{}
        $paneNames = @{}
        foreach ($workspace in $workspaceResponse.result.workspaces) {
            $workspaceNames[$workspace.workspace_id] = $workspace.label
            $paneResponse = & $herdrExe pane list --workspace $workspace.workspace_id | ConvertFrom-Json
            foreach ($pane in $paneResponse.result.panes) {
                if ($pane.label) {
                    $paneNames[$pane.pane_id] = $pane.label
                }
            }
        }

        [Console]::Write("${esc}[2J${esc}[H")
        Write-Host 'HERDR AI COCKPIT' -ForegroundColor Cyan
        Write-Host ('更新 {0:HH:mm:ss}' -f (Get-Date)) -ForegroundColor DarkGray
        Write-Host ''

        $agents = @($agentResponse.result.agents)
        foreach ($workspace in $workspaceResponse.result.workspaces) {
            Write-Host ("[{0}]" -f $workspace.label) -ForegroundColor DarkCyan
            $workspaceAgents = @($agents | Where-Object workspace_id -eq $workspace.workspace_id |
                Sort-Object pane_id)

            if ($workspaceAgents.Count -eq 0) {
                Write-Host '  （待機スロット）' -ForegroundColor DarkGray
                continue
            }

            foreach ($agent in $workspaceAgents) {
                $agentName = if ($paneNames[$agent.pane_id]) {
                    $paneNames[$agent.pane_id]
                }
                elseif ($agent.name) {
                    $agent.name
                }
                else {
                    $agent.agent
                }
                $status = [string]$agent.agent_status
                $color = switch ($status) {
                    'working' { 'Yellow' }
                    'blocked' { 'Red' }
                    'done'    { 'Green' }
                    'idle'    { 'DarkGray' }
                    default   { 'Gray' }
                }
                Write-Host ("  {0}  {1}" -f $agentName, $status) -ForegroundColor $color
            }
        }

        Write-Host ''
        Write-Host 'Ctrl+Shift+H: Herdrを別窓で開く' -ForegroundColor DarkGray
        Write-Host 'F9: agmsg / AI委譲 / 各CLI' -ForegroundColor DarkGray
    }
    catch {
        [Console]::Write("${esc}[2J${esc}[H")
        Write-Host 'HERDR AI COCKPIT' -ForegroundColor Cyan
        Write-Host ('取得失敗: {0}' -f $_.Exception.Message) -ForegroundColor Red
    }

    if ($Once) {
        break
    }
    Start-Sleep -Seconds 3
}
