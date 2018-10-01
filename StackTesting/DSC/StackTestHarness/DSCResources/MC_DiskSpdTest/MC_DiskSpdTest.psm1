function Get-TargetResource
{
	[CmdletBinding()]
    [OutputType([System.Collections.Hashtable])]
    param
    (
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PhysicalPathToDiskSpd,

        [Parameter(Mandatory)]
        [string]$DiskSpdParameters,
		
        [Parameter(Mandatory)]
		[String]$TestName,
		
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ResultsOutputDirectory,
		
		[string]$StorageAccountName,
		[string]$StorageAccountKey,
		[string]$StorageContainerName,
		[String]$StorageUrlDomain,

		[String]$UploadUrlWithSas,

        [string[]]$PerformanceCounters = @('\PhysicalDisk(*)\*', '\Processor Information(*)\*', '\Memory(*)\*', '\Network Interface(*)\*')

    )

    $getTargetResourceResult = $null;
	$n = "perfctr-$TestName-$env:COMPUTERNAME"
	
	$testHarnessParametersPath = [io.path]::combine($ResultsOutputDirectory, $n + ".txt")
	$resultsPath = [io.path]::combine($ResultsOutputDirectory, $n + ".blg")
	$resultsExist = [System.IO.File]::Exists($resultsPath)

	if($resultsExist){
		$line = (Get-Content $testHarnessParametersPath | Select-String -Pattern '^PerfCounters:' | Select -ExpandProperty line).Replace('PerfCounters:', '')
		$diskParams = (Get-Content $testHarnessParametersPath | Select-String -Pattern '^DiskSpdParams:' | Select -ExpandProperty line).Replace('DiskSpdParams:', '')
		
		$getTargetResourceResult =  @{
			Ensure = "Present";
			PhysicalPathToDiskSpd = $PhysicalPathToDiskSpd;
			DiskSpdParameters = $diskParams;
			TestName = $TestName;
			ResultsOutputDirectory = $ResultsOutputDirectory;
			PerformanceCounters = ($line.Split(','));
		}
	}
	else{
		$getTargetResourceResult =  @{
			Ensure = $Ensure;
			PhysicalPathToDiskSpd = $PhysicalPathToDiskSpd;
			DiskSpdParameters = $DiskSpdParameters;
			TestName = $TestName;
			ResultsOutputDirectory = $ResultsOutputDirectory;
			PerformanceCounters = $PerformanceCounters;
		}
	}

    $getTargetResourceResult;
}

function Set-TargetResource
{
    [CmdletBinding()]
    param
    (
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PhysicalPathToDiskSpd,

        [Parameter(Mandatory)]
        [string]$DiskSpdParameters,
		
        [Parameter(Mandatory)]
		[String]$TestName,
		
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ResultsOutputDirectory,
		
		[string]$StorageAccountName,
		[string]$StorageAccountKey,
		[string]$StorageContainerName,
		[String]$StorageUrlDomain,

		[String]$UploadUrlWithSas,

        [string[]]$PerformanceCounters = @('\PhysicalDisk(*)\*', '\Processor Information(*)\*', '\Memory(*)\*', '\Network Interface(*)\*')
    )
	$n = "perfctr-$TestName-$env:COMPUTERNAME"
	$resultsPath = [io.path]::combine($ResultsOutputDirectory, $n + ".blg")
	$resultsExist = [System.IO.File]::Exists($resultsPath)

    <# If Ensure is set to "Present" and the results file does not exist, then run test using the specified parameter values #>
	if(-not $resultsExist -and $Ensure -eq "Present"){
		

		<# disable ESC
		$AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
		$UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
		Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
		Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
		Stop-Process -Name Explorer
		Write-Host "IE Enhanced Security Configuration (ESC) has been disabled." -ForegroundColor Green #>


		$iopsTestFilePath = [io.path]::combine($ResultsOutputDirectory, $TestName + ".dat")
		$testHarnessfile = [System.IO.FileInfo][io.path]::combine($ResultsOutputDirectory, $n + ".txt")
		$diskSpdPath = [io.path]::combine($PhysicalPathToDiskSpd, "diskspd.exe")
		
		if(-not [System.IO.File]::Exists($diskSpdPath)){
			Start-Sleep -Seconds 5
		}

		Add-Content -Path $testHarnessfile -Value "PerfCounters:$([system.String]::Join(",",$PerformanceCounters))"
		Add-Content -Path $testHarnessfile -Value "DiskSpdParams:$DiskSpdParameters"

		Write-Verbose "Running test $TestName with params $DiskSpdParameters"

		start-logman $env:COMPUTERNAME $TestName $PerformanceCounters

		# run the diskspd test and output to a file
		$cmd = "$diskSpdPath $DiskSpdParameters $iopsTestFilePath"
		iex $cmd *> $testHarnessfile

		# save diskSpd output to txt file
		Add-Content -Path $testHarnessfile -Value "DiskSpdResults:`n$diskSpdResults"
		
		# upload iops test file to test the network
		Write-Verbose "Uploading test iops file $iopsTestFilePath"
		$endpoint = "$($uploadUrlWithSas.Split('?')[0])/$("$TestName.dat")?$($uploadUrlWithSas.Split('?')[1])"
		$headers = @{
			"x-ms-blob-type"="BlockBlob"
			"Content-Length"=(Get-Item $iopsTestFilePath).length
		}
		
		$response = Invoke-RestMethod -method PUT -InFile $iopsTestFilePath `
					-Uri $endpoint `
                    -Headers $headers -ErrorVariable $uploadError `
					-Verbose
		
		if($uploadError){
			Add-Content -Path $testHarnessfile -Value "UploadError:$uploadError"
		}
		else{
			# download the file we just uploaded to continue test of the network
			Write-Verbose "Downloading file $endpoint"
			$wc = New-Object System.Net.WebClient
			$wc.Headers["User-Agent"] = "Mozilla/4.0 (compatible; MSIE 6.0; Windows NT 5.2; .NET CLR 1.0.3705;)"
			$wc.DownloadFile($endpoint,([io.path]::combine($ResultsOutputDirectory, "$TestName-download.dat")))
		}

		# stops the performance counters and copies output to $resultsPath
		stop-logman $env:COMPUTERNAME $TestName $ResultsOutputDirectory
		
		upload-to-blob-storage $storageUrlDomain $storageAccountName $storageAccountKey $storageContainerName $resultsPath
		upload-to-blob-storage $storageUrlDomain $storageAccountName $storageAccountKey $storageContainerName $testHarnessfile
		
		Write-Verbose "Uploaded results to storage. Done."
	}

}



function Test-TargetResource
{
	[CmdletBinding()]
    [OutputType([System.Boolean])]
	param
    (
        [ValidateSet("Present", "Absent")]
        [string]$Ensure = "Present",

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$PhysicalPathToDiskSpd,

        [Parameter(Mandatory)]
        [string]$DiskSpdParameters,
		
        [Parameter(Mandatory)]
		[String]$TestName,
		
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$ResultsOutputDirectory,
		
		[string]$StorageAccountName,
		[string]$StorageAccountKey,
		[string]$StorageContainerName,
		[String]$StorageUrlDomain,

		[String]$UploadUrlWithSas,

        [string[]]$PerformanceCounters = @('\PhysicalDisk(*)\*', '\Processor Information(*)\*', '\Memory(*)\*', '\Network Interface(*)\*')
    )

	#Write-Verbose "Use this cmdlet to deliver information about command processing."

	#Write-Debug "Use this cmdlet to write debug information while troubleshooting."


	#Include logic to
	$resultsPath = [io.path]::combine($ResultsOutputDirectory, $env:COMPUTERNAME + "-" + $TestName + ".blg")
	$resultsExist = [System.IO.File]::Exists($resultsPath)
	#Add logic to test whether the website is present and its status mathes the supplied parameter values. If it does, return true. If it does not, return false.
	$resultsExist
}




function upload-to-blob-storage(
		[String] $storageUrlDomain, # for Azure this would be blob.core.windows.net but will differ for Stack
		[string] $StorageAccount, # the name of the storage account
		[string] $Key,  # storage account key
		[string] $containerName,
		[System.IO.FileInfo] $file
	)
{
	
	$fileLength=(Get-Item $file).length

	Write-Verbose "Uploading results to storage...file length is $fileLength"

	$date = [System.DateTime]::UtcNow.ToString("R")

	$stringToSign = "PUT`n`n`n$fileLength`n`n`n`n`n`n`n`n`nx-ms-blob-type:BlockBlob`nx-ms-date:$date`nx-ms-version:2015-04-05`n/$StorageAccount/$containerName/$($file.Name)"
	Write-Verbose "String to sign: $stringToSign"

	$sharedKey = [System.Convert]::FromBase64String($Key)
	$hasher = New-Object System.Security.Cryptography.HMACSHA256
	$hasher.Key = $sharedKey

	$signedSignature = [System.Convert]::ToBase64String($hasher.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($stringToSign)))
				
	$authHeader = "SharedKey ${StorageAccount}:$signedSignature"

	$headers = @{
		"Authorization"=$authHeader
		"x-ms-date"=$date
		"x-ms-version"="2015-04-05" # this is old but needs to be currently for Stack
		"x-ms-blob-type"="BlockBlob"
	}
	$url = "https://$StorageAccount.$storageUrlDomain/$containerName/$($file.Name)"
				
	$response = Invoke-RestMethod -method PUT -InFile $file `
					-Uri $url `
					-Headers $headers -Verbose
				
	write-host $response
}


function start-logman(
    [string] $computer,
    [string] $name,
    [string[]] $counters
    )
{
    $f = "c:\perfctr-$name-$computer.blg"

    $null = logman create counter "perfctr-$name" -o $f -f bin -si 1 --v -c $counters -s $computer
    $null = logman start "perfctr-$name" -s $computer
    write-host "performance counters on: $computer"
}

function stop-logman(
    [string] $computer,
    [string] $name,
    [string] $path
    )
{
    $f = "c:\perfctr-$name-$computer.blg"
    
    $null = logman stop "perfctr-$name" -s $computer
    $null = logman delete "perfctr-$name" -s $computer
    xcopy /j $f $path
    del -force $f
    write-host "performance counters off: $computer"
}


Export-ModuleMember -Function *-TargetResource