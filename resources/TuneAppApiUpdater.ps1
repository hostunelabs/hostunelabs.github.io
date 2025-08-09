#
# A script to stop an IIS website, download an update, extract it, and restart the site.
#

# --- Hardcoded Configuration ---
$WebsiteName = "TuneAppApi"
$DownloadUrl = "http://www.hostune.in/resources/TuneAppApi.zip"


# --- Pre-run Checks ---

# 1. Check for Administrator privileges
Write-Host "Checking for administrator privileges..."
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Error "This script must be run with Administrator privileges. Please right-click the PowerShell icon and select 'Run as Administrator'."
    # Pause to allow the user to read the error before the window closes.
    if ($Host.Name -eq "ConsoleHost") {
        Write-Host "Press any key to continue..."
        $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
    }
    return
}
Write-Host "Administrator check passed."

# 2. Check for and import the WebAdministration module for IIS control
Write-Host "Checking for WebAdministration module..."
if (-NOT (Get-Module -ListAvailable -Name WebAdministration)) {
    Write-Error "The WebAdministration module is required. Please install 'IIS Management Scripts and Tools' via 'Turn Windows features on or off'."
    if ($Host.Name -eq "ConsoleHost") {
        Write-Host "Press any key to continue..."
        $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
    }
    return
}
Import-Module WebAdministration
Write-Host "WebAdministration module loaded successfully."


# --- Confirmation Prompt ---
Write-Host "" # Add a blank line for readability
$confirmation = Read-Host "This script will stop '$WebsiteName', create a backup, download an update, and replace existing files. Are you sure you want to continue? (Y/N)"

if ($confirmation -notmatch '^[Yy](es)?$') {
    Write-Host "Update cancelled by user."
    # Pause to allow the user to read the message before the window closes.
    if ($Host.Name -eq "ConsoleHost") {
        Write-Host "Press any key to exit..."
        $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
    }
    return
}
Write-Host "User confirmed. Proceeding with the update..."
Write-Host "" # Add a blank line for readability


# --- Script Body ---

try {
    # --- Step 1: Get Website Information ---
    Write-Host "Getting information for website: $WebsiteName"
    $webSite = Get-Website -Name $WebsiteName -ErrorAction Stop
    $physicalPath = $webSite.PhysicalPath
    Write-Host "Website physical path: $physicalPath"

    # --- Step 2: Stop the IIS Website ---
    Write-Host "Stopping website: $WebsiteName..."
    Stop-Website -Name $WebsiteName -ErrorAction Stop
    Write-Host "$WebsiteName has been stopped successfully."

    # --- Step 3: Backup Website Files ---
    Write-Host "Backing up current website files..."
    $sourceFolderName = Split-Path -Path $physicalPath -Leaf
    $parentDir = Split-Path -Path $physicalPath -Parent
    $backupFolderName = "Copy of $sourceFolderName"
    $backupPath = Join-Path -Path $parentDir -ChildPath $backupFolderName

    # Check if a previous backup exists and remove it to prevent conflicts
    if (Test-Path -Path $backupPath) {
        Write-Host "Removing existing backup folder: $backupPath"
        Remove-Item -Path $backupPath -Recurse -Force -ErrorAction Stop
    }

    # Create the new backup by copying the entire website directory
    Write-Host "Creating backup at: $backupPath"
    Copy-Item -Path $physicalPath -Destination $backupPath -Recurse -Force -ErrorAction Stop
    Write-Host "Backup created successfully."

    # --- Step 4: Download the Update ---
    # Create a temporary path for the downloaded zip file.
    $tempZipFile = Join-Path -Path $env:TEMP -ChildPath "TuneAppApi_update.zip"
    Write-Host "Downloading update from: $DownloadUrl"
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $tempZipFile -ErrorAction Stop
    Write-Host "Download complete. File saved to $tempZipFile"

    # --- Step 5: Extract the Update ---
    Write-Host "Extracting files to: $physicalPath"
    # Using .NET for broader PowerShell version compatibility, as Expand-Archive requires PS v5.0+
    try {
        # Load the required .NET assembly for zip operations
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($tempZipFile)

        # Loop through each item in the zip archive
        foreach ($entry in $archive.Entries) {
            $destinationFullPath = [System.IO.Path]::Combine($physicalPath, $entry.FullName)

            # Ensure the destination directory for the current item exists
            $destinationDir = [System.IO.Path]::GetDirectoryName($destinationFullPath)
            if (-not (Test-Path $destinationDir)) {
                New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
            }

            # Extract the file, overwriting if it already exists.
            # Skip directory entries in the zip file, which have no Name.
            if ($entry.Name) {
                 [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $destinationFullPath, $true)
            }
        }
    }
    finally {
        # Ensure the archive file handle is released, even if errors occur
        if ($archive) {
            $archive.Dispose()
        }
    }
    Write-Host "Extraction complete. Files have been replaced."

    # --- Step 6: Start the IIS Website ---
    Write-Host "Starting website: $WebsiteName..."
    Start-Website -Name $WebsiteName -ErrorAction Stop
    Write-Host "$WebsiteName has been started successfully."

    # --- Cleanup ---
    Write-Host "Cleaning up temporary files..."
    Remove-Item -Path $tempZipFile -Force
    Write-Host "Update process completed successfully!"

}
catch {
    # Catch any errors that occurred during the try block
    Write-Error "An error occurred during the update process: $($_.Exception.Message)"
    
    # Attempt to restart the website if it exists and is not started, to avoid leaving it in a stopped state.
    if ((Get-Website -Name $WebsiteName -ErrorAction SilentlyContinue) -and (Get-Website -Name $WebsiteName).State -ne "Started") {
        Write-Warning "An error occurred. Attempting to restart the website to prevent downtime..."
        Start-Website -Name $WebsiteName
    }
}

# Pause at the end if running in a console, so the user can see the final output.
if ($Host.Name -eq "ConsoleHost") {
    Write-Host "Press any key to exit..."
    $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown") | Out-Null
}
