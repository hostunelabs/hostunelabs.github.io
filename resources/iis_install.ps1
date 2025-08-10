
# --- PRE-FLIGHT CHECKS ---

# Step 1: Verify Administrator Privileges
Write-Host "Step 1: Checking for Administrator privileges..." -ForegroundColor Yellow
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "Administrator privileges are required to run this script. Please right-click the script and select 'Run as Administrator'."
    # Pause to allow the user to read the error message before the window closes.
    Read-Host "Press Enter to exit."
    exit 1
}
Write-Host "Administrator privileges confirmed." -ForegroundColor Green

# Step 2: User Confirmation to Proceed
Write-Host "`nThis script will perform the following actions:" -ForegroundColor Cyan
Write-Host " - Enable IIS Features with hosting bundle" -ForegroundColor Cyan
Write-Host " - Download and set up the TuneAppApi website" -ForegroundColor Cyan

$confirmation = Read-Host -Prompt "Do you want to continue? (Y/N)"
if ($confirmation -ne 'Y') {
    Write-Host "Operation cancelled by the user." -ForegroundColor Red
    exit
}

# --- SCRIPT EXECUTION ---

# Set execution policy if needed for the current user session
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force

Write-Host "`nStarting IIS Configuration Script..." -ForegroundColor Green

# Define script variables
$dotnetHostingUrl = "https://dotnetcli.azureedge.net/dotnet/aspnetcore/Runtime/8.0.0/dotnet-hosting-8.0.0-win.exe"
$dotnetInstallerPath = "$env:TEMP\dotnet-hosting-8.0.0-win.exe"
$tuneAppUrl = "http://www.hostune.in/resources/TuneAppApi.zip"
$zipPath = "$env:TEMP\TuneAppApi.zip"
$extractPath = "D:\Hostune\API\TuneAppApi"
$mediaPath = "D:\Media\Pics"
$certName = "htncert"
$appPoolName = "TuneAppApiPool"
$siteName = "TuneAppApi"
$httpPort = 62001
$httpsPort = 62000
$iisResetPath = "$env:SystemRoot\System32\inetsrv\iisreset.exe"

# Step 3: Enable IIS Features (MUST be done BEFORE installing the hosting bundle)
Write-Host "`nStep 3: Enabling IIS Features..." -ForegroundColor Yellow
Import-Module ServerManager -ErrorAction SilentlyContinue

$iisFeatures = @(
    "IIS-WebServerRole",
    "IIS-WebServer",
    "IIS-CommonHttpFeatures",
    "IIS-HttpErrors",
    "IIS-HttpLogging",
    "IIS-RequestFiltering",
    "IIS-StaticContent",
    "IIS-DefaultDocument",
    "IIS-DirectoryBrowsing",
    "IIS-ASPNET45",
    "IIS-NetFxExtensibility45",
    "IIS-ISAPIExtensions",
    "IIS-ISAPIFilter",
    "IIS-HttpCompressionStatic",
    "IIS-WebServerManagementTools",
    "IIS-ManagementConsole"
)

foreach ($feature in $iisFeatures) {
    try {
        if (-not (Get-WindowsOptionalFeature -Online -FeatureName $feature).State -eq 'Enabled') {
            Enable-WindowsOptionalFeature -Online -FeatureName $feature -All -NoRestart
            Write-Host "Enabled feature: $feature" -ForegroundColor Green
        } else {
            Write-Host "Feature '$feature' is already enabled." -ForegroundColor Cyan
        }
    } catch {
        Write-Warning "Could not enable feature: $feature. Error: $($_.Exception.Message)"
    }
}

# Step 4: Download and Install/Repair .NET 8 Hosting Bundle
Write-Host "`nStep 4: Downloading .NET 8 Hosting Bundle..." -ForegroundColor Yellow
try {
    Invoke-WebRequest -Uri $dotnetHostingUrl -OutFile $dotnetInstallerPath -UseBasicParsing
    Write-Host "Download completed successfully." -ForegroundColor Green
    
    Write-Host "Repairing/Installing .NET 8 Hosting Bundle to ensure IIS module is registered..." -ForegroundColor Yellow
    # Using /repair ensures that if the bundle is already installed, its components
    # (like the ASP.NET Core Module V2) are correctly registered with IIS.
    Start-Process -FilePath $dotnetInstallerPath -ArgumentList "/repair", "/quiet", "/norestart" -Wait
    Write-Host ".NET 8 Hosting Bundle installation/repair completed." -ForegroundColor Green

} catch {
    Write-Error "Failed to download or install .NET Hosting Bundle: $($_.Exception.Message)"
    exit 1
}

# Import the module now that IIS features are enabled
Import-Module WebAdministration -ErrorAction Stop

# Step 5: Create Self-Signed Certificate
Write-Host "`nStep 5: Creating Self-Signed Certificate '$certName'..." -ForegroundColor Yellow
try {
    $existingCert = Get-ChildItem "cert:\LocalMachine\My" | Where-Object { $_.FriendlyName -eq $certName }
    if ($existingCert) {
        Write-Host "Removing existing certificate with FriendlyName '$certName'." -ForegroundColor Yellow
        Remove-Item -Path $existingCert.PSPath -Force
    }

    $cert = New-SelfSignedCertificate `
        -DnsName "localhost", "127.0.0.1" `
        -CertStoreLocation "cert:\LocalMachine\My" `
        -FriendlyName $certName `
        -KeyExportPolicy Exportable `
        -KeyLength 2048 `
        -KeyAlgorithm RSA `
        -HashAlgorithm SHA256 `
        -KeyUsage KeyEncipherment, DigitalSignature `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.1") `
        -NotAfter (Get-Date).AddYears(5)

    $certThumbprint = $cert.Thumbprint
    
    $rootStore = Get-Item "cert:\LocalMachine\Root"
    $rootStore.Open("ReadWrite")
    $rootStore.Add($cert)
    $rootStore.Close()
    
    Write-Host "Self-signed certificate '$certName' created successfully with thumbprint: $certThumbprint" -ForegroundColor Green
} catch {
    Write-Error "Failed to create self-signed certificate: $($_.Exception.Message)"
    exit 1
}

# Step 6: Download, Extract, and Configure Application
Write-Host "`nStep 6: Downloading and configuring '$siteName'..." -ForegroundColor Yellow
try {
    if (-not (Test-Path -Path $extractPath)) {
        New-Item -ItemType Directory -Path $extractPath -Force | Out-Null
    }
    
    Invoke-WebRequest -Uri $tuneAppUrl -OutFile $zipPath -UseBasicParsing
    Write-Host "Download completed successfully." -ForegroundColor Green
    
    Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force
    Write-Host "'$siteName' extracted to: $extractPath" -ForegroundColor Green

    $sourceConfigFile = "$extractPath\myapiconfig - Copy.json"
    $destinationConfigFile = "$extractPath\myapiconfig.json"
    if (Test-Path $sourceConfigFile) {
        Rename-Item -Path $sourceConfigFile -NewName $destinationConfigFile -Force
        Write-Host "Renamed configuration file to '$($destinationConfigFile.Split('\')[-1])'." -ForegroundColor Green
    } else {
        Write-Warning "Source configuration file not found at '$sourceConfigFile'. Skipping rename."
    }
    
} catch {
    Write-Error "Failed to download or extract '$siteName': $($_.Exception.Message)"
    exit 1
} finally {
    if(Test-Path $zipPath) {
        Remove-Item $zipPath -Force -ErrorAction SilentlyContinue
    }
}

# Step 7: Create Media Directory
Write-Host "`nStep 7: Creating Media Directory..." -ForegroundColor Yellow
try {
    if (-not (Test-Path -Path $mediaPath)) {
        New-Item -ItemType Directory -Path $mediaPath -Force | Out-Null
        Write-Host "Created directory: $mediaPath" -ForegroundColor Green
    } else {
        Write-Host "Directory '$mediaPath' already exists." -ForegroundColor Cyan
    }
} catch {
    Write-Error "Failed to create Media Pics directory: $($_.Exception.Message)"
    exit 1
}

# Step 8: Create IIS Application Pool
Write-Host "`nStep 8: Creating Application Pool '$appPoolName'..." -ForegroundColor Yellow
try {
    if (Get-IISAppPool -Name $appPoolName -ErrorAction SilentlyContinue) {
        Remove-WebAppPool -Name $appPoolName
        Write-Host "Removed existing application pool: $appPoolName" -ForegroundColor Yellow
    }
    
    New-WebAppPool -Name $appPoolName
    Set-ItemProperty -Path "IIS:\AppPools\$appPoolName" -Name "managedRuntimeVersion" -Value ""
    Set-ItemProperty -Path "IIS:\AppPools\$appPoolName" -Name "processModel.identityType" -Value "ApplicationPoolIdentity"
    
    Write-Host "Application pool '$appPoolName' created successfully." -ForegroundColor Green
} catch {
    Write-Error "Failed to create application pool: $($_.Exception.Message)"
    exit 1
}

# Step 9: Create IIS Website
Write-Host "`nStep 9: Creating IIS Website '$siteName'..." -ForegroundColor Yellow
try {
    if (Get-Website -Name $siteName -ErrorAction SilentlyContinue) {
        Remove-Website -Name $siteName -Confirm:$false
        Write-Host "Removed existing website: $siteName" -ForegroundColor Yellow
    }
    
    New-Website -Name $siteName -Port $httpPort -PhysicalPath $extractPath -ApplicationPool $appPoolName
    
    New-WebBinding -Name $siteName -Protocol "https" -Port $httpsPort -SslFlags 0
    
    (Get-WebBinding -Name $siteName -Protocol "https" -Port $httpsPort).AddSslCertificate($certThumbprint, "my")
    
    Write-Host "Website '$siteName' created successfully with:" -ForegroundColor Green
    Write-Host "  - HTTP Port: $httpPort" -ForegroundColor Green
    Write-Host "  - HTTPS Port: $httpsPort" -ForegroundColor Green
    Write-Host "  - Physical Path: $extractPath" -ForegroundColor Green
    Write-Host "  - SSL Certificate: $certName ($certThumbprint)" -ForegroundColor Green
    
} catch {
    Write-Error "Failed to create IIS website: $($_.Exception.Message)"
    exit 1
}

# Step 10: Set Permissions
Write-Host "`nStep 10: Setting Folder Permissions..." -ForegroundColor Yellow
try {
    $acl = Get-Acl $extractPath
    $appPoolIdentity = "IIS AppPool\$appPoolName"
    $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule($appPoolIdentity, "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
    $acl.SetAccessRule($accessRule)
    Set-Acl -Path $extractPath -AclObject $acl
    
    Write-Host "Permissions for '$appPoolIdentity' set on '$extractPath'." -ForegroundColor Green
} catch {
    Write-Warning "Could not set permissions automatically. You may need to manually grant 'IIS AppPool\$appPoolName' Full Control permissions on the folder '$extractPath'."
}

# Step 11: Final IIS Restart
Write-Host "`nStep 11: Performing Final IIS Restart to apply all changes..." -ForegroundColor Yellow
try {
    if (Test-Path $iisResetPath) {
        Start-Process -FilePath $iisResetPath -ArgumentList "/restart" -Wait
        Write-Host "IIS restarted successfully." -ForegroundColor Green
    } else {
        throw "'iisreset.exe' not found at '$iisResetPath'. The IIS features may not have installed correctly. Cannot restart IIS."
    }
} catch {
    Write-Warning "Could not restart IIS automatically. Please restart it manually from the IIS Manager or by running 'iisreset' in an admin terminal."
}

# Step 12: Clean up temporary files
Write-Host "`nStep 12: Cleaning up temporary files..." -ForegroundColor Yellow
if (Test-Path $dotnetInstallerPath) {
    Remove-Item $dotnetInstallerPath -Force
    Write-Host "Removed installer file." -ForegroundColor Green
}

# --- COMPLETION MESSAGE ---
Write-Host "`n--------------------------------------------------" -ForegroundColor DarkCyan
Write-Host "Configuration completed successfully!" -ForegroundColor Green
Write-Host "Your '$siteName' site is now available at:" -ForegroundColor Cyan
Write-Host "  HTTP:  http://localhost:$httpPort" -ForegroundColor Cyan
Write-Host "  HTTPS: https://localhost:$httpsPort" -ForegroundColor Cyan
Write-Host "`nNOTE: You may need to accept the self-signed certificate warning in your browser." -ForegroundColor Yellow
Write-Host "--------------------------------------------------" -ForegroundColor DarkCyan

# Step 13: Self-destruct
Write-Host "`nStep 13: Deleting the script file itself..." -ForegroundColor Yellow
try {
    # The '$MyInvocation.MyCommand.Path' variable contains the full path to the currently running script.
    Remove-Item -Path $MyInvocation.MyCommand.Path -Force
    Write-Host "Script file has been deleted." -ForegroundColor Green
} catch {
    Write-Warning "Could not delete the script file at '$($MyInvocation.MyCommand.Path)'. You may need to delete it manually."
}
