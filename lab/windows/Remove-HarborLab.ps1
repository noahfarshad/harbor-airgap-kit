<#
.SYNOPSIS
    Removes the harbor-airgap-kit lab: the harbor-lab WSL distribution and
    everything in it (Harbor, Nexus, the lab CA, the vault, the transfers).

.EXAMPLE
    PowerShell -ExecutionPolicy Bypass -File .\lab\windows\Remove-HarborLab.ps1
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
param([string] $Name = 'harbor-lab')

$ErrorActionPreference = 'Stop'
$env:WSL_UTF8 = '1'

$existing = @(& wsl.exe --list --quiet) | ForEach-Object { $_.Trim() } | Where-Object { $_ }
if ($existing -notcontains $Name) {
    Write-Host "There is no $Name distribution."
    return
}
if ($PSCmdlet.ShouldProcess($Name, 'Delete the WSL distribution and everything in it')) {
    & wsl.exe --unregister $Name
    if ($LASTEXITCODE -ne 0) { throw "wsl --unregister $Name failed" }
    Write-Host "Removed $Name. Remove any '127.0.0.1 harbor.lab.internal' line you added to the Windows hosts file,"
    Write-Host "and the 'harbor-airgap-kit lab CA' certificate from Current User > Trusted Root (certmgr.msc)."
}
