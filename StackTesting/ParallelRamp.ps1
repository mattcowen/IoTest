#
# ParallelRamp.ps1
#
param(
	$tests = @('first', 'second', 'third', 'fourth', 'fifth', 'sixth'), # DO NOT USE CHARS SUCH AS HYPHENS
	$pauseBetweenRampInSeconds = 150,
	$root = 'c:\dev\mod\Stacktesting\StackTesting\',
	$cred = (Get-Credential -UserName "mcowen" -Message "VM Admin cred"),
	$accountKey = (Read-Host -Prompt "Account key"),
	$vmBatchCount = 10
)

$params = @(
	$cred
	$tests
	$pauseBetweenRampInSeconds
	$root
	$accountKey
	$vmBatchCount
)

workflow Ramp-Test
{
	param(
		$cred,
		$tests,
		$pauseBetweenRampInSeconds,
		$root,
		$accountKey,
		$vmBatchCount
	)

	Set-Location -Path $root

	foreach -parallel ($testname in $tests){
		
		$parms = @(
			$testname
		)
		
		.\RampTest.ps1 -vmNamePrefix $testname `
			-cred $cred `
			-totalVmCount $vmBatchCount `
			-storageKey $accountKey


		Start-Sleep -Seconds $pauseBetweenRampInSeconds
	}
}

Ramp-Test -tests $params