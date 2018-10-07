# Copy custom dsc resource to modules folder
# Install dependent modules

# check we are at the right location
Get-Item .\DSC\StackTestHarness -ErrorVariable dirError

if(-not $dirError)
{
	# delete existing and copy
    Remove-Item -Recurse -Force "C:\Program Files\WindowsPowerShell\Modules\StackTestHarness" -Confirm:$false
    Copy-Item -Recurse -Force -Path .\DSC\StackTestHarness -Destination "C:\Program Files\WindowsPowershell\Modules\" -Confirm:$false
}


Find-Module -Name xPendingReboot -Repository PSGallery | Install-Module
Find-Module -Name ComputerManagementDsc -Repository PSGallery | Install-Module
Find-Module -Name FileDownloadDSC -Repository PSGallery | Install-Module
