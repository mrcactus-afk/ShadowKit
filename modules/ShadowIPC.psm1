$script:StateDir = 'C:\ShadowKit\state'
$script:StatusFile = Join-Path $script:StateDir 'status.json'
$script:CommandFile = Join-Path $script:StateDir 'command.json'
$script:ResponseFile = Join-Path $script:StateDir 'command_response.json'
$script:CommandMutexName = 'Global\ShadowKitCommandMutex'
$script:StatusMutexName = 'Global\ShadowKitStatusMutex'

function Get-ShadowStatus {
    param([string]$Component)
    if (-not (Test-Path $script:StatusFile)) { return $null }
    $raw = Get-Content $script:StatusFile -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $obj = $raw | ConvertFrom-Json
    if ($Component) { return $obj.$Component } else { return $obj }
}

function Set-ShadowStatus {
    param(
        [string]$Component,
        [string]$Status,
        [hashtable]$Data = @{}
    )
    $mtx = New-Object System.Threading.Mutex($false, $script:StatusMutexName)
    try {
        if ($mtx.WaitOne(3000)) {
            $dict = @{}
            if (Test-Path $script:StatusFile) {
                $raw = Get-Content $script:StatusFile -Raw
                if ($raw) {
                    $obj = $raw | ConvertFrom-Json
                    foreach ($p in $obj.PSObject.Properties) { $dict[$p.Name] = $p.Value }
                }
            }
            $dict[$Component] = [ordered]@{
                status = $Status
                pid    = $PID
                updated = (Get-Date).ToString('o')
                data   = $Data
            }
            $tmp = "$script:StatusFile.tmp"
            $dict | ConvertTo-Json -Depth 6 | Set-Content $tmp -Encoding UTF8
            Move-Item $tmp $script:StatusFile -Force
        }
    } finally {
        try { $mtx.ReleaseMutex() } catch {}
        $mtx.Dispose()
    }
}

function Send-ShadowCommand {
    param(
        [string]$Action,
        [hashtable]$Payload = @{},
        [int]$TimeoutSeconds = 15
    )
    $requestId = [guid]::NewGuid().ToString()
    $cmd = [ordered]@{
        action    = $Action
        payload   = $Payload
        requestId = $requestId
        timestamp = (Get-Date).ToString('o')
    }
    $cmdJson = $cmd | ConvertTo-Json -Compress

    $mtx = New-Object System.Threading.Mutex($false, $script:CommandMutexName)
    try {
        if (-not $mtx.WaitOne(3000)) { throw 'Could not acquire command mutex' }
        $cmdJson | Set-Content $script:CommandFile -Encoding UTF8
    } finally {
        try { $mtx.ReleaseMutex() } catch {}
        $mtx.Dispose()
    }

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $script:ResponseFile) {
            $resp = Get-Content $script:ResponseFile -Raw | ConvertFrom-Json
            if ($resp.requestId -eq $requestId) {
                Remove-Item $script:ResponseFile -Force -ErrorAction SilentlyContinue
                return $resp
            }
        }
        Start-Sleep -Milliseconds 200
    }
    throw "Command '$Action' timed out after $TimeoutSeconds seconds"
}

Export-ModuleMember -Function Get-ShadowStatus, Set-ShadowStatus, Send-ShadowCommand
