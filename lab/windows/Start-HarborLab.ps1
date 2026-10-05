<#
.SYNOPSIS
    Starts the harbor-lab distribution and keeps it running in the background.

.DESCRIPTION
    WSL stops a distribution about 15 seconds after the last command attached
    to it finishes, even when services are running under systemd, and Harbor
    and Nexus stop with it. This starts a hidden "sleep infinity" in the lab,
    which keeps it up until you stop it yourself:

        wsl --terminate harbor-lab

    Harbor and Nexus start on their own when the lab boots. If Harbor has been
    built, this waits until it answers.

.EXAMPLE
    PowerShell -ExecutionPolicy Bypass -File .\lab\windows\Start-HarborLab.ps1
#>
[CmdletBinding()]
param([string] $Name = 'harbor-lab')

$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'

$existing = @(& wsl.exe --list --quiet) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
if ($existing -notcontains $Name) {
    throw "There is no $Name distribution yet. Create it with .\lab\windows\New-HarborLab.ps1"
}

# One background "sleep infinity" is enough; only start it if it isn't there.
# (No double quotes inside arguments to wsl.exe: Windows PowerShell 5.1 passes them on mangled.)
$keeper = (& wsl.exe -d $Name -u root -- sh -c 'pgrep -fx ''sleep infinity'' >/dev/null && echo running || echo none') -join ''
if ($keeper -ne 'running') {
    Start-Process -FilePath 'wsl.exe' -ArgumentList '-d', $Name, '-u', 'root', '--exec', 'sleep', 'infinity' -WindowStyle Hidden
}
Write-Host "$Name is running, and stays up until: wsl --terminate $Name"

$built = (& wsl.exe -d $Name -u root -- sh -c 'systemctl is-enabled harbor >/dev/null 2>&1 && echo yes || echo no') -join ''
if ($built -ne 'yes') {
    Write-Host "Harbor isn't built in the lab yet: wsl -d $Name -- make -C /opt/harbor-airgap-kit lab-demo"
    return
}

Write-Host 'Waiting for Harbor to answer (a minute or two after the lab starts)...'
for ($i = 0; $i -lt 60; $i++) {
    $pong = (& wsl.exe -d $Name -u root -- sh -c 'curl -s --max-time 5 https://harbor.lab.internal/api/v2.0/ping || true') -join ''
    if ($pong -eq 'Pong') {
        Write-Host 'Harbor: https://harbor.lab.internal    Nexus: http://localhost:8081'
        return
    }
    Start-Sleep -Seconds 5
}
throw "Harbor didn't answer within 5 minutes. Check it with: wsl -d $Name -- make -C /opt/harbor-airgap-kit verify-registry ENV=lab"
