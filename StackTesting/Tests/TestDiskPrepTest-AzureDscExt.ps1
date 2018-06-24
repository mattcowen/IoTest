#
# TestDiskPrepTest_AzureDscExt.ps1
#
$paramHash = 
@{ 
    diskSpdDownloadUrl = "https://housekeeperdeployment.blob.core.windows.net/stacktest/DiskSpd-2.0.20a.zip"
	testParams = '-c10G -b8K -t2 -o40 -d30'
	testName = 'foo'
	storageAccountKey = (Get-Credential -Message "Account key" -UserName "ignore")
	storageContainerName = 'stacktestresults'
	storageAccountName = 'housekeeperdeployment'
}

# publish the configuration with resources
Publish-AzureRmVMDscConfiguration -ConfigurationPath ..\DSC\DiskPrepTest.ps1 -ResourceGroupName "Housekeeper-Deployment" `
	-StorageAccountName "housekeeperdeployment" -ContainerName "dsctesting" -Force -Verbose

Set-AzureRmVMDscExtension -Name Microsoft.Powershell.DSC -ArchiveBlobName DiskPrepTest.ps1.zip -ArchiveStorageAccountName housekeeperdeployment -ArchiveContainerName dsctesting -ArchiveResourceGroupName Housekeeper-Deployment `
-ResourceGroupName StackTesting -Version 2.21 -VMName TestVM0 -ConfigurationArgument $paramHash -ConfigurationName DiskPrepAndTest -Verbose