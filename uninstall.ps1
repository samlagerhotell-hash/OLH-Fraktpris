# Removes OLH Fraktpris for this Windows user: the app folder, the desktop shortcut and, if wanted, the Profrakt key.
param([string]$Target = (Join-Path $env:LOCALAPPDATA 'OLH Fraktpris'),
      [string]$Desktop = [Environment]::GetFolderPath('Desktop'),
      [switch]$KeepKey)

$lnk = Join-Path $Desktop 'OLH Fraktpris.lnk'
if (Test-Path $lnk) { Remove-Item $lnk -Force; Write-Host 'Snarvei fjernet.' }
if (Test-Path $Target) { Remove-Item $Target -Recurse -Force; Write-Host "Fjernet $Target" }
if (-not $KeepKey -and [Environment]::GetEnvironmentVariable('PROFRAKT_API_KEY', 'User')) {
    if ((Read-Host 'Slette lagret Profrakt-nøkkel også? (j/n)') -match '^[jJyY]') {
        [Environment]::SetEnvironmentVariable('PROFRAKT_API_KEY', $null, 'User'); Write-Host 'Nøkkel slettet.'
    }
}
Write-Host 'Ferdig.'
