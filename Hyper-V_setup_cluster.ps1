#Setup your Hyper-V Host Servers
$ComputerName=”<NameYourHyperVHost>” # (e.g. “HVC-NoInsde1”)
Rename-Computer -NewName $ComputerName -Confirm $False
Install-WindowsFeature –Name Hyper-V -IncludeManagementTools -NoRestart -Confirm:$False
Install-WindowsFeature -Name Failover-Clustering –IncludeManagementTools -Confirm:$False
Enable-WindowsOptionalFeature –Online –FeatureName MultiPathIO
Restart-Computer

#Disable VMQ on 1GBS links leave on 10GB
Get-NetAdapterVmq | Set-NetAdapterVmq -Enabled $False

#enable jumbo frames in Windows GUI to physical nics
#Note: You should repeat Jumbo frame configuration on the virtual network adapters for Live Migration and CSV, as well, once they exist.
$nics= Get-NetAdapter
foreach ($nic in $nics) {
Set-NetAdapterAdvancedProperty -Name $nic -RegistryKeyword '*JumboPacket' -RegistryValue '9014'    
}

#Enable VLAN aware on physical NIC's -https://social.technet.microsoft.com/Forums/windows/en-US/455990de-3307-411c-baa5-3184fd3d418a/hyperv-virtual-switch-and-vlan-tagging-not-working?forum=winserverhyperv

#Configure SET vSwitch for 2022
New-VMSwitch -Name "vSWITCH" -NetAdapterName "NIC1","NIC2" -AllowManagementOS $false -EnableEmbeddedTeaming $true -MinimumBandwidthMode Weight

#Configure the Management Network
$MgmtAlias=”Management” # (e.g. “Management”)
$MgmtVlan=”<VlanIDforMgmt>” # (.e.g. “10”)
$MgmtIP=”<ManagementIPAddress>” # (e.g. “10.10.71.10”)
$MgmtGateway=”<GatewayIPAddress>” # (e.g. “10.10.71.1”)
$DNS=”<ADDNSServerIPAddress>” # (e.g. “10.10.1.4”)
Add-VMNetworkAdapter -ManagementOS -Name $MgmtAlias -SwitchName $SwitchName
Set-VMNetworkAdapterVLAN –ManagementOS –VMNetworkAdapterName $MgmtAlias -Access -VlanId $MgmtVlan
New-NetIPAddress -InterfaceAlias $MgmtAlias -IPAddress $MgmtIP -PrefixLength 24 -DefaultGateway $MgmtGateway
Set-DnsClientServerAddress -InterfaceAlias $MgmtAlias -ServerAddresses $DNS

#Configure the Live Migration Network
$LMAlias=”<NetworkAdapterNameForLM>” # (e.g. “Live Migration”)
$LMVlan=”<VLANIDforLM>” # (e.g. “20”)
$LMIP=”<LMIPAddress>” # (e.g. “10.10.72.10”)
Add-VMNetworkAdapter -ManagementOS -Name $LMAlias -SwitchName $SwitchName
Set-VMNetworkAdapterVLAN –ManagementOS –VMNetworkAdapterName $LMAlias -Access -VlanId $LMVlan
New-NetIPAddress -InterfaceAlias $LMAlias -IPAddress $LMIP -PrefixLength 24

#Configure the Cluster Network
$CSVAlias=”<NetworkAdapterNameForCSV>” # (e.g. “CSV Cluster”)
$CSVVlan=”<VLANIDforCSV>” # (e.g. “30”)
$CSVIP=”<CSVIPAddress>” # (e.g. “10.10.73.10”)
Add-VMNetworkAdapter -ManagementOS -Name $CSVAlias -SwitchName $SwitchName
Set-VMNetworkAdapterVLAN –ManagementOS –VMNetworkAdapterName $CSVAlias -Access -VlanId $CSVVlan
New-NetIPAddress -InterfaceAlias $CSVAlias -IPAddress $CSVIP -PrefixLength 24

#Apply QoS Policy -Only if required
#Set-VMSwitch -Name $SwitchName -DefaultFlowMinimumBandwidthWeight 50
#Set-VMNetworkAdapter -ManagementOS -Name $MgmtAlias -MinimumBandwidthWeight 10
#Set-VMNetworkAdapter -ManagementOS -Name $LMAlias -MinimumBandwidthWeight 20
#Set-VMNetworkAdapter -ManagementOS -Name $CSVAlias -MinimumBandwidthWeight 20

#Join the Domain
$Domain=”<DomainName>” # (e.g. “Company.local”)
$User=”<UserName>” # (e.g. “hvadmin”)
$OUPath=”<OUPath>” # (e.g. “OU=HyperVHosts,DC=Company,DC=local”)
Add-Computer -Credential $Domain\$User -DomainName $Domain -OUPath $OUPath
Restart-Computer

#Setup the Cluster
$ClusterName=”hvcluster” # (e.g. “HVCluster”)
$ClusterIP=”128.232.243.15” # (e.g. “10.10.71.15”)
$Node1=”host3” # (e.g. “HVC-Node1″)
$Node2=”host4” # (e.g. “HVC-Node2”)
New-Cluster -Name $ClusterName -Node $Node1,$Node2 -StaticAddress $ClusterIP -NoStorage

#Friendly Rename of Cluster Networks
$MgmtNet=”194.10.80.0” # (e.g. “10.10.71.0”)
$LMNet=”194.10.82.0” # (e.g. “10.10.72.0”)
$CSVNet=”194.10.81.0” # (e.g. “10.10.73.0”)
(Get-ClusterNetwork | where-object {$_.Address -eq $MgmtNet}).Name = “MGMT”
(Get-ClusterNetwork | where-object {$_.Address -eq $LMNet}).Name = “LM”
(Get-ClusterNetwork | where-object {$_.Address -eq $CSVNet}).Name = “CSV”

#Set the cluster CSV network priority
(Get-ClusterNetwork CSV).Metric = 900

#Configure Live Migration Network to just use that for LM
#$ClusterNetworkMGMT = Get-Clusternetwork MGMT
$ClusterNetworkLM = Get-Clusternetwork LM
$ClusterNetworkCSV = Get-Clusternetwork CSV
$includeIDs = $ClusterNetworkLM.id
$excludeIDs = $ClusterNetworkMGMT.id + “;” + $ClusterNetworkCSV.id
Set-ItemProperty -Path “HKLM:\Cluster\ResourceTypes\Virtual Machine\Parameters” -Name MigrationExcludeNetworks -Value $excludeIDs
Set-ItemProperty -Path “HKLM:\Cluster\ResourceTypes\Virtual Machine\Parameters” -Name MigrationNetworkOrder -Value $includeIDs

#Add Storage
#Bring Disks Online
Get-Disk | Where-Object IsOffline –Eq $True | Set-Disk –IsOffline $False
#Enable Support for MPIO
New-MSDSMSupportedHW -AllApplicable
Restart-Computer

#Initialize Disks & Format Partitions
$NewDisks=Get-Disk | Where-Object PartitionStyle -Eq RAW
Initialize-Disk -InputObject $NewDisks -Confirm:$False
Get-Partition | Where-Object NoDefaultDriveLetter -eq $True | Format-Volume -FileSystem NTFS -Confirm:$False

#Add Cluster Storage & Create CSV’s
Get-ClusterAvailableDisk | Add-ClusterDisk
Get-ClusterResource | Where-Object {$_.OwnerGroup –eq “Available Storage”} | Add-ClusterSharedVolume

#Set CSV Block Cache Size -Improves Read Performance
(Get–Cluster).BlockCacheSize = 512

#Set Default Virtual Machine Storage Locations
$Host1=”srv-hv-01” # (e.g. HVC-NODE1)
$Host2=”srv-hv-02” # (e.g. HVC-NODE2)
$VMPath=”C:\ClusterStorage\Volume1\VM” # (e.g. C:\ClusterStorage\Volume1\ProductionVM)
$VHDPath=”C:\ClusterStorage\Volume1\VHD” # (e.g. C:\ClusterStorage\Volume1\ProductionVHD)
set-vmhost -ComputerName $Host1 -VirtualHardDiskPath $VHDPath -VirtualMachinePath $VMPath
set-vmhost -ComputerName $Host2 -VirtualHardDiskPath $VHDPath -VirtualMachinePath $VMPath

