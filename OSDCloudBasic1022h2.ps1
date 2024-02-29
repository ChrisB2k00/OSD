## This script will check if the device is in Autopilot. If it is, it will print the group tag of the device.
## It will then proceed to remove the Intune record if required, then install Windows & drivers

$winVer = "Windows 10 22H2 x64"

function Start-TPMAttestationFix {
    ## Creates registry key to fix TPM attestation error that can sometimes appear during Autopilot
    Write-Host "Adding registry key for TPM attestation fix" -ForegroundColor Cyan
    reg add HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Setup\OOBE /v SetupDisplayedEula /t REG_DWORD /d 00000001 /f
    Write-Host "Reg key added!" -ForegroundColor Green
}

function Start-OSD {

    ## Install Windows Version listed at top of script, Enterprise, GB language, allow taking screenshots, ZTI so no prompts, skip adding Autopilot profile JSON
    Start-OSDCloud -OSName "$winVer" -OSEdition Pro -OSLanguage en-GB -Screenshot -ZTI -SkipAutopilot
    Write-Host "Build complete!" -ForegroundColor Green

    Start-TPMAttestationFix

    Write-Host "Shutting down in 3 seconds!" -ForegroundColor Cyan
    Start-Sleep -Seconds 3
    wpeutil shutdown
}


Write-Host "OSDCloud build automation with Autopilot enrolment" -ForegroundColor Cyan

Start-OSD

