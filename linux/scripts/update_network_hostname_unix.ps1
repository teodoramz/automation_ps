##
#
#   FOR LINUX VMs
#   
#
#   Update network configuration and changing the computer hostname
#
##


#
# example of config (cmd line)
#
# network config (ip, gateway, dns)
# echo "1234" | sudo -S netplan set ethernets.ens33.addresses=[192.168.150.170/24]
# echo "1234" | sudo -S netplan set ethernets.ens33.gateway4=192.168.150.2
# echo "1234"| sudo -S netplan set ethernets.ens33.nameservers.addresses=[192.168.150.2,8.8.8.8] # at least one dns

# # apply the changes
# echo "1234" | sudo -S netplan apply

# # new hostname
# echo "1234" | sudo -S hostnamectl set-hostname "smthelse"

# # optional (to be sure)
# echo "1234" | sudo -S systemctl restart NetworkManager

# # system reboot to make sure that changes are applied
# echo "1234" | sudo -S reboot


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
    $vms = Import-CSV "../config/vm_network_config.csv"

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

        # Install netplan
        # be sure that the template has netplan installed

        # Network config commands
       # --- 1) ştergi toate adresele de pe interfaţă ---
        $cmdIPFlush = "echo `'$password`' | sudo -S ip addr flush dev $EthInt"

        # --- 2) adaugi noul IP + mască ---
        $cmdIPAdd = "echo `'$password`' | sudo -S ip addr add $newIP/$Mask dev $EthInt"

        
        # --- 3) setezi ruta default (gateway) ---
        $cmdRoute = "echo `'$password`' | sudo -S ip route replace default via $Gateway dev $EthInt"
        
        $cmdDNS = "echo `'$password`' | sudo -S bash -c 'echo -e `"nameserver $DNS1\nnameserver $DNS2`" > /etc/resolv.conf'"

        # Command for computer renaming
        $cmdHostname = "echo `'$password`' | sudo -S hostnamectl set-hostname $newHostname"

        $cmdNetworkReset = "echo `'$password`' | sudo -S systemctl restart NetworkManager"
        
        # Command for rebooting the system
        $cmdReboot = "echo `'$password`' | sudo -S reboot"
 

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
        $scriptResult = Invoke-VMScript -VM $vmObject -ScriptType Bash -ScriptText $cmdIPFlush -Verbose -GuestCredential $cred
        $scriptOutput = $scriptResult.ScriptOutput
        Write-Host "Script output: $scriptOutput"

        $scriptResult = Invoke-VMScript -VM $vmObject -ScriptType Bash -ScriptText $cmdIPAdd -Verbose -GuestCredential $cred
        $scriptOutput = $scriptResult.ScriptOutput
        Write-Host "Script output: $scriptOutput"

        $scriptResult = Invoke-VMScript -VM $vmObject -ScriptType Bash -ScriptText $cmdRoute -Verbose -GuestCredential $cred
        $scriptOutput = $scriptResult.ScriptOutput
        Write-Host "Script output: $scriptOutput"

        $scriptResult = Invoke-VMScript -VM $vmObject -ScriptType Bash -ScriptText $cmdDNS -Verbose -GuestCredential $cred
        $scriptOutput = $scriptResult.ScriptOutput
        Write-Host "Script output: $scriptOutput"


        $scriptResult = Invoke-VMScript -VM $vmObject -ScriptType Bash -ScriptText $cmdNetworkReset -Verbose -GuestCredential $cred
        $scriptOutput = $scriptResult.ScriptOutput
        Write-Host "Script output: $scriptOutput"

        Write-Host -ForegroundColor Green "Network settings updated for VM '$VMName'."


        # Changing hostname
        $scriptResult = Invoke-VMScript -VM $vmObject -ScriptType Bash -ScriptText $cmdHostname -Verbose -GuestCredential $cred
        $scriptOutput = $scriptResult.ScriptOutput
        Write-Host "Script output: $scriptOutput"

        # Reboot the system to make the changes persistent
        $scriptResult = Invoke-VMScript -VM $vmObject -ScriptType Bash -ScriptText $cmdReboot -Verbose -GuestCredential $cred
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