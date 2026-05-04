$ProjectRoot = Split-Path -Parent $PSScriptRoot
$ModulePath  = Join-Path $ProjectRoot 'GitEasy.psd1'

Describe 'Get-GELogPath' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:SavedEnv = $env:GITEASY_LOG_PATH
        Remove-Item Env:\GITEASY_LOG_PATH -ErrorAction SilentlyContinue
    }

    AfterEach {
        Remove-Item Env:\GITEASY_LOG_PATH -ErrorAction SilentlyContinue
        if ($null -ne $script:SavedEnv) {
            $env:GITEASY_LOG_PATH = $script:SavedEnv
        }
    }

    It 'returns the LOCALAPPDATA default when nothing else is set' {
        $result = & (Get-Module GitEasy) { Get-GELogPath }
        $expected = Join-Path $env:LOCALAPPDATA 'GitEasy\Logs'
        $result | Should Be $expected
    }

    It 'honors the GITEASY_LOG_PATH environment variable' {
        $env:GITEASY_LOG_PATH = 'C:\test-env-logs'
        $result = & (Get-Module GitEasy) { Get-GELogPath }
        $result | Should Be 'C:\test-env-logs'
    }

    It 'honors the -OverridePath parameter above env and default' {
        $env:GITEASY_LOG_PATH = 'C:\test-env-logs'
        $result = & (Get-Module GitEasy) { Get-GELogPath -OverridePath 'C:\test-explicit' }
        $result | Should Be 'C:\test-explicit'
    }
}

Describe 'Remove-GEOldLog' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:TempDir = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_Logs_" + [guid]::NewGuid().ToString('N'))
        New-Item -Path $script:TempDir -ItemType Directory -Force | Out-Null
    }

    AfterEach {
        Remove-Item -LiteralPath $script:TempDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    It 'removes log files older than the retention threshold' {
        $oldFile = Join-Path $script:TempDir 'old.log'
        $newFile = Join-Path $script:TempDir 'new.log'
        Set-Content -LiteralPath $oldFile -Value 'old' -Encoding UTF8
        Set-Content -LiteralPath $newFile -Value 'new' -Encoding UTF8

        $oldDate = (Get-Date).AddDays(-60)
        (Get-Item -LiteralPath $oldFile).LastWriteTime = $oldDate

        & (Get-Module GitEasy) { param($d) Remove-GEOldLog -Directory $d -RetentionDays 30 } $script:TempDir

        Test-Path -LiteralPath $oldFile | Should Be $false
        Test-Path -LiteralPath $newFile | Should Be $true
    }

    It 'keeps all log files when none are older than the retention threshold' {
        $f1 = Join-Path $script:TempDir 'a.log'
        $f2 = Join-Path $script:TempDir 'b.log'
        Set-Content -LiteralPath $f1 -Value 'a' -Encoding UTF8
        Set-Content -LiteralPath $f2 -Value 'b' -Encoding UTF8

        & (Get-Module GitEasy) { param($d) Remove-GEOldLog -Directory $d -RetentionDays 30 } $script:TempDir

        Test-Path -LiteralPath $f1 | Should Be $true
        Test-Path -LiteralPath $f2 | Should Be $true
    }

    It 'does not throw when the directory does not exist' {
        $missing = Join-Path $script:TempDir 'nope'
        $thrown = $null
        try { & (Get-Module GitEasy) { param($d) Remove-GEOldLog -Directory $d -RetentionDays 30 } $missing } catch { $thrown = $_ }
        $thrown | Should BeNullOrEmpty
    }

    It 'does not touch non-log files' {
        $logFile = Join-Path $script:TempDir 'old.log'
        $txtFile = Join-Path $script:TempDir 'old.txt'
        Set-Content -LiteralPath $logFile -Value 'x' -Encoding UTF8
        Set-Content -LiteralPath $txtFile -Value 'y' -Encoding UTF8

        $oldDate = (Get-Date).AddDays(-60)
        (Get-Item -LiteralPath $logFile).LastWriteTime = $oldDate
        (Get-Item -LiteralPath $txtFile).LastWriteTime = $oldDate

        & (Get-Module GitEasy) { param($d) Remove-GEOldLog -Directory $d -RetentionDays 30 } $script:TempDir

        Test-Path -LiteralPath $logFile | Should Be $false
        Test-Path -LiteralPath $txtFile | Should Be $true
    }
}

Describe 'Show-Diagnostic' {
    BeforeAll {
        Remove-Module GitEasy -Force -ErrorAction SilentlyContinue
        Import-Module $ModulePath -Force
    }

    BeforeEach {
        $script:SavedEnv = $env:GITEASY_LOG_PATH

        $script:TempLogs = Join-Path ([System.IO.Path]::GetTempPath()) ("GitEasy_Diag_" + [guid]::NewGuid().ToString('N'))
        New-Item -Path $script:TempLogs -ItemType Directory -Force | Out-Null

        $env:GITEASY_LOG_PATH = $script:TempLogs
    }

    AfterEach {
        Remove-Item Env:\GITEASY_LOG_PATH -ErrorAction SilentlyContinue
        if ($null -ne $script:SavedEnv) {
            $env:GITEASY_LOG_PATH = $script:SavedEnv
        }
        Remove-Item -LiteralPath $script:TempLogs -Recurse -Force -ErrorAction SilentlyContinue
    }

    It '-List returns objects with Name, LastWritten, and SizeKB when logs exist' {
        $now = Get-Date
        for ($i = 1; $i -le 3; $i++) {
            $path = Join-Path $script:TempLogs ("Save-Work-2026050${i}T120000Z.log")
            Set-Content -LiteralPath $path -Value "log $i" -Encoding UTF8
            (Get-Item -LiteralPath $path).LastWriteTime = $now.AddMinutes(-1 * $i)
        }

        $rows = @(Show-Diagnostic -List)
        $rows.Count | Should Be 3
        ($rows | Select-Object -First 1).PSObject.Properties.Name -contains 'Name'        | Should Be $true
        ($rows | Select-Object -First 1).PSObject.Properties.Name -contains 'LastWritten' | Should Be $true
        ($rows | Select-Object -First 1).PSObject.Properties.Name -contains 'SizeKB'      | Should Be $true
    }

    It '-List -Count limits the number of returned rows' {
        for ($i = 1; $i -le 5; $i++) {
            $path = Join-Path $script:TempLogs ("Save-Work-2026050${i}T120000Z.log")
            Set-Content -LiteralPath $path -Value "log $i" -Encoding UTF8
        }

        $rows = @(Show-Diagnostic -List -Count 2)
        $rows.Count | Should Be 2
    }

    It '-List returns an empty result when the log folder is empty' {
        $rows = @(Show-Diagnostic -List)
        $rows.Count | Should Be 0
    }

    It 'does not throw when the log directory does not exist' {
        Remove-Item -LiteralPath $script:TempLogs -Recurse -Force -ErrorAction SilentlyContinue
        $thrown = $null
        try { Show-Diagnostic -List } catch { $thrown = $_ }
        $thrown | Should BeNullOrEmpty
    }
}
