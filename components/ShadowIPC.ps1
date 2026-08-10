$script:ShadowStatusFile = "$PSScriptRoot\..\state\status.json"
function Get-ShadowMutex { [System.Threading.Mutex]::new($false, "Global\ShadowKitStatusMutex") }

function Set-ShadowStatus {
    param([string]$Component, [string]$Status, [hashtable]$Data = @{})
    $m = Get-ShadowMutex
    try {
        if ($m.WaitOne(3000)) {
            $parent = Split-Path $script:ShadowStatusFile
            if (-not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            $dict = @{}
            if (Test-Path $script:ShadowStatusFile) {
                $raw = Get-Content $script:ShadowStatusFile -Raw
                if (-not [string]::IsNullOrWhiteSpace($raw)) {
                    $jsonObj = $raw | ConvertFrom-Json
                    if ($jsonObj) {
                        foreach ($prop in $jsonObj.psobject.properties) { $dict[$prop.Name] = $prop.Value }
                    }
                }
            }
            $dict[$Component] = @{ status = $Status; pid = $PID; updated = (Get-Date -Format "o"); data = $Data }
            $tmp = "$script:ShadowStatusFile.tmp"
            $dict | ConvertTo-Json -Depth 5 | Set-Content -Path $tmp -Encoding UTF8
            Move-Item -Path $tmp -Destination $script:ShadowStatusFile -Force
        }
    } finally { $m.ReleaseMutex(); $m.Dispose() }
}

function Get-ShadowStatus {
    param([string]$Component)
    if (-not (Test-Path $script:ShadowStatusFile)) { return $null }
    $raw = Get-Content $script:ShadowStatusFile -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $jsonObj = $raw | ConvertFrom-Json
    if (-not $jsonObj) { return $null }
    if ($Component) { return $jsonObj.$Component } else { return $jsonObj }
}



# ---- Command sender (if not already defined) ----
if (-not (Get-Command Send-ShadowCommand -ErrorAction SilentlyContinue)) {
    function Send-ShadowCommand {
        param([string]$Command, [int]$TimeoutMs = 5000)
        $pipeName = "ShadowKit-Control"
        try {
            $pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", $pipeName, [System.IO.Pipes.PipeDirection]::InOut)
            $pipe.Connect($TimeoutMs)
            $writer = New-Object System.IO.StreamWriter($pipe)
            $writer.AutoFlush = $true
            $writer.WriteLine($Command)
            $reader = New-Object System.IO.StreamReader($pipe)
            $response = $reader.ReadLine()
            $pipe.Close(); $pipe.Dispose()
            return $response | ConvertFrom-Json
        } catch {
            return @{ error = $_.Exception.Message; success = $false }
        }
    }
}
