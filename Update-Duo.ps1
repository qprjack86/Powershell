#Script created by Jack Stalley - 01/07/23
#Script originally developed to fix vulnerability in Duo for RDP as per - https://nvd.nist.gov/vuln/detail/CVE-2023-20123
# v1.0 - Original script used Azure fileshare to download latest msi


#Force TLS 1.2 as Azure Storage Account requires it.
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

Function Set-Duo {
$DuoInstall= 'C:\Program Files\Duo Security\WindowsLogon\DuoCredFilter.dll'
If (!(Test-Path "$DuoInstall") -or (Get-Item "$DuoInstall").VersionInfo.FileVersion -eq '4.2.2.1755') {
    Write-Warning -Message 'Duo either not installed so cannot be updated, or already updated to latest version. Script will now exit.'
    exit
}
}

Function Get-Duo {
    $DownloadDir="C:\Duo"
    If (!(Test-Path "$DownloadDir")) {
        New-Item -ItemType Directory -Force -Path $DownloadDir | Out-Null
    }
    #Get Duo file
    $duofileoutput = "$DownloadDir\DuoWindowsLogon64.msi"
    Invoke-WebRequest -Uri "https://cwlmisc.blob.core.windows.net/duo/DuoWindowsLogon64.msi?sv=2021-10-04&st=2023-06-26T16%3A11%3A43Z&se=2023-12-27T17%3A11%3A00Z&sr=b&sp=r&sig=%2BZ3iO1BA73ezHesjjQTrVqyvsI1qo53cn4iMZuW7tAk%3D" -OutFile $duofileoutput |Out-Null
    }       
    
    Function Install-Duo {

            $duo_msi= "C:\Duo\DuoWindowsLogon64.msi"
    
        Start-Process -FilePath 'C:\Windows\System32\msiexec.exe' -ArgumentList " /qn /i $duo_msi"-NoNewWindow -Wait
        Write-Host 'Duo client updated successfully.'
    }
    #Script Entry point
    #Check Duo Installed
    Set-Duo

    #Download Duo
    Get-Duo
    
    #Install Duo
    Install-Duo

    #Tidy Up Downloads folder
    Remove-Item 'C:\Duo' -Force -Recurse
    
    