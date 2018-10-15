
param (
    [string]$StackDomain,

    [switch]$Admin,

    [string]$ScriptPaths = "C:\dev\AzureStack-Tools"
)

# Are we creating an Admin session or user session
if ( $Admin ) {
    $ArmEndpointURL = "https://adminmanagement.${StackDomain}"
    $GraphAudienceURL = "https://graph.${StackDomain}"
}
else
{
    $ArmEndpointURL = "https://management.${StackDomain}"
    $GraphAudienceURL = "https://graph.${StackDomain}"
}

#First set execution policy
Set-ExecutionPolicy RemoteSigned

# Import all modules from the paths
Get-ChildItem -path "$ScriptPaths" -Recurse -Filter "*.psm1" | ForEach-Object { Import-Module $_.FullName }

# Create the Azure Stack Azure Resource Manager environment by using the following cmdlet:
Add-AzureRMEnvironment -Name "AzureStackEnv" -ArmEndpoint $ArmEndpointURL
Set-AzureRmEnvironment -Name "AzureStackEnv" -GraphAudience $GraphAudienceURL -EnableAdfsAuthentication:$true

# Get Tenant ID
$TenantID = Get-AzsDirectoryTenantId -ADFS -EnvironmentName "AzureStackEnv" 

# Login to Stack so that we can then use modules
Login-AzureRmAccount -EnvironmentName "AzureStackEnv" -TenantId $TenantID
