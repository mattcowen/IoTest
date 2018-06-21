Configuration DiskPrepAndTest
{


	Param(
		#Target nodes to apply the configuration 
		[Parameter(Mandatory = $false)] 
		[ValidateNotNullorEmpty()] 
		[String]$SystemTimeZone="GMT Standard Time" 
 
	) 
 
	# Modules to Import
 
	Import-DscResource –ModuleName PSDesiredStateConfiguration
	Import-DSCResource -ModuleName ComputerManagementDsc 
 
	Node localhost
	{
	
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
	}



}