$AADTenantName = ''
$ArmEndpoint = ''

# Register an Azure Resource Manager environment that targets your Azure Stack instance
Add-AzureRMEnvironment `
  -Name "AzureStackUser" `
  -ArmEndpoint $ArmEndpoint -Verbose

$AuthEndpoint = (Get-AzureRmEnvironment -Name "AzureStackUser").ActiveDirectoryAuthority.TrimEnd('/')
$TenantId = (invoke-restmethod "$($AuthEndpoint)/$($AADTenantName)/.well-known/openid-configuration").issuer.TrimEnd('/').Split('/')[-1]

Disconnect-AzureRmAccount


# Sign in to your environment
Login-AzureRmAccount `
  -EnvironmentName "AzureStackUser" `
  -TenantId $TenantId -Verbose