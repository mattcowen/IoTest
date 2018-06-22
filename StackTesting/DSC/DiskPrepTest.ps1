Configuration DiskPrepAndTest
{


	Param(
		#Target nodes to apply the configuration 
		[Parameter(Mandatory = $false)] 
		[ValidateNotNullorEmpty()] 
		[String]$SystemTimeZone="GMT Standard Time",

		[Parameter(Mandatory = $true)]
		[ValidateNotNullorEmpty()] 
		[String]$diskSpdDownloadUrl,

		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()] 
		[String]$testParams,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullorEmpty()] 
		[String]$testName,

		[String]$resultsStorageAccountKey, # from the properties of the storage account
		[String]$storageUrl,  # e.g. \\housekeeperdeployment.file.core.windows.net\artifacts
		[String]$storageAccountName # e.g. housekeeperdeployment
	)
 
	# Modules to Import
	Import-DscResource –ModuleName PSDesiredStateConfiguration, ComputerManagementDsc, FileDownloadDSC
 
	Node localhost
	{
		LocalConfigurationManager 
        { 
            # This is false by default
            RebootNodeIfNeeded = $true
        } 

		TimeZone TimeZoneExample 
		{ 
			IsSingleInstance = 'Yes'
			TimeZone = $SystemTimeZone 
		} 
 
		WindowsFeature SMBv1 
		{
			Name = "FS-SMB1"
			Ensure = "Absent" 
		}

 		Script StoragePool 
		{
			SetScript = { 
				New-StoragePool -FriendlyName StoragePool1 -StorageSubSystemFriendlyName '*storage*' -PhysicalDisks (Get-PhysicalDisk –CanPool $True)
			}
			TestScript = {
				(Get-StoragePool -ErrorAction SilentlyContinue -FriendlyName StoragePool1).OperationalStatus -eq 'OK'
			}
			GetScript = {
				@{Ensure = if ((Get-StoragePool -FriendlyName StoragePool1).OperationalStatus -eq 'OK') {'Present'} Else {'Absent'}}
			}
		}
	
		Script VirtualDisk 
		{
			SetScript = { 
				$disks = Get-StoragePool –FriendlyName StoragePool1 -IsPrimordial $False | Get-PhysicalDisk
 
				$diskNum = $disks.Count
				New-VirtualDisk –StoragePoolFriendlyName StoragePool1 –FriendlyName VirtualDisk1 –ResiliencySettingName simple -NumberOfColumns $diskNum –UseMaximumSize 
			}
			TestScript = {
				(get-virtualdisk -ErrorAction SilentlyContinue -friendlyName VirtualDisk1).operationalSatus -EQ 'OK' 
			}
			GetScript = { 
				@{Ensure = if ((Get-VirtualDisk -FriendlyName VirtualDisk1).OperationalStatus -eq 'OK') {'Present'} Else {'Absent'}}
			}
			DependsOn = "[Script]StoragePool"
		}
		
		Script FormatDisk 
		{ 
			SetScript = { 
				Get-VirtualDisk –FriendlyName VirtualDisk1 | Get-Disk | Initialize-Disk –Passthru | New-Partition –AssignDriveLetter –UseMaximumSize | Format-Volume -NewFileSystemLabel VirtualDisk1 –AllocationUnitSize 64KB -FileSystem NTFS
			}
			TestScript = { 
				(get-volume -ErrorAction SilentlyContinue -filesystemlabel VirtualDisk1).filesystem -EQ 'NTFS'
			} 
			GetScript = { 
				@{Ensure = if ((get-volume -filesystemlabel VirtualDisk1).filesystem -EQ 'NTFS') {'Present'} Else {'Absent'}}
			} 
			DependsOn = "[Script]VirtualDisk" 
		}


		
		FileDownload DiskSpdDownload
        {
            FileName = "c:\diskspd.zip"
            Url = $diskSpdDownloadUrl
			DependsOn = "[Script]FormatDisk"
        }

		Archive UncompressDiskSpd
        {
            Path = "c:\diskspd.zip"
            Destination = "c:\DiskSpd"
			DependsOn = "[FileDownload]DiskSpdDownload"
        }

		Script MapStorageShare
		{
			SetScript = {
				Write-Verbose "Mapping Storage share for output"
				Write-Verbose "For storage $using:storageAccountName"

				$credential = New-Object System.Management.Automation.PSCredential -ArgumentList "Azure\$using:storageAccountName", $using:resultsStorageAccountKey
				New-PSDrive -Name Z -PSProvider FileSystem -Root $using:storageUrl -Credential $credential -Persist
			}
			TestScript = {
				$false
			}
			GetScript = {""}
			DependsOn = "[Archive]UncompressDiskSpd" 
		}

		Script RunTest
		{
			SetScript = {
				# we need the -si parameter because otherwise diskspd will issue a warning that
				# dsc will flag as an error
				$cmd = 'C:\DiskSpd\amd64\diskspd.exe '+$using:testParams+' -si F:\testfile1.dat'
				iex $cmd > Z:/$using:testName-output.txt

			}
			TestScript = { 
				$false
			} 
			GetScript = {
				@{Ensure = if (test-path -path "C:\DiskSpd\amd64\diskspd.exe") {'Present'} Else {'Absent'}}
			}
			DependsOn = "[Script]MapStorageShare" 
		}
	}





}