Configuration DiskPrepAndTest
{


	Param(
		#Target nodes to apply the configuration 
		[Parameter(Mandatory = $false)] 
		[ValidateNotNullorEmpty()] 
		[String]$SystemTimeZone="GMT Standard Time",

		[Parameter(Mandatory = $true)]
		[ValidateNotNullorEmpty()] 
		[String]$diskSpdDownloadUrl, # https://gallery.technet.microsoft.com/DiskSpd-A-Robust-Storage-6ef84e62/file/199535/1/DiskSpd-2.0.20a.zip

		[Parameter(Mandatory = $false)]
		[ValidateNotNullorEmpty()] 
		[String]$testParams,

		[Parameter(Mandatory = $true)]
		[ValidateNotNullorEmpty()] 
		[String]$testName,

		[String]$storageAccountKey, # from the properties of the storage account
		[String]$storageContainerName,  
		[String]$storageAccountName,
		[String]$storageUrlDomain = 'blob.core.windows.net', # this will be different for an Azure Stack
		
		[String]$uploadUrlWithSas 

		
	)
 
		
	# Modules to Import
	Import-DscResource –ModuleName PSDesiredStateConfiguration, ComputerManagementDsc, xPendingReboot, FileDownloadDSC, StackTestHarness
 
	Node localhost
	{
		LocalConfigurationManager 
        { 
            # This is false by default
            RebootNodeIfNeeded = $true
			ActionAfterReboot = 'ContinueConfiguration'
			ConfigurationMode = 'ApplyOnly'
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
				(get-virtualdisk -ErrorAction SilentlyContinue -friendlyName VirtualDisk1).operationalStatus -EQ 'OK' 
			}
			GetScript = { 
				@{Ensure = if ((Get-VirtualDisk -FriendlyName VirtualDisk1).OperationalStatus -eq 'OK') {'Present'} Else {'Absent'}}
			}
			DependsOn = "[Script]StoragePool"
		}
		
		Script FormatDisk 
		{ 
			SetScript = { 
                $global:DSCMachineStatus = 1;

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

		xPendingReboot Reboot1
        {
            Name = 'BeforeSoftwareInstall'
        }

		
		File ResultsDirectory
		{
			DestinationPath = 'F:\results'
			Ensure = "Present"
			Type = 'Directory'
			DependsOn = "[xPendingReboot]Reboot1"
		}

		FileDownload DiskSpdDownload
        {
            FileName = "c:\diskspd.zip"
            Url = $diskSpdDownloadUrl
			DependsOn = "[File]ResultsDirectory"
        }

		Archive UncompressDiskSpd
        {
            Path = "c:\diskspd.zip"
            Destination = "c:\DiskSpd"
			DependsOn = "[FileDownload]DiskSpdDownload"
        }


		DiskSpdTest test
		{
			TestName = $testName
			PhysicalPathToDiskSpd = "C:\DiskSpd\amd64\"
			ResultsOutputDirectory = "F:\results"
			DiskSpdParameters = $testParams
			StorageAccountName = $storageAccountName
			StorageContainerName = $storageContainerName
			StorageAccountKey = $storageAccountKey
			StorageUrlDomain = $storageUrlDomain
			UploadUrlWithSas = $uploadUrlWithSas
			Ensure = "Present"
			DependsOn = "[Archive]UncompressDiskSpd"

		}



	}





}


