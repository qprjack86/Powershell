[CmdletBinding()]
param (
    [Parameter()] [string] $SourceHost,
    [Parameter()] [string] $DestHost,
    [Parameter()] [string] $vcserver
)

$vccreds = Get-Credential -Message "Enter login details for VCenter Server"
try {
    #Connect to VCenter
    Connect-VIServer -Server $vcserver -Credential $vccreds
}
catch {
    Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false
    Write-Warning -Message "Issue with Connecting to VCenter due to self signed cert. Re-run script and it should connect."
}
#Document VM's on host
(get-vm -Location $SourceHost).Name | Out-File $env:USERPROFILE\Desktop\$($SourceHost)_vms.txt
$VMs = Get-Content $env:USERPROFILE\Desktop\$($SourceHost)_vms.txt

#Evacuate host
Write-Host -ForegroundColor Yellow "VM's on $SourceHost moving to $DestHost"
get-vm -Location $SourceHost | Move-VM -Destination (Get-VMHost $DestHost) |Out-Null 

#Set Maintenance mode
get-vmhost $SourceHost | Set-VMHost -State Maintenance|Out-Null
Write-Host -ForegroundColor Yellow "Host in Maintenance Mode. Remove Maintenance Mode in VCenter to move VM's back."
do {
    Start-Sleep 5
    $VMHostState = (Get-VMHost $SourceHost).State
    } 
while  ($VMHostState -eq 'Maintenance')

if ($VMHostState -eq 'Connected') 
{
#Move back
Move-VM -VM $VMs -Destination (Get-VMHost $SourceHost)|Out-Null
}

#Cleanup
Remove-Item $env:USERPROFILE\Desktop\$($SourceHost)_vms.txt