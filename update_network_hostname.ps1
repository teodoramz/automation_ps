##
#
#   FOR WINDOWS VMs
#   
#
#   Update network configuration and changing the computer hostname
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
    # This script uses the following: Name,EthernetInterface,NewIP,SubnetMask,Gateway,PrimaryDNS,SecondaryDNS,AdministratorAccount,Password,NewHostname
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
        $EthInt = $vm.EthernetInterface
        $newIP = $vm.NewIP
        $SubnetMask = $vm.SubnetMask
        $Gateway = $vm.Gateway
        $PrimaryDNS = $vm.PrimaryDNS
        $SecondaryDNS = $vm.SecondaryDNS    #optional
        $adm = $vm.AdministratorAccount
        $password = $vm.Password

        $newHostname = $vm.NewHostname


        # Creation of PSCredential object with an administrator account for the vm
        $securePassword = ConvertTo-SecureString $password -AsPlainText -Force
        $cred = New-Object System.Management.Automation.PSCredential ($adm, $securePassword)


        # Network config commands
        $cmdIP = "netsh interface ipv4 set address name=`"$EthInt`" static $newIP $SubnetMask $Gateway"
        $cmdDNS1 = "netsh interface ipv4 set dns name=`"$EthInt`" static $PrimaryDNS"
        $cmdDNS2 = "netsh interface ip add dns name=`"$EthInt`" $SecondaryDNS index=2"      # optional

        # Command for computer renaming
        $cmdHostname = "Rename-Computer -NewName $newHostname -Force -PassThru"
        
        # Command for rebooting the system
        $cmdReboot = "Restart-Computer -Force"



        # Edit the network configuration of the selected VM
        #
        # The VM is not edited if there is any name confusion or the VM does not exists
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


        # Changing the ip, network mask and the gateway
        $scriptResult = Invoke-VMScript -VM $vmObject -ScriptType Bat -ScriptText $cmdIP -Verbose -GuestCredential $cred
        $scriptOutput = $scriptResult.ScriptOutput
        Write-Host "Script output: $scriptOutput"

        # Changing the  primary DNS
        $scriptResult = Invoke-VMScript -VM $vmObject -ScriptType Bat -ScriptText $cmdDNS1 -Verbose -GuestCredential $cred
        $scriptOutput = $scriptResult.ScriptOutput
        Write-Host "Script output: $scriptOutput"

        # Adding a secondary DNS (optional)
        $scriptResult = Invoke-VMScript -VM $vmObject -ScriptType Bat -ScriptText $cmdDNS2 -Verbose -GuestCredential $cred
        $scriptOutput = $scriptResult.ScriptOutput
        Write-Host "Script output: $scriptOutput"


        Write-Host -ForegroundColor Green "Network settings updated for VM '$VMName'."


        # Changing hostname
        $scriptResult = Invoke-VMScript -VM $vmObject -ScriptType PowerShell -ScriptText $cmdHostname -Verbose -GuestCredential $cred
        $scriptOutput = $scriptResult.ScriptOutput
        Write-Host "Script output: $scriptOutput"

        # Reboot the system to make the changes persistent
        $scriptResult = Invoke-VMScript -VM $vmObject -ScriptType PowerShell -ScriptText $cmdReboot -Verbose -GuestCredential $cred
        $scriptOutput = $scriptResult.ScriptOutput
        Write-Host "Script output: $scriptOutput"
        

        Write-Host -ForegroundColor Green "Network settings and hostname changed for VM '$VMName'."
    }
    catch{
        Write-Warning -Message $("Something went wrong. Please read the error message. Error: "+ $_.Exception.Message)
        continue
    }
}

Set-PowerCLIConfiguration -InvalidCertificateAction Fail -Confirm:$false

Disconnect-VIServer -Server * -Confirm:$false