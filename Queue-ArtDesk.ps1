$ErrorActionPreference = 'Stop'
$artHost = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
$artWorker = Join-Path $PSScriptRoot 'ArtDesk.ps1'
# Return to JBS immediately, so it can close its image handles before verification.
Start-Process -FilePath $artHost -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-WindowStyle','Hidden','-File',('"' + $artWorker + '"'),'-RecordOnly')
