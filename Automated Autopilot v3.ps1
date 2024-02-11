## This script will check if the device is in Autopilot. If it is, it will print the group tag of the device.
## It will then proceed to remove the Intune record if required, then install Windows & drivers

$winVer = "Windows 11 23H2 x64"

function MgGraph-Authentication {

    ## Credetnails required to auth ##

    $ApplicationId = "84c60813-885f-4a3f-8ecc-b816b3f006be"
    $SecuredPassword = "Xnr8Q~3Gvp01vjpeeVQlc3Zh6xMeHKgHxoyH.bq1"
    $tenantID = "90907c93-7590-444c-a8ac-784e854039b4"

    $SecuredPasswordPassword = ConvertTo-SecureString `
    -String $SecuredPassword -AsPlainText -Force

    $ClientSecretCredential = New-Object `
    -TypeName System.Management.Automation.PSCredential `
    -ArgumentList $ApplicationId, $SecuredPasswordPassword

    try { 
        Connect-MgGraph -TenantId $tenantID -ClientSecretCredential $ClientSecretCredential -NoWelcome
        Write-Host "Connected successfuly"
        downloadPreReqs

    } catch {
        Write-Host "Error connecting to graph: $_."
        Read-Host -Prompt "Press Enter to exit"

    }

}

function downloadPreReqs {

    Write-Host "Creating path for pre-reqs"
    New-Item -ItemType Directory -Path "X:\Autopilot"

    Write-Host "Downloading Pre-reqs..."
    Invoke-WebRequest https://raw.githubusercontent.com/ChrisB2k00/OSD/main/OSD%20Autopilot/Create_4kHash_using_OA3_Tool.ps1 -OutFile X:\Autopilot\Create_4kHash_using_OA3_Tool.ps1
    Invoke-WebRequest https://raw.githubusercontent.com/ChrisB2k00/OSD/main/OSD%20Autopilot/OA3.cfg -OutFile X:\Autopilot\OA3.cfg
    Invoke-WebRequest https://raw.githubusercontent.com/ChrisB2k00/OSD/main/OSD%20Autopilot/PCPKsp.dll -OutFile X:\Autopilot\PCPKsp.dll
    Invoke-WebRequest https://raw.githubusercontent.com/ChrisB2k00/OSD/main/OSD%20Autopilot/input.xml -OutFile X:\Autopilot\input.xml
    Invoke-WebRequest https://raw.githubusercontent.com/ChrisB2k00/OSD/main/OSD%20Autopilot/oa3tool.exe -OutFile X:\Autopilot\oa3tool.exe
    Write-Host "Pre-reqs downloaded!"

    AutopilotDeviceEnrolmentCheck
}

function AutopilotDeviceEnrolmentCheck {
    ## Check if the device is already in Autopilot.
    Write-Host "Checking if device is already enrolled in Autopilot"
    $serialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber
    $autopilotRecord = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity | Where-Object serialNumber -eq "$serialNumber" | Select-Object serialNumber, GroupTag, Model, LastContactedDateTime


    if ($autopilotRecord) {
        Write-Host "Device is not enrolled. Moving to enrolment step"
        IntuneDeviceCheck
        }
    else {
        $enrolledGroupTag = Get-MgDeviceManagementWindowsAutopilotDeviceIdentity | Where-Object serialNumber -eq "$serialNumber" | Select-Object -ExpandProperty GroupTag
        Write-Host "Device already enrolled with Group Tag: $enrolledGroupTag"
        IntuneDeviceCheck
        }

}


function IntuneDeviceCheck {
    ## Check if the device is already in Intune

    Write-Host "Checking if device is in Intune..."
    $serialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber
    $intuneRecord = Get-MgDeviceManagementManagedDevice | Where-Object serialNumber -eq "$serialNumber" | Select-Object serialNumber, deviceName, enrolledDateTime, lastSyncDateTime
    
    if ($intuneRecord) {
        $deviceName = Get-MgDeviceManagementManagedDevice | Where-Object serialNumber -eq "$serialNumber" | Select-Object -ExpandProperty deviceName
        Write-Host "Device is in Intune: $deviceName."
        Write-Host "This will be automatically removed in 5 seconds to prevent conflict during Autopilot."
        sleep 5
        removeIntuneRecord
        }
    else {
        Write-Host "Device is not in Intune. Moving to next step."
        Start-AutopilotEnrolment
        }
}

function removeIntuneRecord {
    ## Removes Intune record if it exists
    $serialNumber = "test"
    $intuneRecord = Get-MgDeviceManagementManagedDevice | Where-Object serialNumber -eq "$serialNumber" | Select-Object serialNumber, deviceName, enrolledDateTime, lastSyncDateTime, Id
    $deviceName = Get-MgDeviceManagementManagedDevice | Where-Object serialNumber -eq "$serialNumber" | Select-Object -ExpandProperty deviceName
    $managedDeviceId = Get-MgDeviceManagementManagedDevice | Where-Object serialNumber -eq "$serialNumber" | Select-Object -ExpandProperty Id


    Write-Host "Removing intune record: $deviceName..."
    try {
    Remove-MgDeviceManagementManagedDevice -ManagedDeviceId $managedDeviceId
    } catch {
        Write-Host "Failed to remove device: $_" -ForegroundColor Red
        Write-Host "$deviceName has not been removed. You will need to remove the device manually before Autopilot!" -ForegroundColor Red
    }
    Start-AutopilotEnrolment
}

function Start-AutopilotEnrolment {
    ## Grab required details and create Autopilot CSV
    $SerialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber

    Write-Host "Welcome to Autopilot Enrolment" -ForegroundColor Yellow
    
    $GroupTag = Read-Host "Please enter your GroupTag (Case Sensitive)"
    
    $OutputFile = "X:\Autopilot\$SerialNumber.CSV"
    
    X:\Autopilot\Create_4kHash_using_OA3_Tool.ps1 -GroupTag $GroupTag -OutputFile $OutputFile
    Write-Host "Creation of Autopilot CSV file succeeded!" -ForegroundColor Green
    Write-Host "Starting Upload to Intune now via MS Graph. Please login with an account that has the ability to enrol devices to Autopilot." -ForegroundColor Yellow
    Sleep -Seconds 10
    Start-AutopilotGraphUpload
    Sleep -Seconds 10
    }

    function Start-AutopilotGraphUpload {

    ## Import AutoPilot CSV via Microsoft Graph

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
            Read-Host -Prompt "Press Enter to exit"
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
            Read-Host -Prompt "Press Enter to exit"
            exit
        }
    }


    function Main {
        $SerialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber

        # Modify the path to AutoPilot CSV file
        $csvPath = "X:\Autopilot\$SerialNumber.CSV"
    
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
            Read-Host -Prompt "Press Enter to exit"
        }
    }

    Main
    Start-OSD
}

function Start-TPMAttestationFix {
    ## Creates registry key to fix TPM attestation error that can sometimes appear during Autopilot
    Write-Host "Adding registry key for TPM attestation fix" -ForegroundColor Yellow
    reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\OOBE /v SetupDisplayedEula /t REG_DWORD /d 00000001 /f
    Write-Host "Reg key added!" -ForegroundColor Green
}

function Start-OSD {

    ## Install Windows Version listed at top of script, Enterprise, GB language, allow taking screenshots, ZTI so no prompts, skip adding Autopilot profile JSON
    Start-OSDCloud -OSName "$winVer" -OSEdition Enterprise -OSLanguage en-GB -Screenshot -ZTI -SkipAutopilot
    Write-Host "Build complete!" -ForegroundColor Green

    Start-TPMAttestationFix

    Write-Host "Shutting down in 3 seconds!" -ForegroundColor Yellow
    Start-Sleep -Seconds 3
    wpeutil shutdown
}

MgGraph-Authentication
