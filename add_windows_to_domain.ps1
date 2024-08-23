##
#
#   FOR WINDOWS VMs
#
#
#   Adding a windows vm to a domain
#
##


# Not carring about tls verification
Set-PowerCLIConfiguration -InvalidCertificateAction Ignore -Confirm:$false

# The ip of the VSphere host 
$vmhostipaddress = Read-Host "Enter the IP of your VSphere Host"

try {

    # the credentials of a user with administration rights over vsphere
    $cred = Get-Credential

    # Connection
    Connect-VIServer -Server $vmhostipaddress -Credential $cred

    Write-Host -ForegroundColor Green ("Connected to (" + $vmhostipaddress + ") with user " + $cred.UserName ) 


    # Depending of your infrastructure, the data used to do the network modification of a vm can differ
    # 
    # This script uses the following: Name,AdministratorAccount,Password,DomainName,DomainUser,DomainPassword
    #
    $vms = Import-CSV "./vm_network_config.csv"

}
catch{
    Write-Warning -Message $("Something went wrong. Please read the error message and re-run the script. Error: "+ $_.Exception.Message)
    
    Set-PowerCLIConfiguration -InvalidCertificateAction Fail -Confirm:$false
    
    Disconnect-VIServer -Server * -Confirm:$false
    exit
}



foreach ($vm in $vms) {
    try{
        $VMName = $vm.Name
        
        $adm = $vm.AdministratorAccount
        $password = $vm.Password

        $domainName = $vm.DomainName
        $domainUser = $vm.DomainUser
        $domainPassword = $vm.DomainPassword

        # Creation of PSCredential object with an administrator account for the vm
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ($adm, $securePassword)

        # Creation of PSCredential object with a domain admin account for the vm
        $domainSecurePassword = ConvertTo-SecureString $domainPassword -AsPlainText -Force
        $domainCred = New-Object System.Management.Automation.PSCredential ($domainUser, $domainSecurePassword)

        # Command for adding the computer to a domain
        $cmdDomain = @"
Add-Computer -DomainName $domainName -Credential (New-Object System.Management.Automation.PSCredential("$domainUser", (ConvertTo-SecureString "$domainPassword" -AsPlainText -Force))) -Force -PassThru
"@

        # Command for rebooting the system
        $cmdReboot = "Restart-Computer -Force"
    

        # Adding the selected VM to a domain
        #
        # The VM is not added if there is any name confusion or the VM does not exists
        $vmObject = Get-VM | Where-Object { $_.Name -eq $vm.Name } | Select-Object -First 1

        if ($vmObject -eq $null) {
            Write-Warning "VM '$VMName' not found. Skipping..."
            continue
        }

        $VMs = Get-VM | Where-Object { $_.Name -eq $VMName }

        if ($VMs.Count -gt 1) {
            Write-Warning "Multiple VMs found with the same name '$VMName'. Skipping VM editing..."
            continue
        }



        # Adding the computer to the domain
        #
        #  ( check update_network_hostname.ps1 if you want to change the computer's hostname before adding it to the domain )
        #
        $scriptResult = Invoke-VMScript -VM $vmObject -ScriptType PowerShell -ScriptText $cmdDomain -Verbose -GuestCredential $cred
        $scriptOutput = $scriptResult.ScriptOutput
        Write-Host "Script output: $scriptOutput"

        # Reboot the system
        $scriptResult = Invoke-VMScript -VM $vmObject -ScriptType PowerShell -ScriptText $cmdReboot -Verbose -GuestCredential $cred
        $scriptOutput = $scriptResult.ScriptOutput
        Write-Host "Script output: $scriptOutput"
        
        Write-Host -ForegroundColor Green "Domain join updated for VM '$VMName'."
    }
    catch{
        Write-Warning -Message $("Something went wrong. Please read the error message. Error: "+ $_.Exception.Message)
        continue
    }
}

Set-PowerCLIConfiguration -InvalidCertificateAction Fail -Confirm:$false

Disconnect-VIServer -Server * -Confirm:$false