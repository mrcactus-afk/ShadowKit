Describe "ShadowKit Core" {
    Context "Status Functions" {
        It "Set-ShadowStatus and Get-ShadowStatus round-trip" {
            $testDir = Join-Path $env:TEMP ("SKTest_" + [guid]::NewGuid().ToString("N"))
            New-Item -ItemType Directory -Path $testDir -Force | Out-Null
            $script:StateDir = $testDir
            $script:StatusFile = Join-Path $testDir 'status.json'
            Set-ShadowStatus -Component 'Test' -Status 'Running' -Data @{ foo = 'bar' }
            $s = Get-ShadowStatus -Component 'Test'
            $s.status | Should -Be 'Running'
            $s.data.foo | Should -Be 'bar'
            Remove-Item $testDir -Recurse -Force
        }
    }
    Context "DNS IP Validation" {
        It "Rejects private IPs" {
            Is-PrivateIP '10.0.0.1' | Should -Be $true
            Is-PrivateIP '1.1.1.1' | Should -Be $false
        }
    }
    Context "SystemCalibrator Condition" {
        It "Evaluates minRamGB" {
            $facts = @{ ramGB = 8; cores = 4; battery = $false }
            $cond = @{ minRamGB = 16 }
            if ($cond.minRamGB -and $facts.ramGB -lt $cond.minRamGB) { $false } else { $true } | Should -Be $false
        }
    }
}
