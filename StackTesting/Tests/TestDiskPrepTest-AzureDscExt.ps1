$key = Read-Host "key"
$sas = Read-Host "url"


$paramHash = @{ 
    diskSpdDownloadUrl = "https://gallery.technet.microsoft.com/DiskSpd-A-Robust-Storage-6ef84e62/file/199535/1/DiskSpd-2.0.20a.zip"
	testParams = '-c200M -b8K -t2 -o40 -d30'
	testName = 'dsctest'
	storageAccountKey = $key + ''
	storageContainerName = 'stacktestresults'
	storageAccountName = 'mctestharness'
	uploadUrlWithSas =  $sas + ''
}
 

# publish the configuration with resources
Publish-AzureRmVMDscConfiguration -ConfigurationPath ..\DSC\DiskPrepTest.ps1 -ResourceGroupName "MgcTestHarness" `
	-StorageAccountName "mctestharness" -ContainerName "artifacts" -Force -Verbose

Set-AzureRmVMDscExtension -Name Microsoft.Powershell.DSC -ArchiveBlobName DiskPrepTest.ps1.zip -ArchiveStorageAccountName mctestharness -ArchiveContainerName artifacts -ArchiveResourceGroupName MgcTestHarness `
-ResourceGroupName STA-1 -Version 2.21 -VMName first1 -ConfigurationArgument $paramHash -ConfigurationName DiskPrepAndTest -Verbose