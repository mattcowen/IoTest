<#
Matt Cowen, August 2018

Creates virtual machines in parallel each in their own resource group and runs performance tests
outputting the results to blob storage. It then deletes each resource group once the test is complete.

#>

param
(
	[Parameter(Mandatory=$true)][ValidateNotNullOrEmpty()][PSCredential]$cred,
	[String]$resourceGroupNamePrefix = 'sta-',
    [String]$location = 'northeurope',    
    [String]$resultsStorageAccountName = 'testharness', # where the results from performance counters are saved
    [String]$resultsStorageAccountRg = 'TestHarness',
    [String]$resultsContainerName = 'stacktestresults', # the container for uploading the results of the performance test
	[String]$keyVaultName = 'TestVault'+([System.Guid]::NewGuid().ToString().Replace('-', '').substring(0, 8)),
    
    [String]$artifactsContainerName = 'artifacts',  # the container for uploading the published DSC configuration
    [Int32]$pauseBetweenVmCreateInSeconds = 0,
    [Int32]$totalVmCount = 5,
    [System.IO.FileInfo]$diskSpd = ".\DiskSpd-2.0.20a.zip",
    

	[ValidateLength(3,20)]
	[String]$vmNamePrefix = 'testvm', # DO NOT USE CHARS SUCH AS HYPHENS
	[String]$vmsize = 'Standard_D2s_v3',   # the size of VM
    [String]$armTemplateFilePath = '.\windowsvirtualmachine.json',
    [String]$armTemplateParamsFilePath = '.\windowsvirtualmachine.parameters.json',
    [String]$testParams = '-c200M -t2 -o20 -d30 -w50 -Rxml',     # the parameters for DiskSpd
    [String]$dscPath = '.\DSC\DiskPrepTest.ps1',     # the path to the DSC configuration to run on the VMs
    [String]$storageUrlDomain = 'blob.core.windows.net',
	[Int32]$dataDiskSizeGb = 1024,
    [switch]$dontDeleteResourceGroupOnComplete,
	[switch]$dontPublishDscBeforeStarting,
	[switch]$initialise # needed for initial deployment to create vnet

)
Write-Host "Started at $(Get-Date -Format 'HH:mm:ss')"

if(-not (Test-Path $dscPath)){
	Write-Host "Can't find necessary files. Are you at the right location?"
	exit
}

Enable-AzureRmContextAutosave

$vnetName = 'TestVnet'  # the name of the vnet to add the VMs to (must match what is set in the ARM template)

if($initialise){

    Get-AzureRMResourceGroup -Name $resultsStorageAccountRg -ErrorVariable resultsRgNotPresent -ErrorAction SilentlyContinue
	if($resultsRgNotPresent){
		Write-Host "Creating resources to receive test results/output"
		Write-Host "- creating resource group"
		New-AzureRmResourceGroup -Name $resultsStorageAccountRg -Location $location
		
		Write-Host "- creating storage account"
        $resultsStdStore = New-AzureRmStorageAccount -ResourceGroupName $resultsStorageAccountRg -Name $resultsStorageAccountName `
          -Location $location -Type Standard_LRS -ErrorAction SilentlyContinue
		
		Write-Host "- creating containers"
		New-AzureStorageContainer -Name $resultsContainerName -Context $resultsStdStore.Context -ErrorAction SilentlyContinue
		New-AzureStorageContainer -Name $artifactsContainerName -Context $resultsStdStore.Context -ErrorAction SilentlyContinue

		# upload DiskSpd-2.0.20a.zip to artifacts
		Write-Host "- uploading diskspd archive"
		Set-AzureStorageBlobContent -File $diskSpd -Blob 'DiskSpd-2.0.20a.zip' -Container $artifactsContainerName -Context $resultsStdStore.Context -Force
	    
		Write-Host "- creating key vault"
		New-AzureRmKeyVault -VaultName $keyVaultName -ResourceGroupName $resultsStorageAccountRg -Location $location 

		Write-Host "- adding secrets"
		$accKey = Get-AzureRmStorageAccountKey -ResourceGroupName $resultsStorageAccountRg -AccountName $resultsStorageAccountName

		Set-AzureKeyVaultSecret -VaultName $keyVaultName -Name 'password' -SecretValue $cred.Password
		Set-AzureKeyVaultSecret -VaultName $keyVaultName -Name 'storageKey' -SecretValue (ConvertTo-SecureString $accKey.Value[0] -AsPlainText -Force)
		
		Write-Host "Resources ready for test output"

	}

	
	Write-Host "Creating Virtual Network"
	$frontendSubnet = New-AzureRmVirtualNetworkSubnetConfig -Name 'Subnet' -AddressPrefix "10.0.1.0/24"
	New-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $resultsStorageAccountRg -Location $location -AddressPrefix "10.0.0.0/16" -Subnet $frontendSubnet -Force -Confirm:$false
	
}




if(-not $dontPublishDscBeforeStarting){
	Write-Host "Publishing DSC"
	# we need to publish the dsc to the root of the container
	Publish-AzureRmVMDscConfiguration -ConfigurationPath $dscPath -ResourceGroupName $resultsStorageAccountRg `
		-StorageAccountName $resultsStorageAccountName -ContainerName $artifactsContainerName -Force -Verbose
}

$root = Get-Location
$resultsStorage = Get-AzureRmStorageAccount -ResourceGroupName $resultsStorageAccountRg -Name $resultsStorageAccountName
New-AzureStorageContainer -Name $resultsContainerName -Context $resultsStorage.Context -ErrorAction SilentlyContinue

$storageKey = (Get-AzureRmStorageAccountKey -ResourceGroupName $resultsStorageAccountRg -AccountName $resultsStorageAccountName).Value[0] +''

$diskSpdDownloadUrl = New-AzureStorageBlobSASToken -Blob 'DiskSpd-2.0.20a.zip' -Container $artifactsContainerName -FullUri -Context $resultsStorage.Context -Permission r -ExpiryTime (Get-Date).AddHours(4)


for ($x = 1; $x -le $totalVmCount; $x++)
{
    Write-Host "Starting creation of vm $x"

    $resourceGroup = $resourceGroupNamePrefix + $x    

    $params = @(
        $resourceGroup
		$root
        $storageKey
		$vmNamePrefix
        $vmsize
		$vnetName
		$dataDiskSizeGb
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
		$dontDeleteResourceGroupOnComplete
    )

    $job = Start-Job -ScriptBlock { 
        param(
            $resourceGroup,
			$root,
            $storageKey,
			$vmNamePrefix,
            $vmsize,
			$vnetName,
			$dataDiskSizeGb,
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
			$storageUrlDomain,
			$dontDeleteResourceGroupOnComplete
        )
        $vmName = "$vmNamePrefix$x"
        $testName = "$vmNamePrefix"
        $sw = [Diagnostics.Stopwatch]::StartNew()
        $log = "c:\logs\$vmName.log"
		New-Item -ItemType Directory -Force -Path c:\logs
		Add-content $log "starting,$(Get-Date -Format 'yyyy-M-d HH:mm:ss')"
		Set-Location -Path $root -PassThru | Out-File -FilePath $log -Append -Encoding utf8
        

        Get-AzureRMResourceGroup -Name $resourceGroup -ErrorVariable notPresent -ErrorAction SilentlyContinue

        if ($notPresent)
        {
            Add-content $log "creating $resourceGroup"
            New-AzureRmResourceGroup -Name $resourceGroup -Location $location
        }

        Add-content $log "creating storage,$($sw.Elapsed.ToString())"

        $vmStorageAccountName = 'vm'+ ([System.Guid]::NewGuid().ToString().Replace('-', '').substring(0, 19))
        $vmStore = New-AzureRmStorageAccount -ResourceGroupName $resourceGroup -Name $vmStorageAccountName `
          -Location $location -Type Premium_LRS

        $stdStorageAccountName = 'std'+ ([System.Guid]::NewGuid().ToString().Replace('-', '').substring(0, 19))
        $stdStore = New-AzureRmStorageAccount -ResourceGroupName $resourceGroup -Name $stdStorageAccountName `
          -Location $location -Type Standard_LRS

		# add container for streaming file in the network tests and acquire full url with SAS token
		New-AzureStorageContainer -Name $testName -Context $stdStore.Context 

		$uploadSasToken = New-AzureStorageContainerSASToken -Container $testName -FullUri -Context $stdStore.Context -Permission rw -ExpiryTime (Get-Date).AddHours(4)

        Add-content $log "building refs,$($sw.Elapsed.ToString())"

        $Vnet = Get-AzureRmVirtualNetwork -Name $vnetName -ResourceGroupName $resultsStorageAccountRg
        $SingleSubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name 'Subnet' -VirtualNetwork $Vnet
        $NIC
        $nicCreateCount = 4
        do{
            # seeing a RetryableError with this cmdlet on 1807 of Azure Stack cmdlets so putting a retry in here
            $NIC = New-AzureRmNetworkInterface -Name "nic1" -ResourceGroupName $resourceGroup -Location $location -SubnetId $Vnet.Subnets[0].Id -Force -ErrorAction SilentlyContinue -ErrorVariable nicCreateError
            $nicCreateCount -= 1
            
			if($nicCreateError){
				Add-content $log "nic create,$nicCreateError,$($sw.Elapsed.ToString())"
			}
			Start-Sleep -Seconds 2
        }
        while($nicCreateError -or $nicCreateCount -le 0)
        
        Add-content $log "creating vm, $($sw.Elapsed.ToString())"

        $VirtualMachine = New-AzureRmVMConfig -VMName $vmName -VMSize $vmsize
		$VirtualMachine = Add-AzureRmVMDataDisk -VM $VirtualMachine -Name 'Data1' -Lun 0 -CreateOption Empty -DiskSizeInGB $dataDiskSizeGb -VhdUri "https://$vmStorageAccountName.$storageUrlDomain/disks/$vmName-data1.vhd" -Caching ReadWrite 
		$VirtualMachine = Add-AzureRmVMDataDisk -VM $VirtualMachine -Name 'Data2' -Lun 1 -CreateOption Empty -DiskSizeInGB $dataDiskSizeGb -VhdUri "https://$vmStorageAccountName.$storageUrlDomain/disks/$vmName-data2.vhd" -Caching ReadWrite
		$VirtualMachine = Add-AzureRmVMDataDisk -VM $VirtualMachine -Name 'Data3' -Lun 2 -CreateOption Empty -DiskSizeInGB $dataDiskSizeGb -VhdUri "https://$vmStorageAccountName.$storageUrlDomain/disks/$vmName-data3.vhd" -Caching ReadWrite
		$VirtualMachine = Add-AzureRmVMDataDisk -VM $VirtualMachine -Name 'Data4' -Lun 3 -CreateOption Empty -DiskSizeInGB $dataDiskSizeGb -VhdUri "https://$vmStorageAccountName.$storageUrlDomain/disks/$vmName-data4.vhd" -Caching ReadWrite
		$VirtualMachine = Set-AzureRmVMBootDiagnostics -VM $VirtualMachine -Disable
        $VirtualMachine = Set-AzureRmVMOperatingSystem -VM $VirtualMachine -Windows -ComputerName $vmName -Credential $cred 
        $VirtualMachine = Set-AzureRmVMSourceImage -VM $VirtualMachine -PublisherName "MicrosoftWindowsServer" -Offer "WindowsServer" -Skus "2016-Datacenter" -Version "latest" 

        $VirtualMachine = Set-AzureRmVMOSDisk -VM $VirtualMachine -Name 'OsDisk' -VhdUri "https://$vmStorageAccountName.$storageUrlDomain/disks/$vmName.vhd" -CreateOption 'FromImage'
        $VirtualMachine = Add-AzureRmVMNetworkInterface -VM $VirtualMachine -Id $NIC.Id

		### create the VM ###
        $vmresult = New-AzureRmVM -VM $VirtualMachine -ResourceGroupName $resourceGroup -Location $location -ErrorVariable vmOutput -Verbose
        
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
				uploadUrlWithSas = $uploadSasToken + ''
            }
			
            # above we published the DSC to the root of the container
            $dscResult = Set-AzureRmVMDscExtension -Name Microsoft.Powershell.DSC -ArchiveBlobName 'DiskPrepTest.ps1.zip' `
                -ArchiveStorageAccountName $resultsStorageAccountName -ArchiveContainerName "$artifactsContainerName" `
                -ArchiveResourceGroupName $resultsStorageAccountRg -ResourceGroupName $resourceGroup -Version 2.19 -VMName $vmName `
                -ConfigurationArgument $dscConfigParams -ConfigurationName DiskPrepAndTest -ErrorVariable dscErrorOutput -OutVariable dscOutput -Verbose
            
            if($dscErrorOutput){
                Add-content $log "dsc result,$dscErrorOutput"
            }
			if($dscOutput){
                Add-content $log $dscOutput
            }
            
            Add-content $log "waiting for blob,$($sw.Elapsed.ToString())"
            $resultsStorage = Get-AzureRmStorageAccount -ResourceGroupName $resultsStorageAccountRg -Name $resultsStorageAccountName

            $c = 6 
            Do{

                Get-AzureStorageBlob -Blob "perfctr-$testName-$vmName.blg" -Container $resultsContainerName `
                    -Context $resultsStorage.Context -ErrorAction SilentlyContinue -ErrorVariable blob1NotPresent
				
				$vmName = $vmName.ToUpper() # not sure why but the blob gets created with a vmname in caps when on stack
				Get-AzureStorageBlob -Blob "perfctr-$testName-$vmName.blg" -Container $resultsContainerName `
						-Context $resultsStorage.Context -ErrorAction SilentlyContinue -ErrorVariable blob2NotPresent

                if($blob1NotPresent -and $blob2NotPresent)
                {
                    Add-content $log "checking for blob"
                    Start-Sleep -Seconds 5
                }
                $c--
            }
            Until([string]::IsNullOrEmpty($blobNotPresent) -or $c -le 0)

            Add-content $log "deleting resource group $resourceGroup,$($sw.Elapsed.ToString())"
            
			if(-not $dontDeleteResourceGroupOnComplete){
				Remove-AzureRmResourceGroup -Name $resourceGroup -Force
			}

        }

		Add-content $log "done,$($sw.Elapsed.ToString()),$(Get-Date -Format 'yyyy-M-d HH:mm:ss')"
		$sw.Stop()

    } -ArgumentList $params

    Write-Host "pausing for $pauseBetweenVmCreateInSeconds seconds"
    Start-Sleep -Seconds $pauseBetweenVmCreateInSeconds
}

Get-Job | Wait-Job | Receive-Job


