Describe "ShadowLogger" {
    BeforeAll {
        $script:testDir = Join-Path $env:TEMP ("SKTest_" + [Guid]::NewGuid().ToString("N"))
        New-Item -ItemType Directory -Path $script:testDir -Force | Out-Null
        $script:testLogFile = Join-Path $script:testDir "shadowkit.jsonl"
    }

    AfterAll {
        if (Test-Path $script:testDir) {
            Remove-Item $script:testDir -Recurse -Force
        }
    }

    It "Writes a JSONL entry format" {
        $ts = (Get-Date).ToString("o")
        $entry = "{`"ts`":`"$ts`",`"level`":`"info`",`"module`":`"TestModule`",`"msg`":`"Test message`",`"data`":null}"
        
        [System.IO.File]::WriteAllText($script:testLogFile, $entry, [System.Text.Encoding]::UTF8)
        $lines = [System.IO.File]::ReadAllLines($script:testLogFile)
        $lines.Count | Should -Be 1
        $parsed = $lines[0] | ConvertFrom-Json
        $parsed.msg | Should -Be "Test message"
        $parsed.level | Should -Be "info"
        $parsed.module | Should -Be "TestModule"
    }

    It "Parses log entries correctly" {
        $ts1 = (Get-Date).ToString("o")
        $ts2 = (Get-Date).ToString("o")
        $entry1 = "{`"ts`":`"$ts1`",`"level`":`"error`",`"module`":`"TestModule`",`"msg`":`"Error one`",`"data`":null}"
        $entry2 = "{`"ts`":`"$ts2`",`"level`":`"info`",`"module`":`"OtherModule`",`"msg`":`"Info two`",`"data`":null}"
        
        [System.IO.File]::WriteAllText($script:testLogFile, ($entry1 + "`n" + $entry2), [System.Text.Encoding]::UTF8)
        
        $lines = [System.IO.File]::ReadAllLines($script:testLogFile)
        $parsed = @()
        foreach ($line in $lines) {
            if ($line.Trim()) {
                $parsed += ($line | ConvertFrom-Json)
            }
        }
        $errors = $parsed | Where-Object { $_.level -eq "error" }
        @($errors).Count | Should -BeGreaterThan 0
        $errors[0].msg | Should -Be "Error one"
    }

    It "Handles legacy text format" {
        $legacyLine = "[$(Get-Date)] [ERROR] Legacy error message"
        [System.IO.File]::WriteAllText($script:testLogFile, $legacyLine, [System.Text.Encoding]::UTF8)
        
        $line = [System.IO.File]::ReadAllText($script:testLogFile)
        $line | Should -Match "Legacy error message"
    }
}
