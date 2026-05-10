# Run PowerShell as Administrator

Write-Host "Applying SMB compatibility settings..." -ForegroundColor Cyan

# -------------------------------------------------------
# Allow insecure guest logons (same as attached .reg file)
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
# -------------------------------------------------------

Set-SmbClientConfiguration `
    -RequireSecuritySignature $false `
    -EnableSecuritySignature $false `
    -Force

# -------------------------------------------------------
# Disable SMB server security signature requirement
# -------------------------------------------------------

Set-SmbServerConfiguration `
    -RequireSecuritySignature $false `
    -EnableSecuritySignature $false `
    -Force

# -------------------------------------------------------
# Optional: Enable SMB1 protocol
# (Needed only for very old NAS/devices)
# -------------------------------------------------------

Enable-WindowsOptionalFeature `
    -Online `
    -FeatureName SMB1Protocol `
    -NoRestart

# -------------------------------------------------------
# Turn OFF Smart App Control
# -------------------------------------------------------

Set-ItemProperty `
    -Path "HKLM:\SYSTEM\CurrentControlSet\Control\CI\Policy" `
    -Name "VerifiedAndReputablePolicyState" `
    -Type DWord `
    -Value 0

Write-Host ""
Write-Host "Completed. Restart Windows for all changes to take effect." -ForegroundColor Green