
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


    # Depending of your infrastructure, the data used to do the vms creation can differ
    # 
    # This script uses the following: Name,Template,Host,Datastore,vCPU,Memory,Network,Datacenter
    #
    $vms = Import-CSV "./vm_config.csv"

}
catch{
    Write-Warning -Message $("Something went wrong. Please read the error message and re-run the script. Error: "+ $_.Exception.Message)
    
    Set-PowerCLIConfiguration -InvalidCertificateAction Fail -Confirm:$false
    
    Disconnect-VIServer -Server * -Confirm:$false
    exit
}

foreach ($vm in $vms)
{
    try{
        $VMName = $vm.Name
        $Template = Get-Template | Where-Object { $_.Name -eq $vm.Template } | Select-Object -First 1
        $VMHost = Get-VMHost -Name $vm.Host -Location (Get-Datacenter -Name $vm.Datacenter)
        $Datastore = Get-Datastore -Name $vm.Datastore -Location (Get-Datacenter -Name $vm.Datacenter)
        $vCPU = $vm.vCPU
        $Memory = $vm.Memory
        $Network = $vm.Network     

        # Skipping creation of vm from a template if the template is null or there is a name confusion (aka multiple templates with same name)
        $templates = Get-Template | Where-Object { $_.Name -eq $vm.Template } 

        if ($templates.Count -gt 1) {
            Write-Warning "Multiple templates found with the same name '$($vm.Template)'. Skip  VM creation for '$($vm.Name)'..."
            continue
        }

        if ($Template -eq $null) {
            Write-Warning "Template '$($vm.Template)' not found. Skipping VM creation for '$VMName'."
            continue
        }


        # The actual creation of the VM
        New-VM -Name $VMName -Template $Template -VMHost $VMHost -StorageFormat Thin -Datastore $Datastore

        # Wait for the vm object to be initialised in vsphere
        Start-Sleep -Seconds 20


        # Edit the hardware configuration of the newly created VM
        #
        # The VM is not edited if there is any name confusion or the VM does not exists

        $VMs = Get-VM | Where-Object { $_.Name -eq $vm.Name }

        if ($VMs.Count -gt 1) {
            Write-Warning "Multiple VMs found with the same name '$($vm.Name)'. Skip  VM editing..."
            continue
        }
        
        
        $NewVM = Get-VM | Where-Object { $_.Name -eq $vm.Name } | Select-Object -First 1

        if ($NewVM -eq $null) {
            Write-Warning "VM created '$($vm.Name)' not found. Skip VM editing for '$VMName'."
            continue
        }

        $NewVM | Set-VM -MemoryGB $Memory -NumCpu $vCPU -Confirm:$false
        $NewVM | Get-NetworkAdapter | Set-NetworkAdapter -NetworkName $Network -Confirm:$false


        Start-VM -VM $NewVM -Confirm:$false
    }
    catch{
        Write-Warning -Message $("Something went wrong. Please read the error message. Error: "+ $_.Exception.Message)
        continue
    }
}

Set-PowerCLIConfiguration -InvalidCertificateAction Fail -Confirm:$false

Disconnect-VIServer -Server * -Confirm:$false
