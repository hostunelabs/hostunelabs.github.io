# ============================================================
# SMB Compatibility Fix for Windows 10 / 11
# Run PowerShell as Administrator
# ============================================================

Write-Host "Applying SMB compatibility settings..." -ForegroundColor Cyan

# -------------------------------------------------------
# Allow insecure guest logons
# (Required for NAS/devices that use guest access)
# -------------------------------------------------------

New-Item `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" `
    -Force | Out-Null

Set-ItemProperty `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanWorkstation\Parameters" `
    -Name "AllowInsecureGuestAuth" `
    -Type DWord `
    -Value 1

# -------------------------------------------------------
# Disable SMB client security signature requirement
# (Allows connecting to devices that don't support signing)
# -------------------------------------------------------

Set-SmbClientConfiguration `
    -RequireSecuritySignature $false `
    -EnableSecuritySignature $false `
    -Force

# -------------------------------------------------------
# Disable SMB server security signature requirement
# (Allows other devices to connect to this PC without signing)
# -------------------------------------------------------

Set-SmbServerConfiguration `
    -RequireSecuritySignature $false `
    -EnableSecuritySignature $false `
    -Force

# -------------------------------------------------------
# Done
# -------------------------------------------------------

Write-Host ""
Write-Host "Completed. Restart Windows for all changes to take effect." -ForegroundColor Green
