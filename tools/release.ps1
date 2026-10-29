# Release a new version: sets $Version in Fraktpris.ps1, then writes version.txt = "<version> <sha256>".
# Installed copies pick it up on their next start once this is pushed to main.
#   powershell -NoProfile -ExecutionPolicy Bypass -File tools\release.ps1 1.2.0
param([Parameter(Mandatory)][string]$NewVersion)
$ErrorActionPreference = 'Stop'
[void][version]$NewVersion
$root = Split-Path $PSScriptRoot -Parent
$app = Join-Path $root 'Fraktpris.ps1'
$text = [IO.File]::ReadAllText($app, [Text.Encoding]::UTF8)
$text = [regex]::Replace($text, "(?m)^\`$Version\s*=\s*'[^']*'", "`$Version    = '$NewVersion'")
[IO.File]::WriteAllText($app, $text, (New-Object Text.UTF8Encoding($true)))
$errs = $null
[void][Management.Automation.Language.Parser]::ParseFile($app, [ref]$null, [ref]$errs)
if ($errs) { throw "Fraktpris.ps1 has parse errors: $($errs[0].Message)" }
$sha = (Get-FileHash $app -Algorithm SHA256).Hash.ToLower()
[IO.File]::WriteAllText((Join-Path $root 'version.txt'), "$NewVersion $sha`n")
"version.txt: $NewVersion $sha"
