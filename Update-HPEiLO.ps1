<#
.SYNOPSIS
########################################################################################################
# Installs the latest iLO Firmware on iLO3/4/5 devices.                                                #
# Taken and expanded from orig Code: https://www.vgemba.net/microsoft/powershell/Update-HPE-iLO-Firmware/ 
# V2 - Added confirmation Loops                                                                        #
# V2.1 - Added check for PowerShell module existing.                                                     #
# V2.5- 1st attempt at adding iLO2 checks and updates                                                  #
# V2.5.5 - iLO 2 not supported so added checks and logging instead                                     #
########################################################################################################
# Renamed file to Update-HPEiLO as now includes iLO3 support.                                        #
# V3 - Added iLO 5 Support - renamed to Update-HPEiLO                                                  #
# V3.5 Split the download functions out. -Issue with $foundservers and iLO5                            #
# V3.6 Added correct syntax for $foundservers                                                          #
# V3.7 Added FirstRun parameter and reworked some find-Hpe ilo queries                                 #
# V3.8 Added Run As Administrator Requirement as some issues registering modules without               #
# V3.9 Issue found updating iLO3 with current MSI installer so reworked script to allow for older install
# v3.9.9 Tweaked script so one device can only be updated at a time due to limitations in iLO3
# v4.0 Added Import Module and .NET Check
########################################################################################################
#>

#requires -RunAsAdministrator
#requires -Version 5.0

[CmdletBinding()]
param(
    [parameter(ValueFromPipeline = $false, 
        ValueFromPipelineByPropertyName = $false, 
        Mandatory = $false)] 
    [switch]
    $FirstRun,
    [parameter(Mandatory = $true,
        HelpMessage = "Enter iLO IP Address or range in the format x.xx.1-254")]
    [string]
    $IPAddress
)

#Define Global Static Variables -DO NOT CHANGE
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$global:path = "C:\iLOFW"
$global:iLO2fwVersion = "2.33"
$global:iLO3fwVersion = "1.91"
$global:iLO4fwVersion = "2.73"
$global:iLO5fwVersion = "2.15"
$global:iLO2fwFile = "$global:path\ilo2_233.bin"
$global:iLO3fwFile = "$global:path\ilo3_191.bin"
$global:iLO4fwFile = "$global:path\ilo4_273.bin"
$global:iLO5fwFile = "$global:path\iLO5_215.bin"

function DownloadiLOs {

    #Download appropriate iLO Firmwares and extracts exe file so fw file can be obtained.    
    $iLOType = (Find-HPEiLO -Range $IPAddress -WarningAction SilentlyContinue -ErrorAction SilentlyContinue)
    
    if (($iLOType).PN -eq "Integrated Lights-Out 2 (iLO 2)") {
        $url2 = "https://jsstorageaccount.blob.core.windows.net/hpeilo/cp035237.exe?sv=2019-02-02&st=2020-05-19T10%3A00%3A02Z&se=2036-05-20T10%3A00%3A00Z&sr=b&sp=r&sig=44THkuA9x%2B6zZo5JKDxiVabN4yN3BhBp4Ugm3xuQk%2BI%3D"
        $output2 = "$global:path\cp035237.exe"
        #(New-Object System.Net.WebClient).DownloadFile($url2, $output2)
        Invoke-WebRequest -Uri $url2 -OutFile $output2
        Move-Item -Path $output2 -Destination $global:path\cp035237.zip
        Expand-Archive -Path $global:path\cp023068.zip -DestinationPath $global:path -Force
    }
    if (($iLOType).PN -eq "Integrated Lights-Out 3 (iLO 3)") {
        $url3 = "https://jsstorageaccount.blob.core.windows.net/hpeilo/cp037907.exe?sv=2019-02-02&st=2020-05-18T13%3A29%3A53Z&se=2040-05-19T13%3A29%3A00Z&sr=b&sp=r&sig=mOfxrMBjNvUVyFzgIlEs0loanWXoLD0fMmOnYIsNtIY%3D"
        $output3 = "$global:path\cp037907.exe"
        (New-Object System.Net.WebClient).DownloadFile($url3, $output3)
        Move-Item -Path $output3 -Destination $global:path\cp037907.zip
        Expand-Archive -Path $global:path\cp037907.zip -DestinationPath $global:path -Force
    }
    if (($iLOType).PN -eq "Integrated Lights-Out 4 (iLO 4)") {
        $url4 = "https://jsstorageaccount.blob.core.windows.net/hpeilo/cp042664.exe?sv=2019-02-02&st=2020-05-18T13%3A27%3A06Z&se=2040-07-20T13%3A27%3A00Z&sr=b&sp=r&sig=D%2B9Hi2oVFxEI4Chpx2WQ4ORaFWZ1QBwWVJDRNUadMQs%3D"
        $output4 = "$global:path\cp042664.exe"
        (New-Object System.Net.WebClient).DownloadFile($url4, $output4)
        Move-Item -Path $output4 -Destination $global:path\cp042664.zip -Force
        Expand-Archive -Path $global:path\cp042664.zip -DestinationPath $global:path -Force
    }
    if (($iLOType).PN -eq "Integrated Lights-Out 5 (iLO 5)") {
        $url5 = "https://jsstorageaccount.blob.core.windows.net/hpeilo/cp043129.exe?sv=2019-02-02&st=2020-05-18T13%3A28%3A52Z&se=2040-05-19T13%3A28%3A00Z&sr=b&sp=r&sig=UFrJ90RTgqtqi%2BlQq6Q9mQskILRdQHv5Wgl40nmDRr8%3D"
        $output5 = "$global:path\cp043129.exe"
        (New-Object System.Net.WebClient).DownloadFile($url5, $output5)
        Move-Item -Path $output5 -Destination $global:path\cp043129.zip -Force
        Expand-Archive -Path $global:path\cp043129.zip -DestinationPath $global:path -Force        
    }
    else {
    Write-Warning -Message "Something went wrong obtaining iLO version. Script will now exit..."
    }    
}
function DownloadPwShMod {
    #Downloads PowerShell Module .msi from Azure blob Storage    
    $urlps = "https://jsstorageaccount.blob.core.windows.net/hpeilo/HPEiLOCmdlets.msi?sv=2019-02-02&st=2020-05-19T16%3A14%3A26Z&se=2040-05-20T16%3A14%3A00Z&sr=b&sp=r&sig=UTdkJv5sPHm%2BGJsQEmY4z6ZecOJi5nXjYfCf2DWJ%2FaQ%3D"    
    $outputps = "$global:path\HPEiLOCmdlets.msi"
    (New-Object System.Net.WebClient).DownloadFile($urlps, $outputps)
    #Installs PowerShell cmdlets and adds them to PSModulePath so you don't have to Import-Module each time.
    Start-Process msiexec.exe -Wait -ArgumentList "/I C:\iLOFW\HPEiLOCmdlets.msi /quiet"
    $env:PSModulePath += ";C:\Program Files (x86)\Hewlett Packard Enterprise\PowerShell\Modules" 
}


function DownloadPwShModiLO3 {
    #Downloads earlier version of Module .msi so iLO3 can be updated
    $urlps = "https://jsstorageaccount.blob.core.windows.net/hpeilo/HPiLOCmdlets-x64.msi?st=2018-12-20T12%3A35%3A12Z&se=2022-12-21T02%3A35%3A00Z&sp=rl&sv=2018-03-28&sr=b&sig=sLRMhd%2Fy2EUVdraXDizokTJa%2BFCPTPAGQSbWoGQtOJ8%3D"
    $outputps = "$global:path\HPiLOCmdlets-x64.msi"
    (New-Object System.Net.WebClient).DownloadFile($urlps, $outputps)
    Start-Process msiexec.exe -Wait -ArgumentList "/I C:\iLOFW\HPiLOCmdlets-x64.msi /quiet"
}

function Update-HPEiLO {
    #beginfunction Update-HPEiLO
    $global:username = Read-Host -Prompt "Please enter your iLO Username"
    $global:password = Read-Host -Prompt "Please enter your iLO Password" -AsSecureString
    Import-Module HPEiLOCmdlets -ErrorAction SilentlyContinue
    $credential = New-Object -TypeName "System.Management.Automation.PSCredential" -ArgumentList $global:username, $global:password
    # Find all iLO's that don't match the required version quit if none found.
    $foundServers = Find-HPEiLO -Range $IPAddress -WarningAction SilentlyContinue | Where-Object { ($_.PN -ne "Integrated Lights-Out 2 (iLO 2)") -and ($global:iLO3fwVersion, $global:iLO4fwVersion, $global:iLO5fwVersion -notcontains $_.FWRI) }
    if (!($foundServers)) {
        Remove-Item -Path $global:path -Recurse -Force | Out-Null
        Write-Warning "No iLO Devices found or none that require updates. Exiting..."
    }
    else {
        Write-Host -ForegroundColor Green "iLO's requiring updates found. Connecting..."
        $foundServers
        # Connect to the iLOs that need updating
        $connection = $foundServers | Connect-HPEiLO -Credential $credential -DisableCertificateAuthentication -WarningAction SilentlyContinue -ErrorAction Stop 
        #Update iLO Firmware -check for versions
        $confirmation = Read-Host "Script will now update iLO Firmware to latest version. Are you sure you want to do this? [y/n]"
        while ($confirmation -ne "y") {
            if ($confirmation -eq "n") { Exit }
            $confirmation = Read-Host "Script will now update iLO Firmware to latest version. Are you sure you want to do this? [y/n]"     
        }
    
        if (($foundServers).PN -eq "Integrated Lights-Out 3 (iLO 3)") {
            Import-Module HPiLOCmdlets
            Update-HPiLOFirmware -Server $IPAddress -Credential $credential -Location $global:iLO3fwFile -DisableCertificateAuthentication -Confirm:$false -WarningAction SilentlyContinue    
        }
        if (($foundServers).PN -eq "Integrated Lights-Out 4 (iLO 4)") {
            Update-HPEiLOFirmware -Connection $connection -Location $global:iLO4fwFile -Confirm:$false -WarningAction SilentlyContinue
        }
        if (($foundServers).PN -eq "Integrated Lights-Out 5 (iLO 5)") {
            Update-HPEiLOFirmware -Connection $connection -Location $global:iLO5fwFile -Confirm:$false -WarningAction SilentlyContinue
        }      
        #Confirm iLO Update 
        Write-Host -ForegroundColor Green "iLO firmware now updated..."
        Find-HPEiLO -Range $IPAddress -WarningAction SilentlyContinue
        Start-Sleep -Seconds 10

        #Disconnect from iLO after update
        Disconnect-HPEiLO -Connection $connection | Write-Host -ForegroundColor Green "Disconnected from iLO" -ErrorAction SilentlyContinue
        Remove-Item -Path $global:path -Recurse -Force | Out-Null
    }
}

#Test for Path - Create if not found.
If (!(Test-Path $global:path)) {
    New-Item -ItemType Directory -Force -Path $global:path | Out-Null
}
if ($FirstRun -eq $true) {
    Write-Host -ForegroundColor Green "FirstRun flag specified. `n Script will install HPE PowerShell Modules and run in reporting mode only..."
    $dotnet = Get-ItemProperty "HKLM:SOFTWARE\Microsoft\NET Framework Setup\NDP\v4\Full"
    if (!($dotnet)) {
        Write-Warning -Message ".NET Framework not installed. Please install, reboot and run script again."
        Exit
    }
    Start-Transcript -Path "$global:path\iLODevices.txt" -Append
    #DownloadPwShMod
    Install-Module HPEiLOCmdlets
    Import-Module HPEiLOCmdlets
    $firstrunilo = Find-HPEiLO -Range $IPAddress -WarningAction SilentlyContinue | Where-Object { $global:iLO3fwVersion, $global:iLO4fwVersion, $global:iLO5fwVersion -notcontains $_.FWRI }
    if ($null -ne $firstrunilo) {
        Write-Warning -Message "Potentially insecure iLO Firmware found."
    }
    if (($firstrunilo).PN -eq "Integrated Lights-Out 2 (iLO 2)") {
        Write-Host -ForegroundColor Yellow "An iLO 2 device was found. This cannot be updated automatically by this script."
        #Start-Sleep -Seconds 5
    }
    if (($firstrunilo).PN -eq "Integrated Lights-Out 3 (iLO 3)") {
        DownloadPwShModiLO3
    }
    if (($firstrunilo).PN -eq "Integrated Lights-Out 4 (iLO 4)" -or "Integrated Lights-Out 5 (iLO 5)") {
        #Start-Sleep -Seconds 5
    }
    else {
        Write-Host -ForegroundColor Yellow "iLO Firmware appears to be up to date"
    }
    $firstrunilo
    Stop-Transcript
    Exit
}
#Runs the DownloadiLOs function
DownloadiLOs
#Runs the Update-HPEiLO function
Update-HPEiLO