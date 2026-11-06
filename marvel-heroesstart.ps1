param([string]$WebServer = 'false', [int]$HttpPort = 80, [int]$HttpsPort = 443, [int]$WebPort = 8180, [string]$WebAddress = 'localhost', [string]$PublicAddress = '127.0.0.1')

# Optional Caddy web server: SiteConfig.xml over HTTP and an HTTPS proxy to the web frontend, as the client needs.
$caddy = $null
if ($WebServer -eq 'true') {
    $dir = Join-Path $PSScriptRoot 'caddy'
    $www = Join-Path $dir 'www'
    New-Item -ItemType Directory -Force -Path $www | Out-Null
    $site = [IO.File]::ReadAllText((Join-Path $dir 'SiteConfig.template.xml'))
    $site = $site -replace 'name="AuthServerAddress" value="[^"]*"', "name=`"AuthServerAddress`" value=`"$PublicAddress`""
    # Port-patched clients use this; stock clients always use 443.
    $site = $site -replace 'name="AuthServerPort" value="[^"]*"', "name=`"AuthServerPort`" value=`"$HttpsPort`""
    [IO.File]::WriteAllText((Join-Path $www 'SiteConfig.xml'), $site)
    $d = $dir -replace '\\', '/'
    @"
{
	admin off
	persist_config off
	storage file_system "$d/data"
	http_port $HttpPort
	https_port $HttpsPort
	default_sni $PublicAddress
	skip_install_trust
	auto_https disable_redirects
}
http://:$HttpPort {
	root * "$d/www"
	file_server
}
https://${PublicAddress}:$HttpsPort {
	tls internal
	reverse_proxy ${WebAddress}:$WebPort {
		header_up Host ${WebAddress}:$WebPort
	}
}
"@ | Set-Content -Path (Join-Path $dir 'Caddyfile') -Encoding Ascii
    $caddy = Start-Process -FilePath (Join-Path $dir 'caddy.exe') -ArgumentList 'run', '--config', "`"$dir\Caddyfile`"", '--adapter', 'caddyfile' `
        -WorkingDirectory $dir -NoNewWindow -PassThru -RedirectStandardError (Join-Path $dir 'caddy.log') -RedirectStandardOutput (Join-Path $dir 'caddy.out.log')
    Start-Sleep -Seconds 2
    if ($caddy.HasExited) {
        Write-Output "Built-in web server failed to start (ports $HttpPort/$HttpsPort in use?). See caddy\caddy.log:"
        Get-Content (Join-Path $dir 'caddy.log') -Tail 3 | Write-Output
    } else {
        Write-Output "Built-in web server running: http://${PublicAddress}:$HttpPort/SiteConfig.xml, https port $HttpsPort"
    }
}

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
if ($caddy -and -not $caddy.HasExited) { $caddy.Kill() }
exit $server.ExitCode
