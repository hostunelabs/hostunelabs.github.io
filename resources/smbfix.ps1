# ============================================================
# SMB Full Fix for Windows 10 / 11
# Fixes: 0x800704b3 - Network provider not available
# Run PowerShell as Administrator
# ============================================================

Write-Host "Step 1: Starting required network services..." -ForegroundColor Cyan

# Workstation service (core SMB client)
Set-Service -Name LanmanWorkstation -StartupType Automatic
Start-Service -Name LanmanWorkstation -ErrorAction SilentlyContinue

# Server service (allows this PC to share too)
Set-Service -Name LanmanServer -StartupType Automatic
Start-Service -Name LanmanServer -ErrorAction SilentlyContinue

# TCP/IP NetBIOS Helper
Set-Service -Name lmhosts -StartupType Automatic
Start-Service -Name lmhosts -ErrorAction SilentlyContinue

# Network Location Awareness
Set-Service -Name NlaSvc -StartupType Automatic
Start-Service -Name NlaSvc -ErrorAction SilentlyContinue

Write-Host "Step 2: Restoring network provider order in registry..." -ForegroundColor Cyan

# Restore the network provider order (commonly gets corrupted)
$providerPath = "HKLM:\SYSTEM\CurrentControlSet\Control\NetworkProvider\Order"
Set-ItemProperty `
    -Path $providerPath `
    -Name "ProviderOrder" `
    -Value "RDPNP,LanmanWorkstation,webclient" `
    -Type String

Write-Host "Step 3: Applying SMB guest and signing settings..." -ForegroundColor Cyan

# Allow insecure guest logons
New-Item `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" `
    -Force | Out-Null

Set-ItemProperty `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" `
    -Name "AllowInsecureGuestAuth" `
    -Type DWord `
    -Value 1

# Disable SMB client signing requirement
Set-SmbClientConfiguration `
    -RequireSecuritySignature $false `
    -EnableSecuritySignature $false `
    -Force

# Disable SMB server signing requirement
Set-SmbServerConfiguration `
    -RequireSecuritySignature $false `
    -EnableSecuritySignature $false `
    -Force

Write-Host "Step 4: Resetting network stack..." -ForegroundColor Cyan

# Reset Winsock and IP stack
netsh winsock reset | Out-Null
netsh int ip reset | Out-Null

Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host " All done! Please RESTART Windows now." -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
