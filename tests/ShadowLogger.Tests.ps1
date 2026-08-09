BeforeAll {
    . "$PSScriptRoot\..\components\ShadowLogger.ps1"
    $script:ShadowKitLogFile = "TestDrive:\shadowkit.jsonl"
    $script:ShadowKitLogDir = "TestDrive:"
}

Describe "ShadowLogger" {
    It "Writes a JSONL entry" {
        Write-ShadowKitLog -Message "Test message" -Level info -Module "TestModule"
        $lines = Get-Content $script:ShadowKitLogFile
        $lines.Count | Should -Be 1
        $entry = $lines[0] | ConvertFrom-Json
        $entry.msg | Should -Be "Test message"
        $entry.level | Should -Be "info"
        $entry.module | Should -Be "TestModule"
    }
    It "Reads back filtered entries" {
        Write-ShadowKitLog -Message "Error one" -Level error -Module "TestModule"
        Write-ShadowKitLog -Message "Info two" -Level info -Module "OtherModule"
        $errors = Read-ShadowKitLog -ErrorsOnly
        $errors.Count | Should -BeGreaterThan 0
        $errors[0].msg | Should -Be "Error one"
    }
}
