# MHServerEmu stays blocked reading the console after "!server shutdown", so send one more line once it has shut down.
$psi = New-Object System.Diagnostics.ProcessStartInfo (Join-Path $PSScriptRoot 'MHServerEmu\MHServerEmu.exe')
$psi.WorkingDirectory = Join-Path $PSScriptRoot 'MHServerEmu'
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$server = [System.Diagnostics.Process]::Start($psi)

# Async read so the wrapper also exits when the server exits on its own.
$console = New-Object System.IO.StreamReader([Console]::OpenStandardInput())
$read = $console.ReadLineAsync()
while (-not $server.HasExited) {
    if (-not $read.Wait(500)) { continue }
    $line = $read.Result
    if ($null -eq $line) { $server.WaitForExit(); break }
    $server.StandardInput.WriteLine($line)
    if ($line.Trim() -eq '!server shutdown') { Start-Sleep -Seconds 2; $server.StandardInput.WriteLine() }
    $read = $console.ReadLineAsync()
}
exit $server.ExitCode
