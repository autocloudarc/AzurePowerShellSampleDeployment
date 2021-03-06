﻿#Requires -Version 5.0
<#
.SYNOPSIS
    POC-Environment-Setup.ps1 - Script that configures the PoC environment for Azure Fast Start for IaaS.
.DESCRIPTION
    POC-Environment-Setup.ps1 - Script that configures the PoC environment for Azure Fast Start for IaaS.
	This script configures all necessary resources to have an environment that is spread between two locations, East and West.
	West location contains a domain controller and a virtual network, East location contains two IIS servers that are domain joined
	to Contosoad.com domain. East also has a virtual network, both of them are connected through a Vnet-to-Vnet VPN to allow 
	communication between them. IIS servers are also load balanced. Powershell DSC (Desired State Configuration) is used to
	configure the new Active Directory Forest and IIS servers. Three resource groups are created, one for east resources, one for
	west resources and the third one located in east for the storage accounts.
.NOTES
    AUTHOR(S): Paulo Marques
    CONTRIBUTOR(S): Preston K. Parsard
    KEYWORDS: PoC, Deployment

.LINK
    https://www.powershellgallery.com/packages/WriteToLogs
#>

<#
Change Log:

* Included New-RandomString function to automatically generate passwords and other random strings. that will be used during the script, i.e. suffixes for storage account names and shared key for VNET
 .to VNET connection, load balancer dns prefix label, etc.
* Added code to prompt user for subscription name instead of requiring a direct hard coded update to the script
* Called New-RandomString function to produce unique shared key for VNET to VNET connection.
* Add a random infix inside the Dnslabel name to avoid conflicts with existing deployments generated from this script
* Create a new random string, then extract the 4 digits to use as the last characters for the storage account name for each region
* Added the Transciption feature from the Start-Transcript and Stop-Transcript cmdlets to record more script activity details, also repositioned the log creation earlier in the script.
* Added an expression after script executes as a convenient option for the user to quickly remove the 'poc...' resource groups if desired (for a dev/test/poc situation only).
* Added author, editor, keyword, license information in the .NOTES help keyword. Also added the .LINK help keyword.
* Added $BeginTimer variable at the start of the script so that total script execution time can be measured at script completion.
* Construct custom path for log files based on current user's $env:HOMEPATH directory for both the log and transcript files.
* Create both log and transcript files with time/date stamps included in their filenames.
* Added work-items (tasks) comment section to track outstanding tasks.
* Added region tags to accomodate collapsing sections of script to hide details or make it easier to scroll.
* Create prompt and responses custom object for opening logs after script completes.
* Add logging module: WriteToLogs.
* Add and display header.
* Format and truncate the results of the New-Guid cmdlet for a subset of random numeric and lowercase combination of characters
* Add a random infix (4 numeric digits) inside the Dnslabel name to avoid conflicts with existing deployments generated from this script. 
* Create a new random string, then extract the 4 digits to use as the last characters for the storage account name for each region.
* Use previously captured plain-text password variable instead of hard-coding in script.
* Added footer region to calculate elapsed time, display footer message, prompt to open log and transcript files, stop transcript...
* .as well as added a commented section that can be used to decomission PoC environment for test/dev situations in order to clean up resources & reduce cost
* Removed test based commenting
* Added #Requires -Version 5.0 to support new package management features, which will download required modules from www.powershellgallery.com
* Added the requirement in the description to include the c:\deployment folder for DSC resources, package and artifacts
* Updated script to use managed disks instead of unmanaged for VM OS and data disks 
* Prompt for credentials with the $creds variable earlier in the script within the INITIALIZATION region before the main script, right after prompting for the subscription name
  This allows to the operator to quickly specify all required user parameters without having to wait for a long period before looking for an interacting again with the script for it to continue. 
* Replaced Standard_D1 size with Standard_D1_v2 since performance is better and cost is the same.
* Added the -managed parameter to the IIS availability set to integrate with the managed disk feature
* Corrected $iisVmConfig01= New-AzureRmVMConfig -VMName $vmName -VMSize "Standard_D1" -AvailabilitySetId $IISAVSet.Id, to use the upgraded "Standard_D1_v2" size instead
* Re-added the load balancer Dns A record test for global uniqueness
* Adjusted indentation of loops and conditional blocks using tabs
* (Get-AzureRmSubscription).SubscriptionName fails to provide the name property. Fixed by changing 'SubscriptionName' property to just 'Name'.
* Review and test script with latest Azure module 4.3.1. Test OK.
* Added two functions: Converted code for creating custom log and transcipt as new function & added another function to automatically download required GitHub repository files.
* Extract downloaded DSC.zip file from GitHub to new directory named c:\deployment\DSC and remove original DSC.zip file.
* Remove New-Log file function and placed the code contents inline with main script due to scope issue.
* Use -Force parameter for Expand-Archive for DSC.zip due to: <[Write-Error], IOException> terminating error.
* Script name truncated from log and transcript filenames. [fixed]
#>

$errorActionPreference = [System.Management.Automation.ActionPreference]::Stop

#region LOGGING

#endregion LOGGING

#----------------------------------------------------------------------------------------------------------------------
# Functions
#----------------------------------------------------------------------------------------------------------------------

#region FUNCTIONS

function Get-GitHubRepositoryFile
{
<#
.Synopsis
   Download selected files from a Github repository to a local directory or share
.DESCRIPTION
   This function downloads a specified set of files from a Github repository to a local drive or share, which can include a *.zipped file
.EXAMPLE
   Get-GithubRepositoryFiles -Owner <Owner> -Repository <Repository> -Branch <Branch> -Files <Files[]> -DownloadTargetDirectory <DownloadTargetDirectory>
.NOTES
    Author: Preston K. Parsard; https://github.com/autocloudarc
    REQUIREMENTS: 
    1. The repository from which the script artifacts are downloaded must be public to avoid additional authentication requirements
.LINK
    http://windowsitpro.com/powershell/use-net-webclient-class-powershell-scripts-access-web-data
    http://windowsitpro.com/site-files/windowsitpro.com/files/archive/windowsitpro.com/content/content/99043/listing_03.txt
#>
    [CmdletBinding()]
    Param
    (
        # Please provide the repository owner
        [Parameter(Mandatory=$true,
                   Position=0)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]$owner,

        # Please provide the name of the repository
        [Parameter(Mandatory=$true,
                   Position=1)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]$repository,

        # Please provide a branch to download from
        [Parameter(Mandatory=$false,
                   Position=2)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string]$branch,

        # Please provide the list of files to download
        [Parameter(Mandatory=$true,
                   Position=3)]
        [ValidateNotNull()]
        [ValidateNotNullOrEmpty()]
        [string[]]$files,
        
        
        # Please provide a local target path for the GitHub files and folders
        [Parameter(Mandatory=$true,
                   Position=4,
                   HelpMessage = "Please provide a local target directory for the GitHub files and folders")]
        [string]$downloadTargetDirectory
    ) #end param

    Begin
    {
        # Write-WithTime -Output "Downloading and installing" -Log $Log
        $wc = New-Object System.Net.WebClient
        $rawGitHubUriPrefix = "https://raw.githubusercontent.com"
    } #end begin
    Process
    {
        foreach ($file in $files)
        {
            # Write-WithTime -Output "Processing $file..." -Log $log
            # File download
            $uri = $rawGitHubUriPrefix, $owner, $repository, $branch, $file -Join "/"
            # Write-WithTime -Output "Attempting to download from $uri" -Log $log 
            $downloadTargetPath = Join-Path -Path $downloadTargetDirectory -ChildPath $file 
            $wc.DownloadFile($uri, $downloadTargetPath)
        } #end foreach
    } #end process
    End
    {
    } #end end
} #end function

function Create-DSCPackage
{
	param
	(
		[string]$dscScriptsFolder,
		[string]$outputPackageFolder,
		[string]$dscConfigFile
	)
    # Create DSC configuration archive
    if (Test-Path $dscScriptsFolder) {
        Add-Type -Assembly System.IO.Compression.FileSystem
        $archiveFile = Join-Path $outputPackageFolder "$dscConfigFile.zip"
        Remove-Item -Path $archiveFile -ErrorAction SilentlyContinue
        [System.IO.Compression.ZipFile]::CreateFromDirectory($dscScriptsFolder, $archiveFile)
    }
	else
	{
		throw "DSC path $dscScriptsFolder does not exist"
	}
}

function Upload-BlobFile
{
    param
    (
        [string]$ResourceGroupName,
        [string]$storageAccountName,
        [string]$containerName,
        [string]$fullFileName
    )
 
    # Checks if source file exists
    if (!(Test-Path $fullFileName))
    {
        throw "File $fullFileName does not exist."
    }

    $storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $resourceGroupName -Name $storageAccountName 
   
    if ($storageAccount -ne $null)
    {
        # Create container
        New-AzureStorageContainer -Name $containerName -Context $storageAccount.Context -Permission Container -ErrorAction SilentlyContinue

        # Uploads a file
        $blobName = [System.IO.Path]::GetFileName($fullFileName)

        Set-AzureStorageBlobContent -File $fullFileName -Blob $blobName -Container $containerName -Context $storageAccount.Context -Force
    }
    else
    {
        throw "Storage Account $storageAccountName could not be found at resource group named $resourceGroupName"
    }
}

function Invoke-AzureRmPowershellDSCAD
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$outputPackageFolder,

        [Parameter(Mandatory=$true)]
        [string]$dscScriptsFolder,

        [Parameter(Mandatory=$true)]
        [string]$dscConfigFile,

        [Parameter(Mandatory=$true)]
        [string]$dscConfigFunction,

        [Parameter(Mandatory=$false)]
        [string]$dscConfigDataFile,

        [Parameter(Mandatory=$true)]
        [string]$resourceGroupName,

        [Parameter(Mandatory=$true)]
        [string]$vmName,

        [Parameter(Mandatory=$true)]
        [string]$stagingSaName,

        [Parameter(Mandatory=$true)]
        [string]$stagingSaResourceGroupName,

        [Parameter(Mandatory=$false)]
        [PSCredential]$Credentials
    )
    
    $outputPackagePath = Join-Path $outputPackageFolder "$dscConfigFile.zip"
    $configurationPath = Join-Path $dscScriptsFolder $dscConfigFile
    $configurationDataPath = Join-Path $dscScriptsFolder $dscConfigDataFile

    # Create DSC configuration archive
	Create-DSCPackage -dscScriptsFolder $dscScriptsFolder -outputPackageFolder $outputPackageFolder -dscConfigFile $dscConfigFile

    # Uploading DSC configuration archive
    Upload-BlobFile -storageAccountName $stagingSaName -ResourceGroupName $stagingSaResourceGroupName -containerName "windows-powershell-dsc" -fullFileName $outputPackagePath
	
	##
    ## In order to know current extension version, you can use the following cmdlet to obatain it (user must be co-admin of the subscription and a subscription in ASM mode must be set as default)
    ## $dscExt = Get-AzureVMAvailableExtension -ExtensionName DSC -Publisher Microsoft.Powershell
	##

    # Executing Powershell DSC Extension on VM
    Set-AzureRmVMDscExtension   -ResourceGroupName $resourceGroupName `
                                -VMName $vmName `
                                -ArchiveBlobName "$dscConfigFile.zip" `
                                -ArchiveStorageAccountName $stagingSaName `
                                -ArchiveResourceGroupName $stagingSaResourceGroupName `
                                -ConfigurationData $configurationDataPath `
                                -ConfigurationName $dscConfigFunction `
                                -ConfigurationArgument @{"DomainAdminCredentials"=$Credentials} `
                                -Version "2.1" `
                                -AutoUpdate -Force -Verbose
} 

function Invoke-AzureRmPowershellDSCIIS
{
    param
    (
        [Parameter(Mandatory=$true)]
        [string]$outputPackageFolder,

        [Parameter(Mandatory=$true)]
        [string]$dscScriptsFolder,

        [Parameter(Mandatory=$true)]
        [string]$dscConfigFile,

        [Parameter(Mandatory=$true)]
        [string]$dscConfigFunction,

        [Parameter(Mandatory=$true)]
        [string]$resourceGroupName,

        [Parameter(Mandatory=$true)]
        [string]$vmName,

        [Parameter(Mandatory=$true)]
        [string]$stagingSaName,

        [Parameter(Mandatory=$true)]
        [string]$stagingSaResourceGroupName
    )
    
    $outputPackagePath = Join-Path $outputPackageFolder "$dscConfigFile.zip"
    $configurationPath = Join-Path $dscScriptsFolder  $dscConfigFile
    $configurationDataPath = Join-Path $dscScriptsFolder $dscConfigDataFile

    # Create DSC configuration archive
	Create-DSCPackage -dscScriptsFolder $dscScriptsFolder -outputPackageFolder $outputPackageFolder -dscConfigFile $dscConfigFile

    # Uploading DSC configuration archive
    Upload-BlobFile -storageAccountName $StagingSaName -ResourceGroupName $stagingSaResourceGroupName -containerName "windows-powershell-dsc" -fullFileName $outputPackagePath 

	##
    ## In order to know current extension version, you can use the following cmdlet to obatin it (user must be co-admin of the subscription and a subscription in ASM mode must be set as default)
    ## $dscExt = Get-AzureVMAvailableExtension -ExtensionName DSC -Publisher Microsoft.Powershell
	##

    # Executing Powershell DSC Extension on VM
	Set-AzureRmVMDscExtension   -ResourceGroupName $resourceGroupName `
                                    -VMName $vmName `
                                    -ArchiveBlobName "$dscConfigFile.zip" `
                                    -ArchiveStorageAccountName $stagingSaName `
                                    -ArchiveResourceGroupName $stagingSaResourceGroupName `
                                    -ConfigurationName $dscConfigFunction `
                                    -Version "2.1" `
                                    -AutoUpdate -Force -Verbose
} 

Function New-RandomString
{
    $combinedCharArray = @()
    $complexityRuleSets = @()
    $passwordArray = @()
    # PCR here means [P]assword [C]omplexity [R]equirement, so the $PCRSampleCount value represents the number of characters that will be generated for each password complexity requirement (alpha upper, lower, and numeric)
    $pcrSampleCount = 4
    $pcr1AlphaUpper = ([char[]]([char]65..[char]90))
    $pcr3AlphaLower = ([char[]]([char]97..[char]122))
    $pcr4Numeric = ([char[]]([char]48..[char]57))

    # Add all of the PCR... arrays into a single consolidated array
    $combinedCharArray = $pcr1AlphaUpper + $pcr3AlphaLower + $prc4Numeric
    # This is the set of complexity rules, so it's an array of arrays
    $complexityRuleSets = ($pcr1AlphaUpper, $pcr3AlphaLower, $pcr4Numeric)

    # Sample 4 characters from each of the 3 complexity rule sets to generate a complete 12 character random string
    ForEach ($complexityRuleSet in $complexityRuleSets)
    {
        Get-Random -InputObject $complexityRuleSet -Count $pcrSampleCount | ForEach-Object { $passwordArray += $_ }
    } #end ForEach

    [string]$randomStringWithSpaces = $passwordArray
    $RandomString = $RandomStringWithSpaces.Replace(" ","")
    return $RandomString
} #end Function

#endregion FUNCTIONS

#region INITIALIZE
#----------------------------------------------------------------------------------------------------------------------
# Script Start
#----------------------------------------------------------------------------------------------------------------------

# Authenticate to Azure
Add-AzureRmAccount

# Start time so that total script execution time can be measured at script completion.
$beginTimer = Get-Date -Verbose

# Create both log and transcript files to record script activities
[string]$scriptName = $myInvocation.myCommand
$scriptFileComponents = $scriptName.Split(".")
$logDirectory = $scriptFileComponents[0]

# Construct custom path for log files based on current user's $env:HOMEPATH directory for both the log and transcript files
$logPath = $env:HOMEPATH + "\" + $logDirectory
If (!(Test-Path $logPath))
{
    New-Item -Path $logPath -ItemType Directory
} #End If

# Create both log and transcript files with time/date stamps included in their filenames
$startTime = (((get-date -format u).Substring(0,16)).Replace(" ", "-")).Replace(":","")
$24hrTime = $startTime.Substring(11,4)

$logFile = "$logDirectory-LOG" + "-" + $startTime + ".log"
$transcriptFile = "$logDirectory-TRANSCRIPT" + "-" + $startTime + ".log"
$log = Join-Path -Path $logPath -ChildPath $logFile
$transcript = Join-Path $logPath -ChildPath $transcriptFile
# Create Log file
New-Item -Path $log -ItemType File -Verbose
# Create Transcript file
New-Item -Path $transcript -ItemType File -Verbose

Start-Transcript -Path $transcript -IncludeInvocationHeader -Append -Verbose

# Get GitHub files
 [string[]]$filesToDownload = "DSC.zip"
 
 $owner = "paulomarquesc"
 $repository = "AzurePowerShellSampleDeployment"
 $branch = "master"
 $deployPath = "c:\deployment"
 
 $targetZipFile = Join-Path -Path $deployPath -ChildPath $filesToDownload[0] 
 $manualDownloadMessage = "@
1) Create an empty folder in the VM at the path C:\deployment
2) Navigate to the following repository in GitHub. https://github.com/paulomarquesc/AzurePowerShellSampleDeployment 
3) Copy the DSC.zip into the new C:\deployment directory.
4) Copy the PowerShell-PoC-Environmet-Setup.ps1 script into a new directory named c:\scripts.
5) Extract the DSC.zip file to the C:\deployment directory
6) Remove the DSC.zip file from the C:\deployment directory, but leave the extracted DSC directory in place.
@"

 If (-not(Test-Path -Path $deployPath))
 {
    New-Item -Path $deployPath -ItemType Directory -Force
 } #end if

 # Write-WithTime -Output "Downloading required files from GitHub..." -Log $Log 
 Get-GitHubRepositoryFile -Owner $owner -repository $repository -branch $branch -files $filesToDownload -downloadTargetDirectory $deployPath -Verbose

 If (!(Test-Path -Path $targetZipFile))
 {
    Write-ToConsoleAndLog -Output "There was an error downloading file $filesToDownload[0]..." -Log
    Write-ToConsoleAndLog -Output "Please download $filesToDownload[0] manually to $deployPath and press enter to continue by following the instructions below" -Log
    Write-ToConsoleAndLog -Output "" -Log $log
    Write-ToConsoleAndLog -Output $manualDownloadMessage -Log $log
    pause
 } #end if

 $zipFolderName = ($targetZipFile | Split-Path -Leaf).Split(".")[0]
 $zipFolderPath = Join-Path $deployPath -ChildPath $zipFolderName
 If (-not(Test-Path -Path $zipFolderPath))
 {
    New-Item -Path $zipFolderPath -ItemType Directory
 } #end if 
 Expand-Archive -Path $targetZipFile -DestinationPath $zipFolderPath -Force -Verbose

If (Test-Path -Path $targetZipFile) 
{
    Remove-Item -Path $targetZipFile
} #end if

# Location Definition
$westLocation = "westus"
$eastLocation = "eastus"

# Create and populate prompts object with property-value pairs
# PROMPTS (promptsObj)
$promptsObj = [PSCustomObject]@{
    pAskToOpenLogs = "Would you like to open the deployment logs now ? [YES/NO]"
} #end $PromptsObj

# Create and populate responses object with property-value pairs
# RESPONSES (ResponsesObj): Initialize all response variables with null value
$responsesObj = [PSCustomObject]@{
    pOpenLogsNow = $null
} #end $ResponsesObj

# To avoid multiple versions installed on the same system, first uninstall any previously installed and loaded versions if they exist
If (Get-Module | Where-Object { $_.Name -eq 'WriteToLogs'})
{
    Uninstall-Module -Name WriteToLogs -AllVersions -ErrorAction SilentlyContinue -Verbose
} #end if

# Next, install and import it for use later in the script for logging operations
# https://www.powershellgallery.com/packages/WriteToLogs
Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-PackageProvider -Name Nuget -ForceBootstrap -Force 
Install-Module -Name WriteToLogs -Repository PSGallery -Force -Verbose
Import-Module -Name WriteToLogs -Verbose

Do
{
    # Subscription name
    $defaultSubscription = (Get-AzureRmSubscription).Name
    Write-ToConsoleAndLog -Output "Default subsriptions found are: $defaultSubscription" -Log $log
    $subscriptionPrompt = "Please enter your subscription name "
    Write-ToLogOnly -Output $subscriptionPrompt -Log $Log
    [string] $Subscription = Read-Host $subscriptionPrompt
    $Subscription = $Subscription.ToUpper()
} #end Do
Until (($Subscription) -ne $null)

# Selects subscription based on subscription name provided in response to the prompt above
Select-AzureRmSubscription -SubscriptionName $Subscription

# Prompt for credentials
$locAdmin = "localadmin"
$creds = Get-Credential -UserName $locAdmin -Message "Enter password for user: $locAdmin"

##
## How to obtain Azure Powershell Module Version 
## Get-Module -ListAvailable -Name Azure
##
## How to get a list of subscriptions you have access
## Get-AzureRmSubscription
##

#endregion INITIALIZE

#region MAIN

$delimDouble = ("=" * 100 )
$Header = "AZURE RM POWERSHELL POC DEPLOYMENT DEMO: " + $startTime

# Display header
Write-ToConsoleAndLog -Output $delimDouble -Log $Log
Write-ToConsoleAndLog -Output $Header -Log $Log
Write-ToConsoleAndLog -Output $delimDouble -Log $Log

# Resource Group Creation
Write-WithTime -Output "Creating resource groups" -Log $Log

$rgWest = New-AzureRmResourceGroup -Name "poc-west-rg" -Location $westLocation
$rgEast = New-AzureRmResourceGroup -Name "poc-east-rg" -Location $eastLocation
$rgStorage = New-AzureRmResourceGroup -Name "poc-storage-rg" -Location $eastLocation

##
## How to get a resource group if needed
## $rgWest = Get-AzureRmResourceGroup -Name "poc-west-rg" -Location $westLocation
## $rgEast = Get-AzureRmResourceGroup -Name "poc-east-rg" -Location $eastLocation
## $rgStorage = Get-AzureRmResourceGroup -Name "poc-storage-rg" -Location $eastLocation
##

#----------------------------------------------------------------------------------------------------------------------
# Virtual networks section - including Subnets, Vnets, Vnet-to-Vnet VPN, load balancer and basic Network security Group
#----------------------------------------------------------------------------------------------------------------------

### Start of Virtual Networks Section

# Subnets Creation
Write-WithTime -Output "Creating Subnets..." -Log $Log

# Subnets belonging to West Location
$gwSNNameWest = "GatewaySubnet"
$gwSNWest = New-AzureRmVirtualNetworkSubnetConfig -Name $gwSNNameWest -AddressPrefix "10.0.255.0/24"

$infraSNNameWest = "West-VNET-Infrastructure-Subnet"
$infraSNWest = New-AzureRmVirtualNetworkSubnetConfig -Name $infraSNNameWest -AddressPrefix "10.0.0.0/24"

# Subnets belonging to East Location
$gwSNNameEast = "GatewaySubnet"
$gwSNEast = New-AzureRmVirtualNetworkSubnetConfig -Name $gwSNNameEast -AddressPrefix "192.168.255.0/24"

$appSNNameEast = "East-VNET-App-Subnet"
$appSNEast = New-AzureRmVirtualNetworkSubnetConfig -Name $appSNNameEast -AddressPrefix "192.168.0.0/24"

# West Virtual Network Creation
Write-WithTime -Output "Creating west virtual network" -Log $Log
$vnetwest = New-AzureRmVirtualNetwork -Name "West-VNET" -ResourceGroupName $rgWest.ResourceGroupName -Location $westLocation -AddressPrefix "10.0.0.0/16" -Subnet $infraSNWest,$gwSNWest
# Eest Virtual Network Creation
Write-WithTime -Output "Creating east virtual network" -Log $Log
$vneteast = New-AzureRmVirtualNetwork -Name "East-VNET" -ResourceGroupName $rgEast.ResourceGroupName -Location $eastLocation -AddressPrefix "192.168.0.0/16" -Subnet $appSNEast,$gwSNEast 

# Establishing VNET to VNET Connection

# West side
Write-WithTime -Output "Establishing VNET to VNET Connection, working on west side" -Log $Log

# Public IP Address of the West Gateway
$gwpipWest = New-AzureRmPublicIpAddress -Name "$westLocation-gwpip" -ResourceGroupName $rgWest.ResourceGroupName -Location $westLocation -AllocationMethod Dynamic 

# West Gateway IP Configuration
$vnet = Get-AzureRmVirtualNetwork -Name "West-VNET" -ResourceGroupName $rgWest.ResourceGroupName
$subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -VirtualNetwork $vnet 

$gwipconfigWest = New-AzureRmVirtualNetworkGatewayIpConfig -Name "$westlocation-gwipconfig" -SubnetId $subnet.Id -PublicIpAddressId $gwpipWest.Id 

# Creating West Gateway
Write-WithTime -Output "Creating West Gateway" -Log $Log

New-AzureRmVirtualNetworkGateway -Name "$westlocation-vnet-Gateway" `
                    -ResourceGroupName $rgWest.ResourceGroupName `
                    -Location $westlocation `
                    -IpConfigurations $gwipconfigWest `
                    -GatewayType Vpn `
                    -VpnType RouteBased `
                    -GatewaySku Basic `
                    -EnableBgp:$false

# East side
# Public IP Address of the East Gateway
$gwpipEast = New-AzureRmPublicIpAddress -Name "$eastLocation-gwpip" -ResourceGroupName $rgEast.ResourceGroupName -Location $eastLocation -AllocationMethod Dynamic 

#East Gateway IP Configuration
$vnet = Get-AzureRmVirtualNetwork -Name "East-VNET" -ResourceGroupName $rgEast.ResourceGroupName
$subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name 'GatewaySubnet' -VirtualNetwork $vnet 

$gwipconfigEast = New-AzureRmVirtualNetworkGatewayIpConfig -Name "$eastlocation-gwipconfig" -SubnetId $subnet.Id -PublicIpAddressId $gwpipEast.Id 

#Creating East Gateway
New-AzureRmVirtualNetworkGateway -Name "$eastlocation-vnet-Gateway" `
                    -ResourceGroupName $rgEast.ResourceGroupName `
                    -Location $eastlocation `
                    -IpConfigurations $gwipconfigEast `
                    -GatewayType Vpn `
                    -VpnType RouteBased `
                    -GatewaySku Basic `
                    -EnableBgp:$false

# Getting public ip of Gateway on West Location
$gw = Get-AzureRmVirtualNetworkGateway -ResourcegroupName $rgWest.ResourceGroupName
$westGwPIP = (Get-AzureRmPublicIpAddress | ? { $_.id -eq $gw.IpConfigurations.publicipaddress.id }).IpAddress

# Getting public of Gateway on East Location
$gw = Get-AzureRmVirtualNetworkGateway -ResourcegroupName $rgEast.ResourceGroupName
$eastGwPIP = (Get-AzureRmPublicIpAddress | ? { $_.id -eq $gw.IpConfigurations.publicipaddress.id }).IpAddress

# Connecting Gateways
Write-WithTime -Output "Connecting Gateways" -Log $Log

# Creating Local Network Gateway on West Location
New-AzureRmLocalNetworkGateway -Name "$eastlocation-LocalNetworkGateway" -ResourceGroupName $rgWest.ResourceGroupName -Location $westlocation -GatewayIpAddress $eastGwPIP -AddressPrefix @("192.168.0.0/16")

# Creating Local Network Gateway on East Location
New-AzureRmLocalNetworkGateway -Name "$westlocation-LocalNetworkGateway" -ResourceGroupName $rgEast.ResourceGroupName -Location $eastlocation -GatewayIpAddress $westGwPIP -AddressPrefix @("10.0.0.0/16")

# Creating West Gateway Connection
$gatewayWest = Get-AzureRmVirtualNetworkGateway -Name "$westlocation-vnet-Gateway" -ResourceGroupName $rgWest.ResourceGroupName
$localWest = Get-AzureRmLocalNetworkGateway -Name "$eastlocation-LocalNetworkGateway" -ResourceGroupName $rgWest.ResourceGroupName

# Format and truncate the results of a randomly generated subset of numeric and lowercase combination of characters
[string]$sharedKey = (New-Guid).Guid.Replace("-","").Substring(0,8)

New-AzureRmVirtualNetworkGatewayConnection -Name "$westlocation-gwConnection" `
                    -ResourceGroupName $rgWest.ResourceGroupName `
                    -Location $westlocation `
                    -VirtualNetworkGateway1 $gatewayWest `
                    -LocalNetworkGateway2 $localWest `
                    -ConnectionType IPsec `
                    -RoutingWeight 10 `
                    -SharedKey $sharedKey

# Creating East Gateway Connection
$gatewayEast = Get-AzureRmVirtualNetworkGateway -Name "$eastlocation-vnet-Gateway" -ResourceGroupName $rgEast.ResourceGroupName
$localEast = Get-AzureRmLocalNetworkGateway -Name "$westlocation-LocalNetworkGateway" -ResourceGroupName $rgEast.ResourceGroupName

New-AzureRmVirtualNetworkGatewayConnection -Name "$eastlocation-gwConnection" `
                    -ResourceGroupName $rgEast.ResourceGroupName `
                    -Location $eastlocation `
                    -VirtualNetworkGateway1 $gatewayEast `
                    -LocalNetworkGateway2 $localEast `
                    -ConnectionType IPsec `
                    -RoutingWeight 10 `
                    -SharedKey $sharedKey

# Creating load balancer that will be used by IIS servers

# Azure Load Balancer Public Ip Address
Write-WithTime -Output "Creating the IIS Loadbalancer" -Log $Log

# Add a random infix (4 numeric digits) inside the Dnslabel name to avoid conflicts with existing deployments generated from this script. 
# The -pip suffix indicates this is a public IP
# Additionally a DNS resolutionn test is made for the generated fqdn for the load balancer to ensure it is globablly unique in DNS before proceeding.
# This is performed to avoid potential conflicts, where if the DNS name is already taken, it may resolve to the wrong IP address.

Do
{
    $randomString = New-RandomString
    [string]$dnsLabelInfix = $randomString.SubString(8,4)
    $albPublicIpDNSName = "pociisalb-" + $dnsLabelInfix + "-pip"
    $dnsSuffix = ".cloudapp.azure.com"
    $albFqdn = $albPublicIpDNSName + "." + $eastLocation + $dnsSuffix
} #end Do
Until (-not(Resolve-DnsName $albFqdn -Type A -ErrorAction SilentlyContinue))

$albPublicIP = New-AzureRmPublicIpAddress -Name "albIISpip" -ResourceGroupName $rgEast.ResourceGroupName -Location $eastlocation –AllocationMethod Static -DomainNameLabel $albPublicIpDNSName

##
## If you want to get the existing load balancer resource you can use the following cmdlet
## $albPublicIP = Get-AzureRmPublicIpAddress -ResourceGroupName $rgEast.ResourceGroupName -Name "albIISpip"
##

# Defining Load Balancer items

# Front end IP Pool
$frontendIP = New-AzureRmLoadBalancerFrontendIpConfig -Name "albIISFrontEndIpConfig" -PublicIpAddress $albPublicIP

# Back End IP Pool
$beAddresspool = New-AzureRmLoadBalancerBackendAddressPoolConfig -Name "albIISBackEndIpConfig"

# NAT Rules - one Nat rule per server and public port, two in this case because we have two IIS servers attached to the LB
$inboundNATRule1= New-AzureRmLoadBalancerInboundNatRuleConfig -Name "IIS1Nat-RDP" -FrontendIpConfiguration $frontendIP -Protocol TCP -FrontendPort 3441 -BackendPort 3389
$inboundNATRule2= New-AzureRmLoadBalancerInboundNatRuleConfig -Name "IIS2Nat-RDP" -FrontendIpConfiguration $frontendIP -Protocol TCP -FrontendPort 3442 -BackendPort 3389

# HTTP probe
$wwwHealthProbe = New-AzureRmLoadBalancerProbeConfig -Name "WWWProbe" -RequestPath '/' -Protocol Http -Port 80 -IntervalInSeconds 10 -ProbeCount 2                  

# Load Balancer rule
$lbRule1 = New-AzureRmLoadBalancerRuleConfig -Name HTTP `
                    -FrontendIpConfiguration $frontendIP `
                    -BackendAddressPool  $beAddressPool `
                    -Probe $wwwHealthProbe `
                    -Protocol Tcp `
                    -FrontendPort 80 `
                    -BackendPort 80

# Load Balancer
$IISAlb = New-AzureRmLoadBalancer -ResourceGroupName $rgEast.ResourceGroupName `
                    -Name "POC-IIS-ALB" `
                    -Location $eastLocation `
                    -FrontendIpConfiguration $frontendIP `
                    -InboundNatRule $inboundNATRule1,$inboundNatRule2 `
                    -LoadBalancingRule $lbRule1 `
                    -BackendAddressPool $beAddressPool `
                    -Probe $wwwHealthProbe 

# Public IP Address of Domain Controller - in this case we showcase that attached a server directly to a public ip address is possible
$dcpip = New-AzureRmPublicIpAddress -Name "dcpip" -ResourceGroupName $rgWest.ResourceGroupName -Location $westLocation -AllocationMethod Dynamic

# Creates NSG (Network Security Group) Rule for Domain Controller. Basically allow RDP from public network, allow all from east subnet.
Write-WithTime -Output "Network Security Group" -Log $Log 

$rules = @()

$rules +=  New-AzureRmNetworkSecurityRuleConfig -Name "allow-rdp" `
			-Description "Allow inbound RDP from internet" `
			-Access Allow `
			-Protocol Tcp `
			-Direction Inbound `
			-Priority 100 `
			-SourceAddressPrefix Internet `
			-SourcePortRange * `
			-DestinationAddressPrefix * `
			-DestinationPortRange 3389

$rules +=  New-AzureRmNetworkSecurityRuleConfig -Name "allow-all-eastsubnet" `
			-Description "Allow inbound all ports from east subnet" `
			-Access Allow `
			-Protocol * `
			-Direction Inbound `
			-Priority 300 `
			-SourceAddressPrefix "192.0.0.0/16" `
			-SourcePortRange * `
			-DestinationAddressPrefix * `
			-DestinationPortRange *

# Create Network Security Group resource
$nsg =  New-AzureRmNetworkSecurityGroup -Name "DC-NSG" -ResourceGroupName $rgWest.ResourceGroupName -Location $westLocation -SecurityRules $rules

# Creates NSG (Network Security Group) Rule for IIS Subnet. Basically allow 3389 and 80 from public network, allow all from west subnet, 80 and 3389 from the load balancer.

$rules = @()

$rules +=  New-AzureRmNetworkSecurityRuleConfig -Name "allow-rdp" `
			-Description "Allow inbound RDP from loadbalancer" `
			-Access Allow `
			-Protocol Tcp `
			-Direction Inbound `
			-Priority 100 `
			-SourceAddressPrefix * `
			-SourcePortRange * `
			-DestinationAddressPrefix * `
			-DestinationPortRange 3389

$rules +=  New-AzureRmNetworkSecurityRuleConfig -Name "allow-80" `
			-Description "Allow inbound 80 from loadbalancer" `
			-Access Allow `
			-Protocol Tcp `
			-Direction Inbound `
			-Priority 200 `
			-SourceAddressPrefix * `
			-SourcePortRange * `
			-DestinationAddressPrefix * `
			-DestinationPortRange 80

$rules +=  New-AzureRmNetworkSecurityRuleConfig -Name "allow-all-westsubnet" `
			-Description "Allow inbound all ports from west subnet" `
			-Access Allow `
			-Protocol * `
			-Direction Inbound `
			-Priority 300 `
			-SourceAddressPrefix "10.0.0.0/16" `
			-SourcePortRange * `
			-DestinationAddressPrefix * `
			-DestinationPortRange *

$eastSnNsg =  New-AzureRmNetworkSecurityGroup -Name "East-SN-NSG" -ResourceGroupName $rgEast.ResourceGroupName -Location $eastLocation -SecurityRules $rules

# Associate NSG to Vnet
$vnet = Get-AzureRmVirtualNetwork -Name "East-VNET" -ResourceGroupName $rgEast.ResourceGroupName
$subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $AppSNNameEast -VirtualNetwork $vnet 

Set-AzureRmVirtualNetworkSubnetConfig -Name $AppSNNameEast -VirtualNetwork $vnet -NetworkSecurityGroup $eastSnNsg -AddressPrefix $subnet.AddressPrefix | `
	Set-AzureRmVirtualNetwork 

### End of Virtual Networks Section

### Start of Storage Accounts Section

##
## if you need to get an existing availability set resource you can use the following cmdlet
## $IISAVSet = Get-AzureRmAvailabilitySet -ResourceGroupName $rgEast.ResourceGroupName -Name $IISAVSetName
##

#-------------------------------------------------------
# Create Storage Account for East Region & West Region
#-------------------------------------------------------
# NOTE: Storage accounts will only be used to host the uploaded DSC configuration and data files, as well as modules for the domain controller and IIS server configuration tasks.
# Storage accounts will not be used for hosting the OS or data disk vhd drives for the VMs. This is because managed disks will be used instead for all VMs.
Write-WithTime -Output "Create Storage Account for East Region & West Region" -Log $Log

# Create a new random string, then extract the 4 digits to use as the last characters for the storage account name for each region
# If the storage account name has already been taken, i.e. not available, continue to generate a new name that can be used
Do 
{
    $randomString = New-RandomString
    $saWestName  = $randomString.Substring(4,8)
} #end while
While (!((Get-AzureRmStorageAccountNameAvailability -Name $saWestName).NameAvailable)) 

New-AzureRmStorageAccount -ResourceGroupName $rgStorage.ResourceGroupName -Name $saWestName -Location $westLocation -Type Standard_LRS -Kind Storage 

# Create a new random string, then extract the 4 digits to use as the last characters for the storage account name for each region
# If the storage account name has already been taken, i.e. not available, continue to generate a new name that can be used
Do 
{
    $randomString = New-RandomString
    $saEastName = $randomString.Substring(4,8)
} #end while
While (!((Get-AzureRmStorageAccountNameAvailability -Name $saEastName).NameAvailable)) 

New-AzureRmStorageAccount -ResourceGroupName $rgStorage.ResourceGroupName -Name $saEastName -Location $eastLocation -Type Standard_LRS -Kind Storage

### End of Storage Accounts Section

### Start of Deploying VMs Section

#---------------------------------------------- 
# Deploying VMs
#---------------------------------------------- 

# Windows 2012R2 VM Image
Write-WithTime -Output "Selecting Windows 2012R2 VM Image" -Log $Log 
$vmRmImage = (Get-AzureRmVMImage -PublisherName "MicrosoftWindowsServer" -Location $westlocation -Offer "WindowsServer" -Skus "2012-R2-Datacenter" | Sort-Object -Descending -Property Version)[0]

# Domain Controller
Write-WithTime -Output "Deploying a Domain Controller VM" -Log $Log 
$vmName = "dc"

# VM nic
Write-WithTime -Output " Setting up nic" -Log $Log

$vnet  = Get-AzureRmVirtualNetwork -ResourceGroupName $rgWest.ResourceGroupName -Name "West-Vnet"
$subnet = Get-AzureRmVirtualNetworkSubnetConfig -Name $infraSNNameWest -VirtualNetwork $vnet 

$dcnic = New-AzureRmNetworkInterface -ResourceGroupName $rgWest.ResourceGroupName `
                    -Location $westLocation `
                    -Name "$vmName-nic" `
                    -PrivateIpAddress "10.0.0.4" `
                    -PublicIpAddress $dcpip `
                    -Subnet $subnet `
                    -NetworkSecurityGroup $nsg 

##
## Optionally getting reference of an existing Nic
## $dcnic = Get-AzureRmNetworkInterface -ResourceGroupName $rgWest.ResourceGroupName -name "dc-nic"
##
 
# VM Config
Write-WithTime -Output " Working on vm configuration" -Log $Log

# Construct the drive names for the SYSTEM and DATA drives
$vmOSDiskName = [string]::Format("{0}-OSDisk",$vmName)
$vmDataDiskName = [string]::Format("{0}-DataDisk",$vmName)

$dc01VmConfig = New-AzureRmVMConfig -VMName $vmName -VMSize "Standard_D1_v2" -Verbose

Set-AzureRmVMOperatingSystem -VM $dc01VmConfig -Windows -ComputerName $vmName -Credential $creds -Verbose
Set-AzureRmVMSourceImage -VM $dc01VmConfig -PublisherName $vmRmImage.PublisherName -Offer $vmRmImage.Offer -Skus $vmRmImage.Skus -Version $vmRmImage.Version -Verbose

# Create OS system drive as a managed disk
Set-AzureRmVMOSDisk -VM $dc01VmConfig -Name $vmOSDiskName -StorageAccountType StandardLRS -DiskSizeInGB 128 -CreateOption FromImage -Caching ReadWrite -Verbose
# Add data disk drive as a managed disk
Write-WithTime -Output "Adding data disk for NTDS, SYSV and LOGS directories..." -Log $Log
Add-AzureRmVmDataDisk -VM $dc01VmConfig -Name $vmDataDiskName -StorageAccountType StandardLRS -Lun 0 -DiskSizeInGB 10 -CreateOption Empty -Caching None -Verbose

# Add nic
Add-AzureRmVMNetworkInterface -VM $dc01VmConfig -Id $dcnic.Id

Write-WithTime -Output "Deploying vm" -Log $Log

New-AzureRmVM -ResourceGroupName $rgWest.ResourceGroupName -Location $westlocation -VM $dc01VmConfig

# Promoting VM to be a Domain Controller via Powershell DSC
Write-WithTime -Output "   Running Powershell DSC to promote vm as Domain Controller" -Log $Log
Invoke-AzureRmPowershellDSCAD -OutputPackageFolder c:\deployment `
                            -DscScriptsFolder c:\deployment\DSC `
                            -DscConfigFile DCConfig.ps1 `
                            -DscConfigFunction DcConfig `
                            -dscConfigDataFile ConfigDataAD.psd1 `
                            -ResourceGroupName $rgWest.ResourceGroupName `
                            -VMName $vmName `
                            -StagingSaName $saWestName `
                            -stagingSaResourceGroupName $rgStorage.ResourceGroupName `
                            -Credentials $creds
# End of Domain Controller

# Since Domain Controller now is up and running, configure both virtual networks to use the DC as primary custom DNS instead of Azure DNS
$eastVnet = Get-AzureRmVirtualNetwork -Name "East-VNET" -ResourceGroupName $rgEast.ResourceGroupName
$eastVnet.DhcpOptions.DnsServers = @("10.0.0.4")
Set-AzureRmVirtualNetwork -VirtualNetwork $eastVnet

$westVnet = Get-AzureRmVirtualNetwork -Name "West-VNET" -ResourceGroupName $rgWest.ResourceGroupName
$westVnet.DhcpOptions.DnsServers = @("10.0.0.4")
Set-AzureRmVirtualNetwork -VirtualNetwork $westVnet

# IIS virtual machines

# Creating Availability set for IIS load balanced set and for use with managed disks
$IISAVSetName = "IIS-AS"
Write-WithTime -Output "Creating Availability set for IIS load balanced set and to support managed disk" -Log $Log
$IISAVSet = New-AzureRmAvailabilitySet -ResourceGroupName $rgEast.ResourceGroupName -Name $IISAVSetName -Location $eastlocation -PlatformUpdateDomainCount 5 -PlatformFaultDomainCount 2 -Managed -Verbose 

# IIS01
$vmName = "iis01"
Write-WithTime -Output "Deploying $vmName VM" -Log $Log

# VM nic
Write-WithTime -Output " Setting up nic" -Log $Log

# Getting Vnet and subnet resources
$vnet  = Get-AzureRmVirtualNetwork -ResourceGroupName $rgEast.ResourceGroupName -Name "East-Vnet"
$appSubnet = Get-AzureRmVirtualNetworkSubnetConfig -Name "East-VNET-App-Subnet" -VirtualNetwork $vnet

# Getting Load Balancer if needed 
$IISAlb = Get-AzureRmLoadBalancer -Name "POC-IIS-ALB"  -ResourceGroupName $rgEast.ResourceGroupName

# Nic creation, highlight the usage of DNS direct on NIC
$iis01nic = New-AzureRmNetworkInterface -ResourceGroupName $rgEast.ResourceGroupName `
                    -Location $eastLocation `
                    -Name "$vmName-nic" `
                    -PrivateIpAddress "192.168.0.4" `
                    -Subnet $appSubnet `
                    -LoadBalancerBackendAddressPool $IISAlb.BackendAddressPools[0] `
                    -LoadBalancerInboundNatRule $IISAlb.InboundNatRules[0] `
                    -DnsServer 10.0.0.4

Write-WithTime -Output " Working on vm configuration" -Log $Log

$vmOSDiskName = [string]::Format("{0}-OSDisk",$vmName)
 
$iisVmConfig01= New-AzureRmVMConfig -VMName $vmName -VMSize "Standard_D1_v2" -AvailabilitySetId $IISAVSet.Id

Set-AzureRmVMOperatingSystem -VM $iisVmConfig01 -Windows -ComputerName $vmName -Credential $creds
Set-AzureRmVMSourceImage -VM $iisVmConfig01 -PublisherName $vmRmImage.PublisherName -Offer $vmRmImage.Offer -Skus $vmRmImage.Skus -Version $vmRmImage.Version

# Use managed disk for OS drive
Set-AzureRmVMOSDisk -VM $iisVmConfig01 -Name $vmOSDiskName -StorageAccountType StandardLRS -DiskSizeInGB 128 -CreateOption FromImage -Caching ReadWrite -Verbose

Add-AzureRmVMNetworkInterface -VM $iisVmConfig01 -Id $iis01nic.Id -Verbose

Write-WithTime -Output " Deploying vm" -Log $Log
New-AzureRmVM -ResourceGroupName $rgEast.ResourceGroupName -Location $eastlocation -VM $iisVmConfig01

# Joining virtual machine to the domain 
Write-WithTime -Output " Joining VM to the domain" -Log $Log
$domainName = "contosoad.com"
$JoinDomainUserName = "contosoad\localadmin"

Set-AzureRmVmExtension -ResourceGroupName $rgEast.ResourceGroupName `
                        -ExtensionType "JsonADDomainExtension" `
                        -Name "JoinDomain" `
                        -Publisher "Microsoft.Compute" `
                        -TypeHandlerVersion "1.3" `
                        -VMName $vmname `
                        -Location $eastLocation `
                        -Settings @{ "Name" = $DomainName; "OUPath" = ""; "User" = $JoinDomainUserName; "Restart" = "true"; "Options" = 3} `
                        -ProtectedSettings @{"Password" = "$($creds.GetNetworkCredential().Password)"}  

# Configuring VM to hold IIS feature via Powershell DSC
Write-WithTime -Output " Running PowerShell DSC to configure VM as IIS server" -Log $Log
Invoke-AzureRmPowershellDSCIIS -OutputPackageFolder c:\deployment `
                            -DscScriptsFolder c:\deployment\DSC `
                            -DscConfigFile IISInstall.ps1 `
                            -DscConfigFunction IISInstall `
                            -ResourceGroupName $rgEast.ResourceGroupName `
                            -VMName $vmName  `
                            -StagingSaName $saEastName `
                            -stagingSaResourceGroupName $rgStorage.ResourceGroupName

# IIS 02 VM
$vmName = "iis02"
Write-WithTime -Output "Deploying $vmName VM" -Log $Log
Write-WithTime -Output " Setting up nic" -Log $Log
$iis02nic = New-AzureRmNetworkInterface -ResourceGroupName $rgEast.ResourceGroupName `
                    -Location $eastLocation `
                    -Name "$vmName-nic" `
                    -PrivateIpAddress "192.168.0.5" `
                    -Subnet $appSubnet `
                    -LoadBalancerBackendAddressPool $IISAlb.BackendAddressPools[0] `
                    -LoadBalancerInboundNatRule $IISAlb.InboundNatRules[1] `
                    -DnsServer 10.0.0.4

Write-WithTime -Output " Working on vm configuration" -Log $Log

$vmOSDiskName = [string]::Format("{0}-OSDisk",$vmName)
 
$iisVmConfig02= New-AzureRmVMConfig -VMName $vmName -VMSize "Standard_D1_v2" -AvailabilitySetId $IISAVSet.Id

Set-AzureRmVMOperatingSystem -VM $iisVmConfig02 -Windows -ComputerName $vmName -Credential $creds
Set-AzureRmVMSourceImage -VM $iisVmConfig02 -PublisherName $vmRmImage.PublisherName -Offer $vmRmImage.Offer -Skus $vmRmImage.Skus -Version $vmRmImage.Version

# Use managed disks for OS drive
Set-AzureRmVMOSDisk -VM $iisVmConfig02 -Name $vmOSDiskName -StorageAccountType StandardLRS -DiskSizeInGB 128 -CreateOption FromImage -Caching ReadWrite -Verbose

Add-AzureRmVMNetworkInterface -VM $iisVmConfig02 -Id $iis02nic.Id

Write-WithTime -Output " Deploying vm" -Log $Log
New-AzureRmVM -ResourceGroupName $rgEast.ResourceGroupName -Location $eastlocation -VM $iisVmConfig02

# Joining virtual machine to the domain 
Write-WithTime -Output " Joining VM to the domain" -Log $Log
Set-AzureRmVmExtension -ResourceGroupName $rgEast.ResourceGroupName `
                        -ExtensionType "JsonADDomainExtension" `
                        -Name "JoinDomain" `
                        -Publisher "Microsoft.Compute" `
                        -TypeHandlerVersion "1.3" `
                        -VMName $vmname `
                        -Location $eastLocation `
                        -Settings @{ "Name" = $domainName; "OUPath" = ""; "User" = $joinDomainUserName; "Restart" = "true"; "Options" = 3}  `
                        -ProtectedSettings @{"Password" = "$($creds.GetNetworkCredential().Password)"}  

# Configuring VM to hold IIS feature via Powershell DSC
Write-WithTime -Output " Running PowerShell DSC to configure VM as IIS server" -Log $Log
Invoke-AzureRmPowershellDSCIIS -OutputPackageFolder c:\deployment `
                            -DscScriptsFolder c:\deployment\DSC `
                            -DscConfigFile IISInstall.ps1 `
                            -DscConfigFunction IISInstall `
                            -ResourceGroupName $rgEast.ResourceGroupName `
                            -VMName $vmname  `
                            -StagingSaName $saEastName `
                            -stagingSaResourceGroupName $rgStorage.ResourceGroupName

# End of IIS virtual machines

### End of Deploying VMs Section
#endregion MAIN

#region FOOTER		

# Calculate elapsed time
Write-WithTime -Output "Getting current date/time..." -Log $Log
$stopTimer = Get-Date
$endTime = (((Get-Date -format u).Substring(0,16)).Replace(" ", "-")).Replace(":","")
Write-WithTime -Output "Calculating script execution time..." -Log $Log
$executionTime = New-TimeSpan -Start $beginTimer -End $stopTimer

$Footer = "SCRIPT COMPLETED AT: "

Write-ToConsoleAndLog -Output $delimDouble -Log $Log
Write-ToConsoleAndLog -Output "$Footer $endTime" -Log $Log
Write-ToConsoleAndLog -Output "TOTAL SCRIPT EXECUTION TIME: $executionTime" -Log $Log
Write-ToConsoleAndLog -Output $delimDouble -Log $Log

# Prompt to open logs
Do 
{
    $responsesObj.pOpenLogsNow = read-host $promptsObj.pAskToOpenLogs
    $responsesObj.pOpenLogsNow = $responsesObj.pOpenLogsNow.ToUpper()
}
Until ($responsesObj.pOpenLogsNow -eq "Y" -OR $responsesObj.pOpenLogsNow -eq "YES" -OR $responsesObj.pOpenLogsNow -eq "N" -OR $responsesObj.pOpenLogsNow -eq "NO")

# Exit if user does not want to continue
if ($responsesObj.pOpenLogsNow -eq "Y" -OR $responsesObj.pOpenLogsNow -eq "YES") 
{
    Start-Process notepad.exe $Log
    Start-Process notepad.exe $Transcript
} #end if

# End of script
Write-WithTime -Output "END OF SCRIPT!" -Log $Log

# Close transcript file
Stop-Transcript -Verbose

<#
# Decommission PoC environment by removing all resource groups in sequence (synchronously)
NOTE: [TEST-DEV / POC SCENARIOS ONLY!!!] To quickly and conveniently remove all the resources that this script generated in order to re-run the script, if there are no other resource groups with 
'poc' in the names, you can uncomment and execute the expression below:
#>

# Get-AzureRmResourceGroup | Where-Object { $_.ResourceGroupName -match 'poc' } | Remove-AzureRmResourceGroup -Force

#endregion FOOTER 
