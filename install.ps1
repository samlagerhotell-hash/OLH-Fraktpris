# Installs OLH Fraktpris for this Windows user: copies Fraktpris.ps1 to %LOCALAPPDATA%\OLH Fraktpris
# (it updates itself from GitHub after that),
# puts an "OLH Fraktpris" shortcut on the desktop and asks once for the Profrakt API key
# (saved as the user setting PROFRAKT_API_KEY, never written to a file). No admin needed.
#   -Target / -Desktop / -SkipKey are for testing only.
param([string]$Target = (Join-Path $env:LOCALAPPDATA 'OLH Fraktpris'),
      [string]$Desktop = [Environment]::GetFolderPath('Desktop'),
      [switch]$SkipKey)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $Target | Out-Null
Copy-Item -Path (Join-Path $PSScriptRoot 'Fraktpris.ps1') -Destination $Target -Force
Write-Host "Kopiert til $Target"

$w = New-Object -ComObject WScript.Shell
$lnk = $w.CreateShortcut((Join-Path $Desktop 'OLH Fraktpris.lnk'))
$lnk.TargetPath = Join-Path $env:WINDIR 'System32\conhost.exe'
$lnk.Arguments = '--headless powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + (Join-Path $Target 'Fraktpris.ps1') + '"'
$lnk.WorkingDirectory = $Target
$lnk.IconLocation = (Join-Path $env:WINDIR 'System32\shell32.dll') + ',43'
$lnk.Description = 'Fraktpris fra Profrakt (Bring/PostNord)'
$lnk.Save()
Write-Host 'Snarvei "OLH Fraktpris" lagt på skrivebordet.'

if (-not $SkipKey) {
    $have = [Environment]::GetEnvironmentVariable('PROFRAKT_API_KEY', 'User')
    $ask = $true
    if ($have) { $ask = (Read-Host 'Profrakt-nøkkel er allerede lagret. Bytte den? (j/n)') -match '^[jJyY]' }
    if ($ask) {
        Write-Host 'Lim inn Profrakt API-nøkkelen (Profrakt > Innstillinger > API). Den vises ikke mens du limer inn.'
        $s = Read-Host 'Profrakt API-nøkkel' -AsSecureString
        $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($s)
        try { $k = [Runtime.InteropServices.Marshal]::PtrToStringAuto($b) } finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) }
        if ($k.Trim()) {
            [Environment]::SetEnvironmentVariable('PROFRAKT_API_KEY', $k.Trim(), 'User')
            Write-Host 'Nøkkel lagret.'
        } else { Write-Host 'Ingen nøkkel limt inn. Kjør Install.cmd på nytt når du har den.' }
    }
}
Write-Host ''
Write-Host 'Ferdig. Dobbeltklikk "OLH Fraktpris" på skrivebordet.'
