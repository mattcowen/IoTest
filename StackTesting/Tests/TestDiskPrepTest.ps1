#
# TestDiskPrepTest.ps1
#

# get credential
$creds = Get-Credential Azure\housekeeperdeployment


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
	diskSpdDownloadUrl = "https://housekeeperdeployment.blob.core.windows.net/stacktest/DiskSpd-2.0.20a.zip"
	testParams = '-c10G -b8K -t2 -o40 -d30'
	testName = 'foo'
	resultsStorageAccountKey = $creds.Password
	storageUrl = '\\housekeeperdeployment.file.core.windows.net\artifacts'
	storageAccountName = 'housekeeperdeployment'

}


DiskPrepAndTest @params -Verbose

Start-DscConfiguration -ComputerName localhost -Credential (Get-Credential mcowen) -Path .\DiskPrepAndTest -Verbose -Wait -Force