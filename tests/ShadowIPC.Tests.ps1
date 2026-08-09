BeforeAll {
    . "$PSScriptRoot\..\components\ShadowIPC.ps1"
    $script:ShadowStatusFile = "TestDrive:\status.json"
}

Describe "ShadowIPC" {
    It "Sets and gets status for a component" {
        Set-ShadowStatus -Component "Test" -Status "Running" -Data @{ foo = "bar" }
        $s = Get-ShadowStatus -Component "Test"
        $s.status | Should -Be "Running"
        $s.data.foo | Should -Be "bar"
    }
    It "Returns null for missing component" {
        Get-ShadowStatus -Component "NonExistent" | Should -BeNullOrEmpty
    }
    It "Updates existing component without destroying others" {
        Set-ShadowStatus -Component "A" -Status "Running"
        Set-ShadowStatus -Component "B" -Status "Stopped"
        $all = Get-ShadowStatus
        $all.A.status | Should -Be "Running"
        $all.B.status | Should -Be "Stopped"
    }
}
