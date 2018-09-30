<#
Matt Cowen, August 2018

Creates virtual machines in parallel each in their own resource group and runs performance tests
outputting the results to blob storage. It then deletes each resource group once the test is complete.

Steps

1. You need to create a few resources: a key vault, storage account
2. Add the storage key to key vault "storageKey" secret. Pass in the $storageKey value below too.
3. Add "password" secret to key vault for vm admin credentials (username can be set below)
4. Upload DiskSpd zip to the artifacts container in the results storage account and update download url below
5. Ensure artifacts container is publically accessible


#>
#Disconnect-AzureRMAccount
#Login-AzureRmAccount -Subscription '4f50786d-0c67-4da6-b423-8c3950bc2b3c' -TenantId 10f302d8-3649-4cb2-99aa-b10d766bd3b0



param
(
    [PSCredential]$cred,
    [String]$baseResourceGroup = 'StackTesting', # where the vnet is deployed
    [String]$location = 'northeurope',    
    [String]$resultsStorageAccountName = 'mctestharness', # where the results from performance counters are saved
    [String]$resultsStorageAccountRg = 'MgcTestHarness',
    [String]$resultsContainerName = 'stacktestresults', # the container for uploading the results of the performance test
    
    [String]$artifactsContainerName = 'artifacts',  # the container for uploading the published DSC configuration
    [Int32]$pauseBetweenVmCreateInSeconds = 0,
    [Int32]$totalVmCount = 10,
    [String]$storageKey,  # the storage key for the results storage account
    [System.IO.FileInfo]$diskSpd = ".\DiskSpd-2.0.20a.zip",
    
    [String]$vmAdminUsername = 'mcowen',
	[String]$vmNamePrefix = 'ramp1-',
	[String]$vmsize = 'Standard_D4s_v3',   # the size of VM
    [String]$armTemplateFilePath = '.\windowsvirtualmachine.json',
    [String]$armTemplateParamsFilePath = '.\windowsvirtualmachine.parameters.json',
	[String]$diskSpdDownloadUrl = "https://gallery.technet.microsoft.com/DiskSpd-A-Robust-Storage-6ef84e62/file/199535/1/DiskSpd-2.0.20a.zip",
    [String]$testParams = '-c200M -t2 -o20 -d30 -w50',     # the parameters for DiskSpd
    [String]$dscPath = 'C:\dev\mod\StackTesting\StackTesting\DSC\DiskPrepTest.ps1',     # the path to the DSC configuration to run on the VMs
    [String]$storageUrlDomain = 'blob.core.windows.net',
	[switch]$deployArmTemplate # needed for initial deployment to create vnet or if you need to upload artifacts

)



if($deployArmTemplate){

# deploy the vnet and the first vm(s)
.\Deploy-AzureResourceGroup.ps1 -StorageAccountName $resultsStorageAccountName -StorageContainerName $artifactsContainerName `
    -ResourceGroupName $baseResourceGroup -ResourceGroupLocation $location `
    -TemplateFile $armTemplateFilePath `
    -TemplateParametersFile $armTemplateParamsFilePath `
    -ArtifactStagingDirectory '.' -DSCSourceFolder '.\DSC' -UploadArtifacts

}


Enable-AzureRmContextAutosave


# we need to publish the dsc to the root of the container
Publish-AzureRmVMDscConfiguration -ConfigurationPath .\DSC\DiskPrepTest.ps1 -ResourceGroupName $resultsStorageAccountRg `
    -StorageAccountName $resultsStorageAccountName -ContainerName $artifactsContainerName -Force -Verbose


for ($x = 1; $x -le $totalVmCount; $x++)
{
    Write-Host "Starting $x"

    $resourceGroup = $baseResourceGroup + $x    
    
	$vnetName = 'TestVnet'        # the name of the vnet to add the VMs to (must match what is set in the ARM template)

    $params = @(
        $resourceGroup
        $baseResourceGroup
        $storageKey
		$vmNamePrefix
        $vmsize
		$vnetName
        $cred
        $x
        $location
		$diskSpdDownloadUrl
		$testParams
        $resultsStorageAccountRg
		$resultsStorageAccountName
		$resultsContainerName
		$artifactsContainerName
		$dscPath
		$storageUrlDomain
    )

    $job = Start-Job -ScriptBlock { 
        param(
            $resourceGroup,
            $baseResourceGroup,
            $storageKey,
			$vmNamePrefix,
            $vmsize,
			$vnetName,
            $cred, 
            $x, 
            $location,
			$diskSpdDownloadUrl,
			$testParams,
            $resultsStorageAccountRg,
			$resultsStorageAccountName,
			$resultsContainerName,
			$artifactsContainerName,
			$dscPath,
			$storageUrlDomain
        )
        $vmName = "$vmNamePrefix$x"
        $testName = "$vmNamePrefix"
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $log = "c:\logs\$vmName.log"
		New-Item -ItemType Directory -Force -Path c:\logs
        Add-content $log "starting,$(Get-Date -Format 'yyyy-M-d hh:mm:ss')"
        
        $resultsStorage = Get-AzureRmStorageAccount -Name $resultsStorageAccountName -ResourceGroupName $resultsStorageAccountRg

        Get-AzureRMResourceGroup -Name $resourceGroup -ErrorVariable notPresent -ErrorAction SilentlyContinue

        if ($notPresent)
        {
            Add-content $log "creating $resourceGroup"
            New-AzureRmResourceGroup -Name $resourceGroup -Location $location
        }

        Add-content $log "creating storage,$($sw.Elapsed.ToString())"

        $storageAccountName = 'ramp'+ ([System.Guid]::NewGuid().ToString().Replace('-', '').substring(0, 19))
        $vmStore = New-AzureRmStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName `
          -Location $location -Type Premium_LRS

		# add container for streaming file in the network tests and acquire full url with SAS token
		New-AzureStorageContainer -Name $testName -Context $vmStore.Context -ErrorAction SilentlyContinue *>&1
		$uploadSasToken = New-AzureStorageContainerSASToken -Container $testName -FullUri -Context $vmStore.Context -Permission w -ExpiryTime (Get-Date).AddHours(4)

        Add-content $log "building refs,$($sw.Elapsed.ToString())"

        $Vnet = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $baseResourceGroup
        $SingleSubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name 'Subnet' -VirtualNetwork $Vnet
        $NIC = New-AzureRmNetworkInterface -Name "nic1" -ResourceGroupName $resourceGroup -Location $location -SubnetId $Vnet.Subnets[0].Id -Force
        
        Add-content $log "creating vm, $($sw.Elapsed.ToString())"

        $VirtualMachine = New-AzureRmVMConfig -VMName $vmName -VMSize $vmsize
		$VirtualMachine = Add-AzureRmVMDataDisk -VM $VirtualMachine -Name 'Data1' -Lun 0 -CreateOption Empty -DiskSizeInGB 1024 -VhdUri "https://$storageAccountName.$storageUrlDomain/disks/$vmName-data1.vhd" -Caching ReadWrite 
		$VirtualMachine = Add-AzureRmVMDataDisk -VM $VirtualMachine -Name 'Data2' -Lun 1 -CreateOption Empty -DiskSizeInGB 1024 -VhdUri "https://$storageAccountName.$storageUrlDomain/disks/$vmName-data2.vhd" -Caching ReadWrite
		$VirtualMachine = Add-AzureRmVMDataDisk -VM $VirtualMachine -Name 'Data3' -Lun 2 -CreateOption Empty -DiskSizeInGB 1024 -VhdUri "https://$storageAccountName.$storageUrlDomain/disks/$vmName-data3.vhd" -Caching ReadWrite
		$VirtualMachine = Add-AzureRmVMDataDisk -VM $VirtualMachine -Name 'Data4' -Lun 3 -CreateOption Empty -DiskSizeInGB 1024 -VhdUri "https://$storageAccountName.$storageUrlDomain/disks/$vmName-data4.vhd" -Caching ReadWrite
		$VirtualMachine = Set-AzureRmVMBootDiagnostics -VM $VirtualMachine -Disable
        $VirtualMachine = Set-AzureRmVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $vmName -Credential $cred 
        $VirtualMachine = Set-AzureRmVMSourceImage -VM $VirtualMachine -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2016-Datacenter" -Version "latest" 

        $VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -Name 'OsDisk' -VhdUri "https://$storageAccountName.$storageUrlDomain/disks/$vmName.vhd" -CreateOption 'FromImage'
        $VirtualMachine = Add-AzureRmVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id

		### create the VM ###
        $vmresult = New-AzureRmVM -VM $VirtualMachine -ResourceGroupName $resourceGroup -Location $location -ErrorVariable $vmOutput -Verbose
        
        if($vmOutput){
            Add-content $log "vm result,$vmOutput"
        }

        if($vmresult.IsSuccessStatusCode){
            
			Add-content $log "publishing dsc,$($sw.Elapsed.ToString())"
            $dscConfigParams = @{ 
                diskSpdDownloadUrl = $diskSpdDownloadUrl
	            testParams = $testParams
	            testName = $testName
	            storageAccountKey = $storageKey
	            storageContainerName = $resultsContainerName
	            storageAccountName = $resultsStorageAccountName
				storageUrlDomain = $storageUrlDomain
				uploadUrlWithSas = $uploadSasToken
            }
			
            # above we published the DSC to the root of the container
            $dscResult = Set-AzureRmVMDscExtension -Name Microsoft.Powershell.DSC -ArchiveBlobName 'DiskPrepTest.ps1.zip' `
                -ArchiveStorageAccountName $resultsStorageAccountName -ArchiveContainerName "$artifactsContainerName" `
                -ArchiveResourceGroupName $resultsStorageAccountRg -ResourceGroupName $resourceGroup -Version 2.19 -VMName $vmName `
                -ConfigurationArgument $dscConfigParams -ConfigurationName DiskPrepAndTest -ErrorVariable $dscOutput -Verbose
            
            if($dscOutput){
                Add-content $log "dsc result,$dscOutput"
            }
            
            Add-content $log "waiting for blob,$($sw.Elapsed.ToString())"

            $c = 6 
            Do{
                $blobNotPresent = ""
                $vmName = $vmName.ToUpper() # not sure why but the blob gets created with a vmname in caps
                Get-AzureStorageBlob -Blob "perfctr-$testName-$vmName.blg" -Container $resultsContainerName `
                    -Context $resultsStorage.Context -ErrorAction SilentlyContinue -ErrorVariable blobNotPresent
            
                if(![string]::IsNullOrEmpty($blobNotPresent))
                {
                    Add-content $log "checking for blob"
                    Start-Sleep -Seconds 5
                }
                $c--
            }
            Until([string]::IsNullOrEmpty($blobNotPresent) -or $c -le 0)

            Add-content $log "deleting resource group $resourceGroup,$($sw.Elapsed.ToString())"
            
            Remove-AzureRmResourceGroup -Name $resourceGroup -Force

        }

		Add-content $log "done,$($sw.Elapsed.ToString()),$(Get-Date -Format 'yyyy-M-d hh:mm:ss')"
		$sw.Stop()

    } -ArgumentList $params

    Write-Host "pausing for $pauseBetweenVmCreateInSeconds seconds"
    Start-Sleep -Seconds $pauseBetweenVmCreateInSeconds
}

Get-Job | Wait-Job | Receive-Job


