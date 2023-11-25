try {
## Amend this for internal build script e.g. when newer feature update is released - Might be a way to automate pulling through the latest version
$WindowsOSVersion = "Windows 11 22H2 x64"

function Start-Autopilot {

    Write-Host "Would you like to enrol this device into Autopilot?" -ForegroundColor Magenta
    Write-Host "NOTE: If the device is already enrolled in Autopilot. Select NO" -ForegroundColor Yellow

    $APChoice = Read-Host "Y for Yes or N for No"

    if ($APChoice -eq "Y")
    {
        Write-Host "Starting Autopilot Process" -ForegroundColor Yellow
        Write-Host "Importing required modules" -ForegroundColor Yellow
        Import-Module Microsoft.Graph.Authentication
        Start-AutopilotEnrolment
        Start-BuildSelection
    }
    elseif ($APChoice -eq "N")
    {
        Write-Host "Skipping Autopilot Enrolment" -ForegroundColor Yellow
        Start-BuildSelection
    }
    else
    {
        Write-Host "Invalid selection. Please try again." -ForegroundColor Red
        Start-Autopilot
    }
}

function Start-AutopilotEnrolment {
    $SerialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber

    Write-Host "Welcome to Autopilot Enrolment" -ForegroundColor Yellow
    $GroupTag = Read-Host "Please enter your GroupTag (Case Sensitive)"
    $OutputFile = "X:\Autopilot\$SerialNumber.CSV"
    X:\Autopilot\Create_4kHash_using_OA3_Tool.ps1 -GroupTag $GroupTag -OutputFile $OutputFile
    ## NOT FINISHED - NEED TO EITHER GET IT TO ASK THE USER WHERE TO SAVE THE OUTPUT FILE, OR AUTOMATE IT UPLOADING
    Write-Host "Creation of Autopilot CSV file succeeded!" -ForegroundColor Green
    Write-Host "Starting Upload to Intune now via MS Graph. Please login with an account that has the ability to enrol devices to Autopilot." -ForegroundColor Yellow
    Sleep -Seconds 10
    Start-AutopilotGraphUpload
    Sleep -Seconds 10
    }

function Start-AutopilotGraphUpload {

  # PowerShell Script to Import AutoPilot CSV via Microsoft Graph

    # Function to connect to Microsoft Graph
    function Connect-Graph {
        $scopes = "DeviceManagementServiceConfig.ReadWrite.All"

        try {
            Connect-MgGraph -Scopes $scopes
            Write-Host "Connected to Microsoft Graph." -ForegroundColor Green
        } catch {
            Write-Host "Error connecting to Microsoft Graph: $_" -ForegroundColor Red
            exit
        }
    }

    # Function to read and format AutoPilot CSV data
    function Get-AutoPilotData {
        param (
            [string]$CsvPath
        )

        try {
            $csvData = Import-Csv -Path $CsvPath -Encoding UTF8
            $deviceList = @()

            foreach ($row in $csvData) {
                $hardwareIdentifierBase64 = if ([string]::IsNullOrWhiteSpace($row."Hardware Hash")) {
                    "" # Leave empty if no hardware hash
                } else {
                    $bytes = [System.Convert]::FromBase64String($row."Hardware Hash")
                    [System.Convert]::ToBase64String($bytes)
                }

                $deviceObj = @{
                    "@odata.type" = "#microsoft.graph.importedWindowsAutopilotDeviceIdentity"
                    groupTag = $row."Group Tag"
                    serialNumber = $row."Device Serial Number"
                    productKey = if ($row."Windows Product ID") { $row."Windows Product ID" } else { $null }
                    hardwareIdentifier = $hardwareIdentifierBase64
                }
                $deviceList += $deviceObj
            }

            return $deviceList | ConvertTo-Json -Depth 10
        } catch {
            Write-Host "Error reading CSV file: $_" -ForegroundColor Red
            exit
        }
    }




    # Function to upload data to Intune via Microsoft Graph
    function Upload-AutoPilotData {
        param (
            [string]$JsonData
        )

        $uri = "https://graph.microsoft.com/v1.0/deviceManagement/importedWindowsAutopilotDeviceIdentities"

        try {
            $response = Invoke-MgGraphRequest -Method POST -Uri $uri -Body $JsonData -ContentType "application/json"
            return $response
        } catch {
            Write-Host "Error uploading data to Intune: $($_.Exception.Response.StatusCode.Value__) $($_.Exception.Message)" -ForegroundColor Red
            Write-Host "Graph API Response: $($_.Exception.Response.Content.ReadAsStringAsync().Result)" -ForegroundColor Red
            exit
        }
    }


    # Main script execution
    function Main {
        # Connect to Microsoft Graph
        Connect-Graph

        # Modify the path to your AutoPilot CSV file
        $csvPath = "E:\Test2.csv"
    
        # Get and format AutoPilot data
        $jsonData = Get-AutoPilotData -CsvPath $csvPath

        # Print JSON Payload for debugging (Remove in production)
        Write-Host "JSON Payload: $jsonData" -ForegroundColor Yellow

        # Upload data to Intune
        $response = Upload-AutoPilotData -JsonData $jsonData

        # Check response
        if ($response -ne $null) {
            Write-Host "AutoPilot data uploaded successfully." -ForegroundColor Green
        } else {
            Write-Host "Failed to upload AutoPilot data." -ForegroundColor Red
        }
    }

    # Run the script
    Main
}
    
function Start-BuildSelection {
    Write-Host "Which build would you like to run?" -ForegroundColor Magenta
    Write-Host "1) Internal Build (Automated, will wipe the disk, install $WindowsOSVersion Enterprise, latest drivers and then shutdown" -ForegroundColor Magenta
    Write-Host "2) Install specific WIM file (Prompt for WIM choice from available WIM files, wipe the disk, install Windows, latest drivers, and then shutdown)" -ForegroundColor Magenta
    Write-Host "3) Show OSDCloud GUI for manual build" -ForegroundColor Magenta

    $Choice = Read-Host "Please select which build you would like to run"

    if ($Choice -eq "1")
        {
            Write-Host "Starting internal build" -ForegroundColor Yellow
            Start-OSDInternal
        }
    elseif ($Choice -eq "2")
        {
            Write-Host "Starting specific WIM file build" -ForegroundColor Yellow
            Start-OSDWIM
        }
    elseif ($Choice -eq "3")
        {
            Write-Host "Starting OSDCloud GUI" -ForegroundColor Yellow 
            Start-OSDCloudGUI
            Write-Host "Build complete!" -ForegroundColor Green

            ## Fix TPM Attestation issue seen before during Autopilot
            Start-TPMAttestationFix

            Write-Host -ForegroundColor Cyan "Shutting down in 3 seconds!" -ForegroundColor Yellow 
            Start-Sleep -Seconds 3
            wpeutil shutdown
        }
    else
        {
            Write-Host "Invalid selection. Please try again." -ForegroundColor Red
            Start-BuildSelection
        }

}

function Start-OSDInternal {

    ## Install Windows Version listed at top of script, Enterprise, GB language, allow taking screenshots, ZTI so no prompts, skip adding Autopilot profile JSON
    Start-OSDCloud -OSName "$WindowsOSVersion" -OSEdition Enterprise -OSLanguage en-GB -Screenshot -ZTI -SkipAutopilot
    Write-Host "Build complete!" -ForegroundColor Green

    ## Fix TPM Attestation issue seen before during Autopilot
    Start-TPMAttestationFix

    Write-Host "Shutting down in 3 seconds!" -ForegroundColor Yellow
    Start-Sleep -Seconds 3
    wpeutil shutdown
}

function Start-OSDWIM {

    ## Connect to the shared location for WIM files
    net use * \\192.168.1.167\OSDCloud /user:Administrator

    ## Starts OSDCloud with the parameters to search for WIM files, Skip adding Autopilot profile JSON, Skip ODT, and Zero Touch Installation (No prompts throughout build process)
    Start-OSDCloud -FindImageFile -SkipAutopilot -SkipODT -ZTI
    Write-Host "Build complete!" -ForegroundColor Green

    ## Fix TPM Attestation issue seen before during Autopilot
    Start-TPMAttestationFix

    Write-Host "Shutting down in 3 seconds!" -ForegroundColor Yellow
    Start-Sleep -Seconds 3
    wpeutil shutdown
}

function Start-TPMAttestationFix {

    Write-Host "Adding registry key for TPM attestation fix" -ForegroundColor Yellow
    reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\OOBE /v SetupDisplayedEula /t REG_DWORD /d 00000001 /f
    Write-Host "Reg key added!" -ForegroundColor Green
}

Write-Host "Automated Building Process V2.0" -ForegroundColor Yellow
Write-Host "Now includes Autopilot Enrolment!" -ForegroundColor Yellow
Start-Autopilot
pause

}
catch {
    Write-Host "An error occurred: $_"
    Read-Host -Prompt "Press Enter to exit"
}
