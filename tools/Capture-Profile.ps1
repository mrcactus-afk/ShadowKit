$profilePath = "C:\ShadowKit\profile.json"
$profile = Get-Content $profilePath -Raw | ConvertFrom-Json
foreach ($e in $profile.entries) {
    switch ($e.type) {
        "service" { $s = Get-Service -Name $e.target -EA SilentlyContinue; if ($s) { $e.value = [string]$s.StartType } }
        "registry" { $v = (Get-ItemProperty -Path $e.target -Name $e.name -EA SilentlyContinue).$e.name; if ($null -ne $v) { $e.value = $v } }
        "power" { $p = powercfg -getactivescheme; if ($p -match '([0-9a-f-]{36})') { $e.value = $matches[1] } }
    }
}
$profile | ConvertTo-Json -Depth 5 | Set-Content $profilePath -Encoding UTF8
"Profile captured from this machine."
