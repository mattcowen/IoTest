#
# TestDiskPrepTest.ps1
#

# get credential


$configData =@{
    AllNodes = @(
        @{
            NodeName = "localhost";
			RebootNodeIfNeeded = $true;
			ActionAfterReboot = "ContinueConfiguration";
         }
    );

}



DiskPrepAndTest -Verbose

Start-DscConfiguration -ComputerName localhost -Credential (Get-Credential mcowen) -Path .\DiskPrepAndTest -Verbose -Wait -Force