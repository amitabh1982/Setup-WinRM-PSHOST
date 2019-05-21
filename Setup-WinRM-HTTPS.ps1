#Script to configure WinRM for use with vRO as a Powershell host, but generic enough to work for anyone. 
#Install and configures a https listener on all interfaces with a self signed certificate that lasts 5 years.
#Disables BASIC auth, says no to AllowUnencrypted, locks down to specific trusted host(s) & deletes any http listeners.
#Built and tested on W2K16 with Powershell 5.1
#v1.0 vMan.ch, 19.05.2019 - Initial Version

#Usage IPs ---> vRO host IP
#CN ---> common name used for cert.


param
(
    [String]$IPs = '192.168.16.69',
    [String]$CN = 'winsrv01.vman.ch'
)

$WinRM = Get-Service WinRM -ComputerName . | Select Status

Write-Host "Checking if WinRM is already running" -ForegroundColor Yellow

If ($WinRM.Status -eq 'Running') {

    Write-Host "WinRM is already installed and running, checking config" -ForegroundColor Green

    #Check if Cert exists if not create it

    Write-Host "Checking if Self Signed Certificate for https listener exists" -ForegroundColor Yellow

    $CertLookup = Get-Childitem -Path Cert:\LocalMachine\my | where { $_.FriendlyName -eq 'Self Signed cert for vRO Powershell Host'}

        If ($CertLookup.Subject -eq 'CN='+$CN)
            {
                Write-Host "Found Self Signed cert for vRO Powershell for $CN... checking if WinRM listener running with this cert" -ForegroundColor Yellow

                $CheckListner = Get-ChildItem -recurse WSMan:\localhost\Listener | where {$_.Value -eq $CertLookup.Thumbprint}

                #Check if cert is running on a listener

                If ($CheckListner)
                    {
                    Write-Host "WinRM listener running with the correct cert, nothing to do.... moving to lockdown settings" -ForegroundColor Green                        
                    }

            }
        else
            {

                Write-Host "Unable to find Self Signed Certificate for vRO Powershell Host, creating new cert, set to expire in 5 years from now" -ForegroundColor Red

                #Generating new self signed cert

                $cert = New-SelfSignedCertificate -DnsName $CN -CertStoreLocation Cert:\LocalMachine\My -FriendlyName 'Self Signed cert for vRO Powershell Host' -NotAfter (Get-Date).AddMonths(60)
               
                #Setup listener with new cert.

                $newListener = new-item -Path WSMan:\localhost\Listener -Force -Address '*' -Transport 'HTTPS' -CertificateThumbPrint $cert.thumbprint -HostName $CN

                If ($newListener){

                Write-Host "Host setup with new Listener" -ForegroundColor Green
                Write-Host $newListener.Name created -ForegroundColor Cyan
                }
                else
                {
                Write-Host "Computer said no, terminating" -ForegroundColor Red
                }

            }           

}

Else

{

Write-Host WinRM is not running, setup time -ForegroundColor Red

Enable-PSRemoting

Write-Host "Generating new Self Signed Certificate for vRO Powershell Host, set to expire in 5 years from now" -ForegroundColor Yellow

#Generating new self signed cert

$cert = New-SelfSignedCertificate -DnsName $CN -CertStoreLocation Cert:\LocalMachine\My -FriendlyName 'Self Signed cert for vRO Powershell Host' -NotAfter (Get-Date).AddMonths(60)

Write-Host Creating Listener with new certificate with thumbprint $cert.thumbprint -ForegroundColor Yellow

$Listener = new-item -Path WSMan:\localhost\Listener -Force -Address '*' -Transport 'HTTPS' -CertificateThumbPrint $cert.thumbprint -HostName $CN

Write-Host Host setup with new Listener $Listener.Name -ForegroundColor Green

}

#Locking down the Powershell host


        #Check then disable Basic Auth

        Write-Host "Check if Basic Auth is disabled" -ForegroundColor Yellow

        $CheckBasichAuth = get-item -Path WSMan:\localhost\Service\Auth\Basic | select Value 

        If ($CheckBasichAuth.Value -eq $true){

            Write-Host "Naughty Naughty, Disabling Basic Auth" -ForegroundColor Red

            set-item -Path WSMan:\localhost\Service\Auth\Basic -value $false -Force

        } 
        Else
        
        {
        Write-Host Good job, Basic Auth is already disabled on this host... skipping  -ForegroundColor Green
        }

        #Check then disable AllowUnencrypted

        Write-Host "Checking if encryption is enforced or if you are shouting your passwords down the street" -ForegroundColor Yellow

        $AllowUnencrypted = get-item wsman:\localhost\Client\AllowUnencrypted

        If ($AllowUnencrypted.value -eq $true){

            Write-Host "Naughty Naughty... why not just write your passwords down and hand them out to strangers, enforcing encryption" -ForegroundColor Red

            set-item wsman:\localhost\Client\AllowUnencrypted -value $false -Force
        } 
        Else 
        
        {
        Write-Host "Good job, encryption is enforced on this host... skipping" -ForegroundColor Green
        }

        #Check then lock down Allowed hosts to $IPs

        Write-Host "Checking if allowed hosts are set to $IPs" -ForegroundColor Yellow

        $TrustedHosts = get-item wsman:\localhost\Client\TrustedHosts

        If ($TrustedHosts.value -eq ''){

            Write-Host "Naughty Naughty... locking down to $IPs" -ForegroundColor Red

            set-item wsman:\localhost\Client\TrustedHosts -value $IPs -Force
        } 
        Else 
        
        {Write-Host Good job, already locked down to $TrustedHosts.Value -ForegroundColor Green}


        #Checking if CredSSP is enabled

        Write-Host "Checking if CredSSP is enabled" -ForegroundColor Yellow

        $TrustedHosts = get-item WSMan:\localhost\Client\Auth\CredSSP

        If ($TrustedHosts.value -eq $false){

            Write-Host "CredSSP is not enabled, fixing that right away!" -ForegroundColor Red

            set-item WSMan:\localhost\Client\Auth\CredSSP -value $true -Force
        } 
        Else 
        
        {Write-Host Good job, CredSSP already enabled -ForegroundColor Green}

   
   Write-Host "Searching for and removing HTTP listener if it exists"

   $ListenerList = Get-ChildItem -Path WSMan:\localhost\Listener

   ForEach ($LS in $ListenerList){

       $LSPath = 'WSMan:\localhost\Listener\' + $LS.Name

       $LSSearch = Get-ChildItem -Path $LSPath

           If ($LSSearch.Value -eq 'HTTP'){

           Remove-Item -Path $LSPath -Recurse -Force

           Write-Host Removed $LS.Name as it was using HTTP only.... naughty naughty -ForegroundColor Red
           }
           else
           {
           Write-Host All good didnt find any HTTP listeners -ForegroundColor Green
           }
   

   }
            

    Write-Host All done Restarting WinRM service for the lolz -ForegroundColor Green

    Restart-Service WinRM -Force

    $WinRM = Get-Service WinRM -ComputerName . | Select Status


    While ($WinRM.Status -ne 'Running'){

        $WinRM = Get-Service WinRM -ComputerName . | Select Status

        Write-Host WinRM is $WinRM.Status
    }

    Write-Host WinRM is now $WinRM.Status

    Write-Host "All done, Script terminated"
