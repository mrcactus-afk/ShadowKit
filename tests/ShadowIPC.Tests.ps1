Describe "ShadowIPC" {
    BeforeAll {
        $script:testDir = Join-Path $env:TEMP ("SKTest_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
        $script:testStatusFile = Join-Path $script:testDir "status.json"
        
        # Mock the status functions to use test path instead of real path
        function Set-TestShadowStatus {
            param([string]$Component, [string]$Status, [hashtable]$Data = @{})
            $all = @{}
            if (Test-Path $script:testStatusFile) {
                $all = Get-Content $script:testStatusFile -Raw | ConvertFrom-Json
            }
            $all | Add-Member -NotePropertyName $Component -NotePropertyValue @{
                status = $Status
                pid = $PID
                updated = (Get-Date).ToString("o")
                data = $Data
            } -Force
            $all | ConvertTo-Json -Depth 3 | Set-Content $script:testStatusFile -Encoding UTF8
        }
        
        function Get-TestShadowStatus {
            param([string]$Component)
            if (-not (Test-Path $script:testStatusFile)) { return $null }
            $all = Get-Content $script:testStatusFile -Raw | ConvertFrom-Json
            if ([string]::IsNullOrEmpty($Component)) { return $all }
            return $all.$Component
        }
    }

    AfterAll {
        if (Test-Path $script:testDir) {
            Remove-Item $script:testDir -Recurse -Force
        }
    }

    It "Sets and gets status for a component" {
        Set-TestShadowStatus -Component "Test" -Status "Running" -Data @{ foo = "bar" }
        $s = Get-TestShadowStatus -Component "Test"
        $s.status | Should -Be "Running"
        $s.data.foo | Should -Be "bar"
    }

    It "Returns null for missing component" {
        Get-TestShadowStatus -Component "NonExistent" | Should -BeNullOrEmpty
    }

    It "Updates existing component without destroying others" {
        Set-TestShadowStatus -Component "A" -Status "Running"
        Set-TestShadowStatus -Component "B" -Status "Stopped"
        $all = Get-TestShadowStatus
        $all.A.status | Should -Be "Running"
        $all.B.status | Should -Be "Stopped"
    }
}
