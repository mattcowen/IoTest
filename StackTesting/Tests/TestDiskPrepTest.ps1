#
# TestDiskPrepTest.ps1
#

# get credential
#$creds = Get-Credential Azure\mgcdeployment


$configData =@{
    AllNodes = @(
        @{
            NodeName = "localhost";
			RebootNodeIfNeeded = $true;
			ActionAfterReboot = "ContinueConfiguration";
         }
    );

}

$params = @{
	diskSpdDownloadUrl = "https://gallery.technet.microsoft.com/DiskSpd-A-Robust-Storage-6ef84e62/file/199535/1/DiskSpd-2.0.20a.zip"
	testParams = '-c200M -b8K -t2 -o20 -d30'
	testName = 'iotest1'
	storageAccountKey = ''
	storageContainerName = 'stacktestresults'
	storageAccountName = 'mgctestharness'
	uploadUrlWithSas = ''
}


DiskPrepAndTest @params -Verbose

Start-DscConfiguration -ComputerName localhost -Path .\DiskPrepAndTest -Verbose -Wait -Force