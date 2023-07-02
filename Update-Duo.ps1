#Script to fix vulnerability in Duo for RDP as per - https://nvd.nist.gov/vuln/detail/CVE-2023-20123

#Force TLS 1.2 as Storage account needs it
[Net.ServicePointManager]::SecurityProtocol =[Net.SecurityProtocolType]::Tls12

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
    }
    #Script Entry point

    #Download Duo
    Get-Duo
    
    #Install Duo
    Install-Duo

    #Tidy Up Downloads folder
    Remove-Item 'C:\Duo' -Force -Recurse
    