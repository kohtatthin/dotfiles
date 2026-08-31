# Herdr AI Cockpit — ワークスペース一覧 + キー切替メニュー（⑤ペイン用）
# 1/2/3キーでワークスペース切替、Rで表示リフレッシュ、Qで終了。

param(
    [switch]$Once
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$herdrExe = Join-Path $env:LOCALAPPDATA 'Programs\Herdr\bin\herdr.exe'
$esc = [char]27

function Get-HerdrState {
    $ws = & $herdrExe workspace list | ConvertFrom-Json
    $ag = & $herdrExe agent list | ConvertFrom-Json

    $paneNames = @{}
    foreach ($w in $ws.result.workspaces) {
        $pr = & $herdrExe pane list --workspace $w.workspace_id | ConvertFrom-Json
        foreach ($p in $pr.result.panes) {
            if ($p.label) {
                $paneNames[$p.pane_id] = $p.label
            }
        }
    }

    return @{
        Workspaces = @($ws.result.workspaces)
        Agents     = @($ag.result.agents)
        PaneNames  = $paneNames
    }
}

function Show-Cockpit($s) {
    [Console]::Write("${esc}[2J${esc}[H")
    Write-Host 'HERDR AI COCKPIT' -ForegroundColor Cyan
    Write-Host ('{0:HH:mm:ss}' -f (Get-Date)) -ForegroundColor DarkGray
    Write-Host ''

    $workspaces = $s.Workspaces
    $agents = $s.Agents
    $names = $s.PaneNames
    $num = 1

    foreach ($w in $workspaces) {
        if ($w.focused) {
            $mark = ' *'
            $clr = 'White'
        }
        else {
            $mark = ''
            $clr = 'DarkCyan'
        }
        Write-Host -NoNewline '  ' -ForegroundColor DarkGray
        Write-Host -NoNewline "$num" -ForegroundColor $clr
        Write-Host -NoNewline '  ' -ForegroundColor DarkGray
        Write-Host ("[{0}]{1}" -f $w.label, $mark) -ForegroundColor $clr

        $wAgents = @($agents | Where-Object { $_.workspace_id -eq $w.workspace_id } |
            Sort-Object pane_id)

        if ($wAgents.Count -eq 0) {
            Write-Host '     (idle)' -ForegroundColor DarkGray
        }
        else {
            foreach ($a in $wAgents) {
                $paneId = $a.pane_id
                $pLabel = $names[$paneId]
                if ($pLabel) { $aName = $pLabel }
                elseif ($a.name) { $aName = $a.name }
                else { $aName = $a.agent }

                $st = [string]$a.agent_status
                $stClr = switch ($st) {
                    'working' { 'Yellow' }
                    'blocked' { 'Red' }
                    'done'    { 'Green' }
                    'idle'    { 'DarkGray' }
                    default   { 'Gray' }
                }
                Write-Host ("     {0}  {1}" -f $aName, $st) -ForegroundColor $stClr
            }
        }
        $num++
    }

    Write-Host ''
    Write-Host "1-3: Switch  Ctrl+Shift+H: New Window" -ForegroundColor DarkGray
}

while ($true) {
    try {
        $state = Get-HerdrState
        Show-Cockpit $state
    }
    catch {
        [Console]::Write("${esc}[2J${esc}[H")
        Write-Host 'HERDR AI COCKPIT' -ForegroundColor Cyan
        Write-Host ('Error: {0}' -f $_.Exception.Message) -ForegroundColor Red
    }

    if ($Once) { break }

    $deadline = (Get-Date).AddSeconds(3)
    while ((Get-Date) -lt $deadline) {
        if ([Console]::KeyAvailable) {
            $key = [Console]::ReadKey($true)
            $ch = $key.KeyChar
            $wsList = $state.Workspaces
            if ($ch -eq '1' -and $wsList.Count -ge 1) {
                & $herdrExe workspace focus $wsList[0].workspace_id 2>$null | Out-Null
                break
            }
            elseif ($ch -eq '2' -and $wsList.Count -ge 2) {
                & $herdrExe workspace focus $wsList[1].workspace_id 2>$null | Out-Null
                break
            }
            elseif ($ch -eq '3' -and $wsList.Count -ge 3) {
                & $herdrExe workspace focus $wsList[2].workspace_id 2>$null | Out-Null
                break
            }
            elseif ($ch -eq 'r' -or $ch -eq 'R') {
                break
            }
            elseif ($ch -eq 'q' -or $ch -eq 'Q') {
                return
            }
        }
        Start-Sleep -Milliseconds 100
    }
}
