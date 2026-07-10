#███████████████████████████████████████████████████
#█                  PREREQUISITES                  █
#███████████████████████████████████████████████████

# Run Script As Admin
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator"))
{
$arguments = "& '" + $myinvocation.mycommand.definition + "'"
Start-Process powershell -Verb runAs -ArgumentList $arguments
Exit
}

Add-Type -AssemblyName PresentationFramework

# ------------------------------------------------------------
#                          FUNCTIONS
# ------------------------------------------------------------

# Install Universal HP, Konica Minolta, Lexmark and Canon printer drivers.
function Install-PrintDrivers {
    [CmdletBinding()]
    param()

    Write-Host "`n🖨️  Installing common universal print drivers..." -ForegroundColor Magenta

    $DownloadUrl = "https://github.com/TCBCTim/BasicPrep/releases/download/print_drivers/Printer_Drivers.zip"
    $TempPath    = "C:\Temp"
    $ZipPath     = Join-Path $TempPath "Printer_Drivers.zip"
    $ExtractPath = Join-Path $TempPath "Printer_Drivers"

    $CanonInf = Join-Path $ExtractPath "Printer_Drivers\Canon_Universal\CNS30MA64.inf"
    $KMInf    = Join-Path $ExtractPath "Printer_Drivers\KM_Universal\KOAWNA__.inf"
    $HPInf    = Join-Path $ExtractPath "Printer_Drivers\HP_Universal\hpcu355v.inf"
    $LexInf   = Join-Path $ExtractPath "Printer_Drivers\Lexmark_Universal\LMUD1p40.inf"

    if (-not (Test-Path $TempPath)) {
        New-Item -Path $TempPath -ItemType Directory -Force | Out-Null
    }

    Write-Host "Downloading print driver package..."
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $ZipPath -UseBasicParsing

    Write-Host "Extracting print driver package..."
    if (Test-Path $ExtractPath) {
        Remove-Item $ExtractPath -Recurse -Force
    }

    Expand-Archive -Path $ZipPath -DestinationPath $ExtractPath -Force

    function Install-INFDriver {
        param([Parameter(Mandatory)][string]$InfPath)

        if (-not (Test-Path $InfPath)) {
            Write-Host "❌ INF not found: $InfPath"
            return
        }

        Write-Host "Installing driver from $InfPath ..."
        pnputil.exe /add-driver "$InfPath" /install | Out-Host
    }

    Write-Host "Installing Canon Universal driver..."
    Install-INFDriver -InfPath $CanonInf

    Write-Host "Installing Konica Minolta Universal driver..."
    Install-INFDriver -InfPath $KMInf

    Write-Host "Installing HP Universal driver..."
    Install-INFDriver -InfPath $HPInf

    Write-Host "Installing Lexmark Universal driver..."
    Install-INFDriver -InfPath $LexInf

    Write-Host "All drivers processed."
}

# Set up SMB Scan Share and Folder
function Setup-ScansShare {
    param (
        [string]$username = "scans",
        [string]$folderPath = "C:\scans",
        [string]$shareName = "scans"
    )

    Write-Host "`n📁 Setting up SCANS account, folder, and share..." -ForegroundColor Magenta

    # Generate dynamic password
    $year = (Get-Date).Year
    $password = "Scanning${year}!"

    # Create user account
    try {
        net user /add $username $password
        Write-Host "✅ User '$username' created." -ForegroundColor Green
    } catch {
        Write-Host "⚠️ Failed to create user '$username'. It may already exist." -ForegroundColor Yellow
    }

    # Disable password expiration
    try {
        Set-LocalUser -Name $username -PasswordNeverExpires $true
        Write-Host "🔒 Password expiration disabled for '$username'." -ForegroundColor Cyan
    } catch {
        Write-Host "⚠️ Failed to update password policy for '$username'." -ForegroundColor Yellow
    }

    # Create folder if needed
    if (-not (Test-Path -Path $folderPath)) {
        New-Item -Path $folderPath -ItemType Directory | Out-Null
        Write-Host "📂 Folder created at $folderPath" -ForegroundColor Green
    } else {
        Write-Host "📂 Folder already exists at $folderPath" -ForegroundColor Cyan
    }

    # Set NTFS permissions
    try {
        $acl = Get-Acl $folderPath
        $accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            "$env:COMPUTERNAME\$username", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow"
        )
        $acl.SetAccessRule($accessRule)
        Set-Acl -Path $folderPath -AclObject $acl
        Write-Host "🔐 NTFS permissions granted to '$username'." -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed to set NTFS permissions." -ForegroundColor Red
    }

    # Create share and set permissions
    try {
        Invoke-Expression "net share $shareName=`"$folderPath`" /GRANT:$username,FULL"
        Write-Host "🔗 Folder shared as '$shareName' with full permissions for '$username'." -ForegroundColor Green
    } catch {
        Write-Host "❌ Failed to create share '$shareName'." -ForegroundColor Red
    }

    # Enable SMB 1.0/CIFS features
    Write-Host "`n🔧 Checking SMB 1.0/CIFS features..." -ForegroundColor Magenta
    $features = @("SMB1Protocol", "SMB1Protocol-Client", "SMB1Protocol-Server")

    foreach ($feature in $features) {
        try {
            $featureState = Get-WindowsOptionalFeature -Online -FeatureName $feature
            if ($featureState.State -ne "Enabled") {
                Write-Host "🔄 $feature is not enabled. Enabling now..." -ForegroundColor Yellow
                Enable-WindowsOptionalFeature -Online -FeatureName $feature -NoRestart
            } else {
                Write-Host "✅ $feature is already enabled." -ForegroundColor Green
            }
        } catch {
            Write-Host "❌ Failed to check or enable $feature." -ForegroundColor Red
        }
    }

    # Output credentials to scans folder
    try {
        $outputPath = Join-Path $folderPath "ScansAccount.txt"
        $outputText = "Username: $username`nPassword: $password"
        Set-Content -Path $outputPath -Value $outputText
        Write-Host "📝 Credentials saved to: $outputPath" -ForegroundColor Cyan
    } catch {
        Write-Host "❌ Failed to write credentials to scans folder." -ForegroundColor Red
    }

    Write-Host "`n✅ SCANS setup complete." -ForegroundColor Green
}

# Remove all 365 Apps
# This Will Break within 90 days when the CMD tool expires and I have to get a new URL. Last Working as of 3/16/26
function Invoke-SaRATool {
    Write-Host "`n📦 Downloading and running Microsoft SaRA Tool..." -ForegroundColor Magenta

    # Add .NET Assemblies
    Add-Type -AssemblyName PresentationFramework
    Add-Type -AssemblyName System.Windows.Forms

    try {
        # Define paths and URLs
        $tempPath = "C:\temp"
        $zipUrl = "https://download.microsoft.com/download/5/0/d/50dd45c9-f465-402e-92d2-537871f1f106/SaRACmd_17_0_8713_1.zip"
        $zipPath = Join-Path $tempPath "SaRACmd.zip"
        $extractPath = Join-Path $tempPath "SaRACmd"

        # Create C:\temp if it doesn't exist
        if (-not (Test-Path $tempPath)) {
            New-Item -ItemType Directory -Path $tempPath | Out-Null
        }

        # Download SaRA zip file
        Write-Host "⬇ Downloading SaRA tool..." -ForegroundColor Blue
        Invoke-WebRequest -Uri $zipUrl -OutFile $zipPath

        # Extract the zip file
        Write-Host "📂 Extracting SaRA tool..." -ForegroundColor Blue
        Expand-Archive -Path $zipPath -DestinationPath $extractPath -Force

        # Run SaRAcmd.exe from the DONE subfolder with specified arguments
        Write-Host "🚀 Running SaRA tool with OfficeScrubScenario..." -ForegroundColor Blue
        Write-Host "ℹ️ This will remove all installed versions of Microsoft Office completely..."
        Write-Host "ℹ️ Please make sure all office apps are closed...including teams."
        Write-Host "This may take 15+ minutes please be patient."
        $saraCmdPath = Join-Path $extractPath "SaRACMD.exe"
        Start-Process -FilePath $saraCmdPath -ArgumentList "-S OfficeScrubScenario -AcceptEula -CloseOffice -OfficeVersion All" -Wait

        Write-Host "`n✅ SaRA tool execution complete." -ForegroundColor Green
    } catch {
        Write-Host "`n❌ Error during SaRA tool execution: $_" -ForegroundColor Red
        [System.Windows.Forms.MessageBox]::Show("SaRA tool execution failed.`n$_", "Error")
    }
}
# Call the function
Invoke-SaRATool





# ------------------------------------------------------------
# GUI WINDOW
# ------------------------------------------------------------
$window = New-Object System.Windows.Window
$window.Title = "Tim's QuikScripz"
$window.Width = 500
$window.Height = 600
$window.WindowStartupLocation = "CenterScreen"
$window.Background = "WhiteSmoke"

$grid = New-Object System.Windows.Controls.Grid
$grid.Margin = "20"

for ($i = 0; $i -lt 10; $i++) {
    $row = New-Object System.Windows.Controls.RowDefinition
    $row.Height = "Auto"
    $grid.RowDefinitions.Add($row)
}

$buttonNames = @(
    "Install Print Drivers",
    "Setup Scans Share",
    "Remove 365 Apps",
    "Button 4",
    "Button 5",
    "Button 6",
    "Button 7",
    "Button 8",
    "Button 9",
    "Button 10"
)

for ($i = 0; $i -lt $buttonNames.Count; $i++) {

    $btn = New-Object System.Windows.Controls.Button
    $btn.Content = $buttonNames[$i]
    $btn.Margin = "5"
    $btn.Height = 40
    $btn.FontSize = 16
    $btn.Tag = $i

    $btn.Add_Click({
        param($sender, $eventArgs)

        switch ($sender.Tag) {
            0 {
                Write-Host "`nRunning Install-PrintDrivers..." -ForegroundColor Cyan
                Install-PrintDrivers
            }
            1 { Write-Host "`nRunning Setup-ScansShare..." -ForegroundColor Cyan
                Setup-ScansShare
            }
            2 { Write-Host "`nRunning Remove-365-Apps..." -ForegroundColor Cyan
                Invoke-SaRATool
            }
            3 { Write-Host "Button 4 clicked. Add your code here." }
            4 { Write-Host "Button 5 clicked. Add your code here." }
            5 { Write-Host "Button 6 clicked. Add your code here." }
            6 { Write-Host "Button 7 clicked. Add your code here." }
            7 { Write-Host "Button 8 clicked. Add your code here." }
            8 { Write-Host "Button 9 clicked. Add your code here." }
            9 { Write-Host "Button 10 clicked. Add your code here." }
        }
    })

    [System.Windows.Controls.Grid]::SetRow($btn, $i)
    $grid.Children.Add($btn)
}

$window.Content = $grid
$window.ShowDialog()
