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

		[String]$storageAccountKey, # from the properties of the storage account
		[String]$storageContainerName,  # e.g. testresults
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
			ConfigurationMode = 'ApplyOnly'
        } 

		#TimeZone TimeZoneExample 
		#{ 
		#	IsSingleInstance = 'Yes'
		#	TimeZone = $SystemTimeZone 
		#} 
 
		#WindowsFeature SMBv1 
		#{
		#	Name = "FS-SMB1"
		#	Ensure = "Absent" 
		#}

 	#	Script StoragePool 
		#{
		#	SetScript = { 
		#		New-StoragePool -FriendlyName StoragePool1 -StorageSubSystemFriendlyName '*storage*' -PhysicalDisks (Get-PhysicalDisk –CanPool $True)
		#	}
		#	TestScript = {
		#		(Get-StoragePool -ErrorAction SilentlyContinue -FriendlyName StoragePool1).OperationalStatus -eq 'OK'
		#	}
		#	GetScript = {
		#		@{Ensure = if ((Get-StoragePool -FriendlyName StoragePool1).OperationalStatus -eq 'OK') {'Present'} Else {'Absent'}}
		#	}
		#}
	
		#Script VirtualDisk 
		#{
		#	SetScript = { 
		#		$disks = Get-StoragePool –FriendlyName StoragePool1 -IsPrimordial $False | Get-PhysicalDisk
 
		#		$diskNum = $disks.Count
		#		New-VirtualDisk –StoragePoolFriendlyName StoragePool1 –FriendlyName VirtualDisk1 –ResiliencySettingName simple -NumberOfColumns $diskNum –UseMaximumSize 
		#	}
		#	TestScript = {
		#		(get-virtualdisk -ErrorAction SilentlyContinue -friendlyName VirtualDisk1).operationalSatus -EQ 'OK' 
		#	}
		#	GetScript = { 
		#		@{Ensure = if ((Get-VirtualDisk -FriendlyName VirtualDisk1).OperationalStatus -eq 'OK') {'Present'} Else {'Absent'}}
		#	}
		#	DependsOn = "[Script]StoragePool"
		#}
		
		#Script FormatDisk 
		#{ 
		#	SetScript = { 
		#		Get-VirtualDisk –FriendlyName VirtualDisk1 | Get-Disk | Initialize-Disk –Passthru | New-Partition –AssignDriveLetter –UseMaximumSize | Format-Volume -NewFileSystemLabel VirtualDisk1 –AllocationUnitSize 64KB -FileSystem NTFS
		#	}
		#	TestScript = { 
		#		(get-volume -ErrorAction SilentlyContinue -filesystemlabel VirtualDisk1).filesystem -EQ 'NTFS'
		#	} 
		#	GetScript = { 
		#		@{Ensure = if ((get-volume -filesystemlabel VirtualDisk1).filesystem -EQ 'NTFS') {'Present'} Else {'Absent'}}
		#	} 
		#	DependsOn = "[Script]VirtualDisk" 
		#}

		#FileDownload DiskSpdDownload
  #      {
  #          FileName = "c:\diskspd.zip"
  #          Url = $diskSpdDownloadUrl
		#	DependsOn = "[Script]FormatDisk"
  #      }

		#Archive UncompressDiskSpd
  #      {
  #          Path = "c:\diskspd.zip"
  #          Destination = "c:\DiskSpd"
		#	DependsOn = "[FileDownload]DiskSpdDownload"
  #      }

		Script RunTest
		{
			SetScript = {
				
				# we need the -si parameter at the moment because 
				# otherwise diskspd will issue a warning that
				# dsc flags as an error
				$resultsfile = [System.IO.FileInfo]"C:\$using:testName-$(Get-Date -Format yyyy-MM-dd-hhmmssff).txt"
				
				Write-Verbose "Running test and outputting to $resultsfile"

				$cmd = 'C:\DiskSpd\amd64\diskspd.exe '+$using:testParams+' -si F:\testfile1.dat'
				iex $cmd > $resultsfile

				Write-Verbose "Uploading to storage..."

				$fileLength=(Get-Item $resultsfile).length

				$StorageAccount = $using:storageAccountName
				$Key = $using:storageAccountKey
				$resource = $using:storageContainerName

				$date = [System.DateTime]::UtcNow.ToString("R")

				$stringToSign = "PUT`n`n`n$fileLength`n`n`n`n`n`n`n`n`nx-ms-blob-type:BlockBlob`nx-ms-date:$date`nx-ms-version:2015-04-05`n/$StorageAccount/$resource/"+$resultsfile.Name
				Write-Verbose "String to sign: $stringToSign"

				$sharedKey = [System.Convert]::FromBase64String($Key)
				$hasher = New-Object System.Security.Cryptography.HMACSHA256
				$hasher.Key = $sharedKey

				$signedSignature = [System.Convert]::ToBase64String($hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($stringToSign)))
				
				$authHeader = "SharedKey ${StorageAccount}:$signedSignature"

				$headers = @{
					"Authorization"=$authHeader
					"x-ms-date"=$date
					"x-ms-version"="2015-04-05"
					"x-ms-blob-type"="BlockBlob"
				}
				$url = "https://$StorageAccount.blob.core.windows.net/$resource/"+$resultsfile.Name
				
				$response = Invoke-RestMethod -method PUT -InFile $resultsfile `
							 -Uri $url `
							 -Headers $headers -Verbose
				
				write-host $response
				Write-Verbose "Uploaded to storage. Done."

			}
			TestScript = { 
				$false
			} 
			GetScript = {
				@{Ensure = if (test-path -path "C:\DiskSpd\amd64\diskspd.exe") {'Present'} Else {'Absent'}}
			}
			#DependsOn = "[Archive]UncompressDiskSpd"
		}
	}





}