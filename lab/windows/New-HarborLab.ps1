<#
.SYNOPSIS
    Creates the harbor-airgap-kit lab on this Windows machine.

.DESCRIPTION
    Installs a separate WSL distribution (AlmaLinux 9 by default, named
    harbor-lab) and turns on systemd in it. It then copies this repository to
    /opt/harbor-airgap-kit inside it and runs lab/bootstrap.sh, which installs
    the packages and builds the lab: a CA, Nexus in Podman, and Nexus's
    repositories and accounts.
    Your other WSL distributions are not touched. Run it again at any time: it
    reuses the distribution and keeps the lab's vault, runtime and last publish.

.PARAMETER Demo
    Also run the whole pipeline end to end (make lab-demo): build the
    transfer, publish it to Nexus, build Harbor, load the Broadcom bundles,
    verify.

.PARAMETER Runtime
    With -Demo: the container runtime Harbor runs on, podman (the default) or
    docker (Docker CE, from the transfer). Harbor moves runtimes with its data.

.PARAMETER Recreate
    Delete the existing harbor-lab distribution first, and everything in it.

.PARAMETER RepoPath
    The harbor-airgap-kit folder to copy into the lab. Defaults to the folder
    this script is in (two levels up from lab\windows).

.EXAMPLE
    PowerShell -ExecutionPolicy Bypass -File .\lab\windows\New-HarborLab.ps1 -Demo

.EXAMPLE
    PowerShell -ExecutionPolicy Bypass -File .\lab\windows\New-HarborLab.ps1 -Demo -Runtime docker
#>
[CmdletBinding()]
param(
    [string] $Name = 'harbor-lab',
    [string] $Distribution = 'AlmaLinux-9',
    [string] $Location = (Join-Path $env:LOCALAPPDATA 'harbor-lab'),
    [string] $RepoPath,
    [switch] $Demo,
    [ValidateSet('podman', 'docker')] [string] $Runtime,
    [switch] $Recreate
)

$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'                         # wsl.exe prints UTF-8 rather than UTF-16
$LinuxRepo = '/opt/harbor-airgap-kit'

# Windows PowerShell 5.1 leaves $PSScriptRoot empty while it fills in parameter
# defaults, so the repo folder gets worked out here instead.
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $RepoPath) { $RepoPath = (Resolve-Path (Join-Path $ScriptDir '..\..')).Path }

function Write-Step([string] $Text) { Write-Host "`n==> $Text" -ForegroundColor Cyan }

function Invoke-Lab {
    # Runs a command in the lab distribution as root; stops on failure. No param()
    # block on purpose: every argument, -c included, goes straight to the command.
    & wsl.exe -d $Name -u root -- @args
    if ($LASTEXITCODE -ne 0) { throw "Failed in ${Name} (exit $LASTEXITCODE): $($args -join ' ')" }
}

if ($Runtime -and -not $Demo) { throw '-Runtime goes with -Demo: it chooses the runtime the demo builds Harbor on' }

Write-Step 'Checking WSL'
try { $versionText = (& wsl.exe --version) -join "`n" } catch { $versionText = '' }
if ($versionText -notmatch 'WSL[^:\r\n]*:\s*(\d+)\.(\d+)\.(\d+)') {
    throw 'WSL is missing or too old for this script. Install or update it: wsl --install, or wsl --update'
}
$wslVersion = [version]"$($Matches[1]).$($Matches[2]).$($Matches[3])"
if ($wslVersion -lt [version]'2.4.4') { throw "WSL $wslVersion is too old (2.4.4 or later is needed). Run: wsl --update" }
Write-Host "WSL $wslVersion"
if (-not (Test-Path (Join-Path $RepoPath 'lab\bootstrap.sh'))) { throw "$RepoPath is not the harbor-airgap-kit folder" }

$existing = @(& wsl.exe --list --quiet) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
if ($existing -contains $Name -and $Recreate) {
    Write-Step "Deleting the existing $Name distribution"
    & wsl.exe --unregister $Name
    if ($LASTEXITCODE -ne 0) { throw "wsl --unregister $Name failed" }
    $existing = @($existing | Where-Object { $_ -ne $Name })
}
if ($existing -contains $Name) {
    Write-Host "$Name already exists: reusing it (add -Recreate to start from scratch)"
} else {
    Write-Step "Installing $Distribution as $Name in $Location"
    & wsl.exe --install $Distribution --name $Name --location $Location --no-launch
    if ($LASTEXITCODE -ne 0) { throw "wsl --install failed. 'wsl --list --online' shows the distributions on offer." }
}

Write-Step 'Turning on systemd, signing in as root, keeping /etc/hosts'
Invoke-Lab sh -c "printf '[boot]\nsystemd=true\n\n[user]\ndefault=root\n\n[network]\ngenerateHosts=false\n' > /etc/wsl.conf"
# The distribution asks for a user account on its first interactive shell unless
# UID 1000 exists. The lab signs in as root, so give it one and skip the question.
Invoke-Lab sh -c 'getent passwd 1000 >/dev/null || useradd -m -u 1000 -G wheel labuser'
& wsl.exe --terminate $Name | Out-Null
Invoke-Lab sh -c 'systemctl is-system-running --wait >/dev/null 2>&1; grep -qx systemd /proc/1/comm'

# Files under C:\ show up in WSL as writable by everyone, and Ansible ignores
# ansible.cfg in a world-writable folder, so the copy gets normal permissions.
Write-Step "Copying $RepoPath to $LinuxRepo (keeping the lab's vault, runtime and last publish)"
& wsl.exe -d $Name -u root --cd "$RepoPath" -- sh -c (
    "mkdir -p $LinuxRepo && tar -cf - --exclude=./.vault_pass --exclude=./inventories/lab/group_vars/all/vault.yml " +
    "--exclude=./inventories/lab/group_vars/registry/runtime.yml " +
    "--exclude=./inventories/lab/group_vars/registry/harbor_artifacts.yml " +
    "--exclude=./collections --exclude=./dist --exclude=./.venv . | tar -C $LinuxRepo -xf - && chmod -R go-w $LinuxRepo")
if ($LASTEXITCODE -ne 0) { throw 'Copying the repository failed' }

Write-Step 'Setting up the lab: packages, Ansible collections, CA, Nexus (about 10 minutes the first time)'
Invoke-Lab bash "$LinuxRepo/lab/bootstrap.sh"

if ($Demo) {
    Write-Step 'Running the pipeline end to end (make lab-demo)'
    if ($Runtime) { Invoke-Lab make -C $LinuxRepo lab-demo "RUNTIME=$Runtime" }
    else { Invoke-Lab make -C $LinuxRepo lab-demo }
}

# WSL would stop the lab 15 seconds after this script ends, and Harbor with it.
Write-Step 'Keeping the lab running in the background'
& (Join-Path $ScriptDir 'Start-HarborLab.ps1') -Name $Name

Write-Step 'Done'
Write-Host @"
  A shell in the lab:           wsl -d $Name
  Run the whole pipeline:       wsl -d $Name -- make -C $LinuxRepo lab-demo
  The same on Docker CE:        wsl -d $Name -- make -C $LinuxRepo lab-demo RUNTIME=docker
  Where everything is:          wsl -d $Name -- make -C $LinuxRepo lab-info
  Stop the lab:                 wsl --terminate $Name
  Start it again later:         PowerShell -ExecutionPolicy Bypass -File .\lab\windows\Start-HarborLab.ps1
  Remove the lab completely:    PowerShell -ExecutionPolicy Bypass -File .\lab\windows\Remove-HarborLab.ps1
"@
