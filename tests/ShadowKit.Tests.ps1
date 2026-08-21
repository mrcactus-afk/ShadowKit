# ShadowKit.Tests.ps1 - Simple unit tests (Pester 3 compatible)
Describe "ShadowKit Helpers" {
    Context "Is-PrivateIP" {
        It "Detects private IPv4 ranges" {
            $ip = '10.0.0.1'
            ($ip -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)') | Should Be $true
        }
        It "Accepts public IPs" {
            $ip = '1.1.1.1'
            ($ip -match '^(10\.|192\.168\.|172\.(1[6-9]|2[0-9]|3[01])\.)') | Should Be $false
        }
    }
    Context "Condition evaluation" {
        It "Respects minRamGB" {
            $facts = @{ ramGB = 8; cores = 4; battery = $false }
            $cond = @{ minRamGB = 16 }
            $result = if ($cond.minRamGB -and $facts.ramGB -lt $cond.minRamGB) { $false } else { $true }
            $result | Should Be $false
        }
    }
}
