<#
.SYNOPSIS
Installs the File Server Resource Manager role if not installed and then configured a file screen on all drives other than C. 
The file screen screens for possible ransomware infections and uppdates the list of files.

v2.0 - Removed 2008 R2 support as it's difficult to get consistent results.
     - Changed script to make it work on PowerShell Core
v3.0 - Added foreach loops to target multiple fileservers 

.PARAMETER Server
Specify the server the code will run on
#>

#Requires -Version 3.0 
#Requires -RunAsAdministrator

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'Low')]
param(
    [Parameter(
        Position = 0,
        ValueFromPipeline = $true,
        ValueFromPipelineByPropertyName = $true)]
    [string[]]
    $Server = @(),
    [Parameter()]
    [switch]
    $FirstRun
)

$Ver = (Get-CimInstance -ComputerName $Server win32_OperatingSystem -ErrorAction Stop).Version
# Check for Supported Windows Version 
if ($ver -eq '6.2' -or '6.3' -or '10.0' -or '10.0.17763') {
    Write-Host " "
    Write-Host "$Server are running a supported Operating System" -ForegroundColor Green
    Write-Host " "
    Write-Host "Script will now install and configure FSRM as appropriate" -ForegroundColor Green
    Write-Host " "
}
else {
    Write-Host " "
    throw "$Server are running a non-supported version of Windows Server.  Exiting the script." 
    Write-Host " "
}
function Get-FSRM {
    process {
        #Write-Host " "
        #Write-Host " "
        foreach ($Ser in $Server) {
            $checkFSRM = Get-WindowsFeature -ComputerName $Ser -Name FS-Resource-Manager
    
            if ($checkFSRM.Installed -eq $false -and $FirstRun -eq $true) {
                Install-FSRM
            }
            elseif ($checkFSRM.Installed -eq $true -and $FirstRun -eq $true) {
                Set-FSRM
            }
            else {
                Write-Host " "
                Write-Host "FSRM already installed and configured. Try running with -FirstRun to force re-install." -ForegroundColor Yellow
                Write-Host " "
            }
        }
    }
}   
function Install-FSRM {
    #Formatting
    #   Write-Host " "
    #  Write-Host " "
    foreach ($Ser in $Server) {    
        Install-WindowsFeature fs-resource-manager -ComputerName $Ser -IncludeManagementTools | Out-Null 
    }
    Write-Host "Rebooting $Server to enable FSRM PowerShell Modules...." -ForegroundColor Yellow
    #Write-Host " "
    Restart-Computer -ComputerName $Server -Force -Wait -For PowerShell
}
function Set-FSRM {
    process {
        Invoke-Command -ComputerName $Server -ScriptBlock {
            New-FsrmFileGroup -name "Ransomware Files" -IncludePattern @((Invoke-WebRequest -Uri "https://fsrm.experiant.ca/api/v1/combined" -UseBasicParsing).content | convertfrom-json | ForEach-Object { $_.filters })
            $FSRMTemplate = @"
<?xml version="1.0" ?><Root ><Header DatabaseVersion = '2.0' ></Header><QuotaTemplates ></QuotaTemplates><DatascreenTemplates ><DatascreenTemplate Name = 'RansomwareCheck' Id = '{122F5AB4-9DF0-4F09-B89E-0F7BDC9D46CC}' Flags = '1' Description = '' ><BlockedGroups ><FileGroup FileGroupId = '{FCD4D266-025D-4CEC-BCF5-BBFA939DF1A1}' Name = 'Ransomware%sFiles' ></FileGroup></BlockedGroups><FileGroupActions ><Action Type="1" Id="{73AFB339-FF17-42DC-B9B9-E7C9A8E7C9A9}" EventType="2" MessageText="User%s[Source%sIo%sOwner]%sattempted%sto%ssave%s[Source%sFile%sPath]%sto%s[File%sScreen%sPath]%son%sthe%s[Server]%sserver.%sThis%sfile%sis%sin%sthe%s[Violated%sFile%sGroup]%sfile%sgroup,%swhich%sis%snot%spermitted%son%sthe%sserver." /><Action Type="2" Id="{5F8A5821-5271-429D-A9BC-AFADC0C621EF}" MailFrom="" MailReplyTo="" MailTo="[Admin%sEmail]" MailCc="" MailBcc="" MailSubject="Unauthorized%sfile%sfrom%sthe%s[Violated%sFile%sGroup]%sfile%sgroup%sdetected" MessageText="User%s[Source%sIo%sOwner]%sattempted%sto%ssave%s[Source%sFile%sPath]%sto%s[File%sScreen%sPath]%son%sthe%s[Server]%sserver.%s%r%n%r%nThis%sfile%sis%sin%sthe%s[Violated%sFile%sGroup]%sfile%sgroup,%swhich%sis%snot%spermitted%son%sthe%sserver.%r%n%r%nImmediately%stake%sthe%suser&apos;s%scomputer%soff%sthe%snetwork%sand%scheck%sfor%sinfections.%s%sMay%sbe%sworth%sreinstalling%sthe%sOS,%sto%sbe%scertain." /></FileGroupActions></DatascreenTemplate></DatascreenTemplates><FileGroups ></FileGroups></Root>
"@
            $FSRMTemplate | Out-File -FilePath C:\users\public\FSRMTemplate.xml
            Filescrn template import /file:C:\users\public\FSRMTemplate.xml | Out-Null
            Remove-Item -path C:\Users\Public\FSRMTemplate.xml
            $disks = GET-WMIOBJECT win32_logicaldisk -filter "DriveType='3'" | Where-Object { $_.deviceid -ne "C:" }
            ForEach ($disk in $disks) {
                $DRIVE = $DISK.DeviceID
                New-FSRMFILEScreen -path $DRIVE -template "RansomwareCheck"
            }
            $psupdate = @"
Set-FsrmFileGroup -name "Ransomware Files" -IncludePattern @((Invoke-WebRequest -Uri "https://fsrm.experiant.ca/api/v1/combined" -UseBasicParsing).content | convertfrom-json | ForEach-Object {$_.filters})
"@
            if (!(Test-path -path "C:\Scripts")) {
                New-item -ItemType Directory -path "C:\Scripts" | Out-Null
            }
            $psupdate | Out-File -FilePath "C:\Scripts\Update-FSRMRansomware.ps1"
            
            $Action = New-ScheduledTaskAction -execute "PowerShell.exe" -Argument "-ExecutionPolicy Bypass C:\Scripts\Update-FSRMRansomware.ps1"
            $Trigger = New-ScheduledTaskTrigger -Daily -At '12AM'
            $msg = "Enter the username and password that will run the Scheduled Task";
            $credential = $Host.UI.PromptForCredential("Task Username and password", $msg, "$env:USERDOMAIN\$env:USERNAME", $env:USERDOMAIN)
            $username = $credential.Username
            $password = $credential.GetNetworkCredential().password
            Register-ScheduledTask -TaskName "Update-FSRMRansomware" -Description "Scheduled Task to update FSRM file lists from web." -Trigger $Trigger -User $username -Password $password -Action $Action -RunLevel Highest
        }
    }
}    
Get-FSRM