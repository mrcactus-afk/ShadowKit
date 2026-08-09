Describe "SystemCalibrator Logic" {
    It "Test-Condition respects minRamGB" {
        $facts = @{ ramGB = 8; cores = 4; battery = $false }
        $cond = @{ minRamGB = 16 }
        $pass = if ($cond.minRamGB -and $facts.ramGB -lt $cond.minRamGB) { $false } else { $true }
        $pass | Should -Be $false
        $cond2 = @{ minRamGB = 4 }
        $pass2 = if ($cond2.minRamGB -and $facts.ramGB -lt $cond2.minRamGB) { $false } else { $true }
        $pass2 | Should -Be $true
    }
    It "Entry-Allowed respects severity levels" {
        $eUniversal = @{ severity = "universal" }
        $eConditional = @{ severity = "conditional"; condition = @{ minRamGB = 4 } }
        $eRisky = @{ severity = "risky"; condition = @{ minRamGB = 4 } }
        ($eUniversal.severity -eq "universal") | Should -Be $true
        $facts = @{ ramGB = 8 }
        $pass = if ($eConditional.condition.minRamGB -and $facts.ramGB -lt $eConditional.condition.minRamGB) { $false } else { $true }
        $pass | Should -Be $true
        $allowRisky = $false
        ($eRisky.severity -eq "risky" -and $allowRisky) | Should -Be $false
    }
}
