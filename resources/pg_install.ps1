#region Script Configuration and Parameters
[CmdletBinding(SupportsShouldProcess = $true)]
param (
    [Parameter(Mandatory = $false, HelpMessage = "Root directory for application files.")]
    [string]$AppRootPath = "D:\Hostune",

    [Parameter(Mandatory = $false, HelpMessage = "Directory for PostgreSQL data files.")]
    [string]$PostgresDataPath = "D:\PGDATA",

    [Parameter(Mandatory = $false, HelpMessage = "Installation directory for PostgreSQL binaries.")]
    [string]$PostgresInstallPath = "C:\Program Files\PostgreSQL\18",

    [Parameter(Mandatory = $false, HelpMessage = "Network port for the PostgreSQL server.")]
    [int]$PostgresPort = 61000,

    # --- FIX 1: Changed default download path to D:\Hostune\Tools ---
    [Parameter(Mandatory = $false, HelpMessage = "Path to store downloaded installation files.")]
    [string]$DownloadCachePath = "D:\Hostune\Tools"
)

# --- Static Configuration ---
$Downloads = @{
    "pg_setup" = @{
        "url"       = "https://get.enterprisedb.com/postgresql/postgresql-18.3-3-windows-x64.exe"
        "path"      = Join-Path $DownloadCachePath "pg.exe"
    }
    "odbc_driver" = @{
        "url"       = "https://ftp.postgresql.org/pub/odbc/releases/REL-17_00_0006-mimalloc/psqlodbc_x64.msi"
        "path"      = Join-Path $DownloadCachePath "odbc.msi"
    }
    "db_zip" = @{
        "url"       = "https://www.dropbox.com/scl/fi/op8mlfxbr6qw990hkrz2d/db.zip?rlkey=59dxzmk548odoww0mdrw9l7c9&st=flvfk1ul&dl=1"
        "path"      = Join-Path $DownloadCachePath "db.zip"
        "extractTo" = $DownloadCachePath
    }
    "htnhis_zip" = @{
        "url"       = "https://www.dropbox.com/scl/fi/u4z68wsumdb5nxri2buou/htnhis.zip?rlkey=oqfopebye2qqdd3xp9h43f3jg&st=f4vw14b5&dl=1"
        "path"      = Join-Path $DownloadCachePath "htnhis.zip"
        "extractTo" = "" # Placeholder, will be set dynamically
    }
    "backup_tool_zip" = @{
        "url"       = "https://www.dropbox.com/scl/fi/g7x2uj5tv21zau34m1utd/TuneBackupTool.zip?rlkey=hm6c2agz1k20f7nf2g7gvhm2l&st=gdv5sw1j&dl=1"
        "path"      = Join-Path $DownloadCachePath "TuneBackupTool.zip"
        "extractTo" = "" # Placeholder, will be set dynamically
    }
    "hsql_zip" = @{
        "url"       = "https://www.dropbox.com/scl/fi/l4gtm8n1ipfjneczp6bi4/HSql.zip?rlkey=xdrfb6rovbx1457j1f7rb7jsb&st=svjqa06b&dl=1"
        "path"      = Join-Path $DownloadCachePath "HSql.zip"
        "extractTo" = $env:APPDATA
    }
}
#endregion

#region Helper Functions
function Test-Admin {
    if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]"Administrator")) {
        Write-Error "This script must be run with Administrator privileges."
        Write-Warning "Please right-click the PowerShell script and select 'Run as Administrator'."
        Read-Host "Press Enter to exit"
        exit 1
    }
}

function Get-PostgresCredentials {
    Write-Host "Using hardcoded PostgreSQL 'postgres' superuser password." -ForegroundColor Yellow
    $password = "1234xyzS" | ConvertTo-SecureString -AsPlainText -Force
    return $password
}

function Invoke-Download {
    param($Url, $OutFile)
    $fileName = Split-Path -Leaf $OutFile
    if (Test-Path $OutFile) {
        Write-Host "[$fileName] already exists. Skipping download." -ForegroundColor Gray
        return
    }
    try {
        Write-Host "Downloading [$fileName]..." -ForegroundColor Yellow
        $ProgressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $Url -OutFile $OutFile -ErrorAction Stop
        Write-Host "[$fileName] downloaded successfully." -ForegroundColor Green
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Error "Failed to download [$fileName] from '$Url'. Error: $errorMessage"
        throw
    }
}

function Invoke-Extraction {
    param($ArchivePath, $DestinationPath)
    $archiveName = Split-Path -Leaf $ArchivePath
    try {
        if ($PSCmdlet.ShouldProcess($archiveName, "Extract to $DestinationPath")) {
            Write-Host "Extracting [$archiveName] to '$DestinationPath'..." -ForegroundColor Yellow
            Expand-Archive -Path $ArchivePath -DestinationPath $DestinationPath -Force -ErrorAction Stop
            Write-Host "[$archiveName] extracted successfully." -ForegroundColor Green
        }
    }
    catch {
        $errorMessage = $_.Exception.Message
        Write-Error "Failed to extract [$archiveName]. Error: $errorMessage"
        throw
    }
}

function Start-ProcessWithLogging {
    param(
        [string]$FilePath,
        [string]$ArgumentList,
        [string]$SuccessMessage,
        [int[]]$ValidExitCodes = @(0, 3010),
        [string]$LogMessage = ""
    )
    if (-not [string]::IsNullOrEmpty($LogMessage)) {
        Write-Host $LogMessage -ForegroundColor Cyan
    } else {
        $loggableArgs = $ArgumentList
        Write-Host "Executing: $FilePath $loggableArgs" -ForegroundColor Cyan
    }

    $process = Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -notin $ValidExitCodes) {
        Write-Error "Process failed with exit code: $($process.ExitCode)."
        throw "Installation failed."
    }
    Write-Host $SuccessMessage -ForegroundColor Green
    if ($process.ExitCode -eq 3010) {
        Write-Warning "A reboot is recommended to complete the installation."
    }
}
#endregion

# --- Main Execution ---
try {
    Test-Admin

    # --- Initial User Confirmation ---
    Write-Host "PostgreSQL Installation and Configuration Script" -ForegroundColor Green
    Write-Host "This script will download, install, and configure PostgreSQL and related components." -ForegroundColor Yellow
    Write-Host "---"
    Write-Host "Configuration:"
    Write-Host "  Application Root: $AppRootPath"
    Write-Host "  Download Cache:   $DownloadCachePath" # Added to summary
    Write-Host "  PostgreSQL Data:  $PostgresDataPath"
    Write-Host "  PostgreSQL Install: $PostgresInstallPath"
    Write-Host "  PostgreSQL Port:  $PostgresPort"
    Write-Host "---"

    $continue = Read-Host "Type 'Y' to continue with the installation"
    if ($continue -ne 'Y') {
        Write-Host "Installation cancelled by user." -ForegroundColor Red
        exit 0
    }

    $downloadHtnhisChoice = Read-Host "Do you want to download and configure the 'htnhis' application files? (Y/N)"
    $downloadHtnhis = ($downloadHtnhisChoice -eq 'Y')

    $postgresPasswordSecure = Get-PostgresCredentials
    $postgresPasswordPlain = (New-Object System.Net.NetworkCredential("", $postgresPasswordSecure)).Password

    # --- 1. Create Directories ---
    Write-Host "`nStep 1: Creating required directories..." -ForegroundColor Magenta
    $htnhisPath = Join-Path $AppRootPath "htnhis"
    $backupToolPath = Join-Path $AppRootPath "TuneBackupTool"
    
    # --- FIX 1 (Cont.): Ensure DownloadCachePath (Tools) is created ---
    # --- NEW: Added specific backup directories ---
    $backupTuneHIS = "D:\BackupTuneHIS"

    $dirsToCreate = @( $AppRootPath, $DownloadCachePath, $PostgresDataPath, $backupToolPath, $backupTuneHIS)
    if ($downloadHtnhis) {
        $dirsToCreate += $htnhisPath
    }

    $dirsToCreate | ForEach-Object {
        if (-not (Test-Path $_)) {
            if ($PSCmdlet.ShouldProcess($_, "Create Directory")) {
                New-Item -Path $_ -ItemType Directory -Force -ErrorAction Stop | Out-Null
                Write-Host "  Created: $_" -ForegroundColor Green
            }
        } else {
            Write-Host "  Exists: $_" -ForegroundColor Gray
        }
    }

    # --- 2. System Configuration ---
    Write-Host "`nStep 2: Configuring system time and date..." -ForegroundColor Magenta
    try {
        Set-TimeZone -Id "India Standard Time" -ErrorAction Stop
        Write-Host "  Timezone set to 'India Standard Time'." -ForegroundColor Green
        
        Write-Host "  Configuring date and time formats..." -ForegroundColor Cyan
        Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sShortDate" -Value "dd-MMM-yyyy" -ErrorAction Stop
        Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sLongDate" -Value "dd-MMM-yyyy" -ErrorAction Stop
        Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sShortTime" -Value "hh:mm tt" -ErrorAction Stop
        Set-ItemProperty -Path "HKCU:\Control Panel\International" -Name "sLongTime" -Value "hh:mm:ss tt" -ErrorAction Stop
        Write-Host "  Date and time formats configured successfully." -ForegroundColor Green
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Warning "Could not set timezone or date/time formats. This is non-critical. Error: $errorMessage"
    }

    # --- 3. Download and Extract Files ---
    Write-Host "`nStep 3: Downloading and extracting files..." -ForegroundColor Magenta
    foreach ($key in $Downloads.Keys) {
        if ($key -eq "htnhis_zip" -and -not $downloadHtnhis) {
            Write-Host "[htnhis.zip] download and extraction skipped by user." -ForegroundColor Yellow
            continue
        }

        $file = $Downloads[$key]
        Invoke-Download -Url $file.url -OutFile $file.path

        # Check if the file is meant to be extracted
        if ($file.ContainsKey("extractTo")) {
            $destinationPath = $file.extractTo

            # Dynamically set paths for specific zips that depend on other parameters
            if ($key -eq "htnhis_zip") {
                $destinationPath = $htnhisPath
            }
            if ($key -eq "backup_tool_zip") {
                $destinationPath = $backupToolPath
            }

            # Ensure the destination path is set before attempting extraction
            if (-not [string]::IsNullOrEmpty($destinationPath)) {
                 Invoke-Extraction -ArchivePath $file.path -DestinationPath $destinationPath
            }
        }
    }

    # --- 4. Install PostgreSQL and ODBC Driver ---
    Write-Host "`nStep 4: Installing PostgreSQL and ODBC driver..." -ForegroundColor Magenta
    $pgInstallArgs = "--mode unattended --unattendedmodeui none --superpassword `"$postgresPasswordPlain`" --servicename postgresql-htn --serviceaccount postgres --servicepassword `"$postgresPasswordPlain`" --prefix `"$PostgresInstallPath`" --datadir `"$PostgresDataPath`" --serverport $PostgresPort --locale `"English, United States`""
    Start-ProcessWithLogging -FilePath $Downloads.pg_setup.path -ArgumentList $pgInstallArgs -SuccessMessage "PostgreSQL installed successfully." -LogMessage "Installing PostgreSQL..."

    $odbcInstallArgs = "/i `"$($Downloads.odbc_driver.path)`" /quiet /norestart"
    Start-ProcessWithLogging -FilePath "msiexec.exe" -ArgumentList $odbcInstallArgs -SuccessMessage "PostgreSQL ODBC driver installed successfully." -LogMessage "Installing ODBC Driver..."

    # --- 5. Configure Database ---
    Write-Host "`nStep 5: Configuring PostgreSQL database..." -ForegroundColor Magenta
    $pgBinPath = Join-Path $PostgresInstallPath "bin"
    $env:PGPORT = $PostgresPort
    $env:PGUSER = "postgres"
    $env:PGPASSWORD = $postgresPasswordPlain

    # Wait for service to start
    Write-Host "  Waiting for PostgreSQL service to start..." -ForegroundColor Cyan
    Start-Sleep -Seconds 10
    if (-not (Get-Service -Name "postgresql-htn" | Where-Object { $_.Status -eq "Running" })) {
        Write-Warning "Service not running, attempting to start..."
        Start-Service -Name "postgresql-htn"
        Start-Sleep -Seconds 10
    }
    if (-not (Get-Service -Name "postgresql-htn" | Where-Object { $_.Status -eq "Running" })) {
        throw "PostgreSQL service failed to start."
    }
    Write-Host "  Service is running." -ForegroundColor Green

    # Create user and database
    & "$pgBinPath\psql.exe" -h localhost -U postgres -c "CREATE USER htn WITH PASSWORD '1234' SUPERUSER;"
    if ($LASTEXITCODE -ne 0) { throw "Failed to create user 'htn'." }
    Write-Host "  User 'htn' created." -ForegroundColor Green

    & "$pgBinPath\createdb.exe" -h localhost -U postgres -O htn htnhis
    if ($LASTEXITCODE -ne 0) { throw "Failed to create database 'htnhis'." }
    Write-Host "  Database 'htnhis' created." -ForegroundColor Green

    # Restore database
    $backupPath = Join-Path $DownloadCachePath "db.bak"
    Write-Host "  Restoring database from '$backupPath'..." -ForegroundColor Cyan
    & "$pgBinPath\pg_restore.exe" -h localhost -U postgres -d htnhis -v "`"$backupPath`""
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Database restoration completed with non-critical warnings (this is often normal)."
    } else {
        Write-Host "  Database restoration completed successfully." -ForegroundColor Green
    }

    # --- 6. Configure Network Access (pg_hba.conf) ---
    Write-Host "`nStep 6: Configuring network access..." -ForegroundColor Magenta
    $pgHbaPath = Join-Path $PostgresDataPath "pg_hba.conf"
    if (Test-Path $pgHbaPath) {
        Write-Warning "Updating pg_hba.conf to allow remote connections using md5 passwords."
        $hbaContent = Get-Content $pgHbaPath -Raw
        # Comment out existing host rules and add the new one
        $hbaContent = $hbaContent -replace '(?m)^host\s+', '#host '
        $hbaContent += "`nhost    all             all             0.0.0.0/0               md5`n"
        $hbaContent += "host    all             all             ::/0                    md5`n"
        Set-Content -Path $pgHbaPath -Value $hbaContent
        Write-Host "  pg_hba.conf updated." -ForegroundColor Green

        Write-Host "  Restarting PostgreSQL service to apply changes..." -ForegroundColor Cyan
        Restart-Service -Name "postgresql-htn" -Force
        Start-Sleep -Seconds 5
    } else {
        Write-Warning "Could not find pg_hba.conf at '$pgHbaPath'. Skipping network configuration."
    }

    # --- 7. Configure Firewall ---
    Write-Host "`nStep 7: Configuring Windows Firewall..." -ForegroundColor Magenta
    $ruleName = "PostgreSQL HTN Service"
    if (Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue) {
        Write-Host "  Firewall rule '$ruleName' already exists. Ensuring it is configured correctly..." -ForegroundColor Gray
        Get-NetFirewallRule -DisplayName $ruleName | Set-NetFirewallRule -Action Allow -Protocol TCP -LocalPort $PostgresPort -Enabled True -Profile Any
        Write-Host "  Firewall rule '$ruleName' verified." -ForegroundColor Green
    } else {
        New-NetFirewallRule -DisplayName $ruleName -Direction Inbound -Action Allow -Protocol TCP -LocalPort $PostgresPort -Enabled True -Profile Any -Group "PostgreSQL"
        Write-Host "  Firewall rule '$ruleName' created for TCP port $PostgresPort." -ForegroundColor Green
    }
    
    # --- 8. Disable Password Protected Sharing ---
    Write-Host "`nStep 8: Disabling Password Protected Sharing..." -ForegroundColor Magenta
    $regKey = "HKLM:\SYSTEM\CurrentControlSet\Control\Lsa"
    $regValue = "LimitBlankPasswordUse"
    
    $netKey = "HKLM:\SYSTEM\CurrentControlSet\Services\LanmanServer\Parameters"
    $netValue = "restrictnullsessaccess"
    
    try {
        if ((Get-ItemProperty -Path $regKey -Name $regValue -ErrorAction SilentlyContinue).$regValue -ne 0) {
            Set-ItemProperty -Path $regKey -Name $regValue -Value 0 -Force -ErrorAction Stop
            Write-Host "  Set registry key '$regKey\$regValue' to 0." -ForegroundColor Green
        } else {
            Write-Host "  Registry key '$regKey\$regValue' is already set to 0." -ForegroundColor Gray
        }
        
        if ((Get-ItemProperty -Path $netKey -Name $netValue -ErrorAction SilentlyContinue).$netValue -ne 0) {
            Set-ItemProperty -Path $netKey -Name $netValue -Value 0 -Force -ErrorAction Stop
            Write-Host "  Set registry key '$netKey\$netValue' to 0." -ForegroundColor Green
        } else {
            Write-Host "  Registry key '$netKey\$netValue' is already set to 0." -ForegroundColor Gray
        }
            
        Write-Warning "  Password Protected Sharing has been disabled."
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Warning "  Could not disable password protected sharing. Manual configuration may be required. Error: $errorMessage"
    }

    # --- 9. Configure Network Share ---
    if ($downloadHtnhis) {
        Write-Host "`nStep 9: Configuring network share..." -ForegroundColor Magenta
        $shareName = "htnhis"
        if (Get-SmbShare -Name $shareName -ErrorAction SilentlyContinue) {
            Write-Host "  Removing existing network share '$shareName'..." -ForegroundColor Cyan
            Remove-SmbShare -Name $shareName -Force
        }
        Write-Host "  Creating new network share '$shareName' for path '$htnhisPath'." -ForegroundColor Cyan
        
        # --- FIX 2: Ensure Share permissions are for Everyone (Read) ---
        New-SmbShare -Name $shareName -Path $htnhisPath -ReadAccess "Everyone" -ErrorAction Stop
        Write-Host "  Network share '$shareName' created with Read access for 'Everyone'." -ForegroundColor Green
        
        # --- FIX 3: Ensure NTFS Permissions allow Everyone to read ---
        # (This is critical: Share permissions mean nothing if NTFS blocks it)
        Write-Host "  Setting NTFS permissions for 'Everyone' (Read-Only)..." -ForegroundColor Cyan
        try {
            # Use icacls for reliable permission setting on the folder
            $null = icacls $htnhisPath /grant "Everyone:(OI)(CI)R" /T /C
            Write-Host "  NTFS permissions updated successfully." -ForegroundColor Green
        } catch {
            Write-Warning "  Failed to set NTFS permissions automatically. Please ensure 'Everyone' has Read access to folder properties."
        }

        Write-Host "  Share available at: \\$env:COMPUTERNAME\$shareName" -ForegroundColor White
    }
    else {
        Write-Host "`nStep 9: Skipping network share configuration as 'htnhis' files were not downloaded." -ForegroundColor Yellow
    }

    # --- 10. Cleanup Temporary Files ---
    Write-Host "`nStep 10: Cleaning up temporary files..." -ForegroundColor Magenta
    $filesToDelete = @(
        $Downloads.db_zip.path,
        $Downloads.hsql_zip.path,
        $backupPath 
    )
    foreach ($file in $filesToDelete) {
        if (Test-Path $file) {
            Write-Host "  Removing: $(Split-Path -Leaf $file)" -ForegroundColor Cyan
            Remove-Item -Path $file -Force -ErrorAction SilentlyContinue
        }
    }

    # --- Final Summary ---
    Write-Host "`n--- Installation Complete! ---" -ForegroundColor Green
    Write-Host "Summary:" -ForegroundColor Cyan
    Write-Host "  - PostgreSQL Port: $PostgresPort"
    Write-Host "  - Installation Dir:  $PostgresInstallPath"
    Write-Host "  - Data Dir:          $PostgresDataPath"
    Write-Host "  - Database:          htnhis"
    if ($downloadHtnhis) {
        Write-Host "  - Network Share:     \\$env:COMPUTERNAME\htnhis (Read-only for Everyone)"
    }

}
catch {
    Write-Error "An unrecoverable error occurred during installation. Please check the output above."
    Write-Error $_.Exception.Message
}
finally {
    # Clear sensitive data from memory and environment variables
    $postgresPasswordPlain = $null
    $postgresPasswordSecure = $null
    $env:PGPASSWORD = $null
    Write-Host "`nScript finished. Press Enter to exit. The script file will be deleted automatically." -ForegroundColor Yellow
    Read-Host

    try {
        # Schedule the script to delete itself after exit
        $scriptPath = $MyInvocation.MyCommand.Definition
        Start-Process -FilePath "cmd.exe" -ArgumentList "/c timeout 1 && del `"$scriptPath`"" -WindowStyle Hidden
    } catch {
        $errorMessage = $_.Exception.Message
        Write-Warning "Could not schedule script for deletion. You may need to delete it manually. Error: $errorMessage"
    }
}