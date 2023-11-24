## Amend this for internal build script e.g. when newer feature update is released - Might be a way to automate pulling through the latest version
$WindowsOSVersion = "Windows 11 22H2 x64"

function Start-Autopilot {

    Write-Host "Would you like to enrol this device into Autopilot?"

    $APChoice = Read-Host "Y for Yes or N for No"

    if ($APChoice -eq "Y")
    {
        Write-Host "Starting Autopilot Process"
        Start-AutopilotEnrolment
        Start-BuildSelection
    }
    elseif ($APChoice -eq "N")
    {
        Write-Host "Skipping Autopilot Enrolment"
        Start-BuildSelection
    }
    else
    {
        Write-Host "Invalid selection. Please try again."
        Start-Autopilot
    }

function Start-AutopilotEnrolment {
    $SerialNumber = (Get-WmiObject -Class Win32_BIOS).SerialNumber

    Write-Host "Welcome to Autopilot Enrolment"
    $GroupTag = Read-Host "Please enter your GroupTag (Case Sensitive)"
    $OutputFile = "X:\Autopilot\$SerialNumber.CSV"
    X:\Autopilot\Create_4kHash_using_OA3_Tool.ps1 -GroupTag $GroupTag -OutputFile $OutputFile
    ## NOT FINISHED - NEED TO EITHER GET IT TO ASK THE USER WHERE TO SAVE THE OUTPUT FILE, OR AUTOMATE IT UPLOADING
function Start-BuildSelection {
    Write-Host "Which build would you like to run?"
    Write-Host "1) Internal Build (Automated, will wipe the disk, install $WindowsOSVersion Enterprise, latest drivers and then shutdown"
    Write-Host "2) Install specific WIM file (Prompt for WIM choice from available WIM files, wipe the disk, install Windows, latest drivers, and then shutdown)"
    Write-Host "3) Show OSDCloud GUI for manual build"

    $Choice = Read-Host "Please select which build you would like to run"

    if ($Choice -eq "1")
        {
            Write-Host "Starting internal build"
            Start-OSDInternal
        }
    elseif ($Choice -eq "2")
        {
            Write-Host "Starting specific WIM file build"
            Start-OSDWIM
        }
    elseif ($Choice -eq "3")
        {
            Write-Host "Starting OSDCloud GUI"
            Start-OSDCloudGUI
            Write-Host -ForegroundColor Green "Build complete!"

            ## Fix TPM Attestation issue seen before during Autopilot
            Start-TPMAttestationFix

            Write-Host -ForegroundColor Cyan "Shutting down in 3 seconds!"
            Start-Sleep -Seconds 3
            wpeutil shutdown
        }
    else
        {
            Write-Host "Invalid selection. Please try again."
            Start-BuildSelection
        }

}

function Start-OSDInternal {

    ## Install Windows Version listed at top of script, Enterprise, GB language, allow taking screenshots, ZTI so no prompts, skip adding Autopilot profile JSON
    Start-OSDCloud -OSName "$WindowsOSVersion" -OSEdition Enterprise -OSLanguage en-GB -Screenshot -ZTI -SkipAutopilot
    Write-Host -ForegroundColor Green "Build complete!"

    ## Fix TPM Attestation issue seen before during Autopilot
    Start-TPMAttestationFix

    Write-Host -ForegroundColor Cyan "Shutting down in 3 seconds!"
    Start-Sleep -Seconds 3
    wpeutil shutdown
}

function Start-OSDWIM {

    ## Connect to the shared location for WIM files
    net use * \\192.168.1.167\OSDCloud /user:Administrator

    ## Starts OSDCloud with the parameters to search for WIM files, Skip adding Autopilot profile JSON, Skip ODT, and Zero Touch Installation (No prompts throughout build process)
    Start-OSDCloud -FindImageFile -SkipAutopilot -SkipODT -ZTI
    Write-Host -ForegroundColor Green "Build complete!"

    ## Fix TPM Attestation issue seen before during Autopilot
    Start-TPMAttestationFix

    Write-Host -ForegroundColor Cyan "Shutting down in 3 seconds!"
    Start-Sleep -Seconds 3
    wpeutil shutdown
}

function Start-TPMAttestationFix {

    Write-Host -ForegroundColor Cyan "Adding registry key for TPM attestation fix"
    reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\OOBE /v SetupDisplayedEula /t REG_DWORD /d 00000001 /f
    Write-Host -ForegroundColor Cyan "Reg key added!"
}

Write-Host "Automated Building Process V1.0" -ForegroundColor Yellow
Start-Autopilot
Start-BuildSelection
