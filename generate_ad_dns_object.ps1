#check if PowerCLI is installed if not it will install
If (-not(Get-InstalledModule "VMware.PowerCLI" -ErrorAction silentlycontinue)) {
    Write-Output "Installing VMware.PowerCLI..."
    Install-Module -Name VMware.PowerCLI -Confirm:$false -AllowClobber -Force
}
$ErrorActionPreference = "silentlycontinue"

#l = Linux W = Windows
$serverType = 'l'
$templateName = "centos7_pkr"

#vSphere resources
$ResourcePool = "Low"

#Naming
$serverName = "linux-01"
$supCode = "1102"

#VM configuration
$MemoryGB = "1"
$NumCpu = "2"
$NetworkName = ""
$DatastoreDSC = "synol"
#Options Thin, Thick, and EagerZeroedThick
$DiskStorageFormat = "Thin"

#Networking Settings
#DNS servers are set in the OSCustomizationSpec
$IpAddress = "0.0.0.0"
$DefaultGateway = ""
$SubnetMask = ""


################################################################################
#   Constant Variables
################################################################################
#$inputMode = 0

$vSphere = "192.168.50.136"

$linuxOU = "OU=Linux,OU=Managed Servers,DC=home,DC=lab"
$windowsOU = "OU=Windows,OU=Managed Servers,DC=home,DC=lab"

$securityGroupsOU = "OU=Servers,OU=Groups,OU=Services,OU=Administration,DC=home,DC=lab"

$dnsServer = "home.lab"
#This var isn't really needed we can concatenate to form needed info  
$serverFQDN = "$($serverName).$(dnsServer)"


$systemAdministratorGroups = "home lab group"

$systemUserGroups = "SSSD Group",
"home lab group"

#Gets the Folder to place the VM based on sup code
$Location = Get-Folder -Name "*$($supCode)*"

#Generate the vSphere VM object name
$vcenterservername = $supCode + "_" + $serverName


################################################################################
#   Script Logic
################################################################################
#Sets logic for Computer object OU
if($serverType.tolower() -eq 'l')
{
   $selectedComputerOU = $linuxOU
   $linuxOSCustomizationSpec = "Linux"
}
elseif($serverType.tolower() -eq 'w')
{
    $selectedComputerOU = $windowsOU
    $linuxOSCustomizationSpec = "Windows"
}


################################################################################
#   Login to vSphere
################################################################################
Write-Output "`Connecting to $($vSphere)..."
Write-Output "`nEnter vSphere credentials:"
$privilegedCredential = Get-Credential

$ErrorActionPreference = "stop"

try
{
    #$vsphereCredential = get-credential -Credential $null
    Connect-VIServer -Server $vSphere -Credential $privilegedCredential
}
catch [VMware.VimAutomation.ViCore.Types.V1.ErrorHandling.InvalidLogin]
{
    Write-Output "Invalid login, try again:"
    #$vsphereCredential = get-credential -Credential $null
    Connect-VIServer -Server $vSphere -Credential $privilegedCredential
}
catch
{
    Write-Output "Unhandled exception error. Exiting."
}

$ErrorActionPreference = "silentlycontinue"
Write-Output "Login success..."


################################################################################
#   Create AD Objects
################################################################################
Write-Output "`nWill create an AD Computer object with following parameters:`nObject Name: $($serverName)`nSAMAccountName: $($serverName)$`nDNS Name: $($serverFQDN)`nOU: $($selectedComputerOU)"
# New-ADComputer -path $selectedComputerOU -name $serverName -SAMAccountName "$($serverName)$" -DNSHostName $serverFQDN -Credential $privilegedCredential

Write-Output "`nWill create a new AD Group with the following parameters:`nGroup Name: $($serverName) - Server - Administrators`nOU: $($securityGroupsOU)`nMembers: $($systemAdministratorGroups)"
# New-ADGroup -Name "$($serverName) - admin group" -path $securityGroupsOU -ManagedBy $systemAdministratorGroups

#If Linux create SSSD group
if($serverType.tolower() -eq 'l')
{
    #New-ADGroup -Name "$($serverName) - user group" -path $securityGroupsOU -ManagedBy $systemUserGroups
}

Write-Output "`nWill create a new DNS record (and accompanying PTR Record) with the following parameters:`nName: $serverName`nDNS Server: $($dnsServer)`nForward Lookup Zone: $($dnsServer)`nIP: $IpAddress"
# Add-DnsServerResourceRecordA -Name $serverName -ComputerName $dnsServer" -ZoneName $dnsServer -IPv4Address $IpAddress -CreatePtr


################################################################################
#   Create VM
################################################################################

#clone vm OSCustomizationSpec
Get-OSCustomizationSpec -name $OSCustomizationSpec | New-OSCustomizationSpec -name temp -type nonpersistent
#set some settings
Get-OSCustomizationSpec -Name temp | Set-OSCustomizationSpec -NamingScheme "Fixed" -NamingPrefix $hostname
#Set networking information
Get-OSCustomizationSpec -Name temp | Get-OSCustomizationNicMapping | Set-OSCustomizationNicMapping -IpMode UseStaticIp -IpAddress $IpAddress -DefaultGateway $DefaultGateway -SubnetMask $SubnetMask

#Needs to be updates to be dynamic
$toClone = Get-Folder Templates | Get-Folder main | Get-Folder $linuxOSCustomizationSpec | get-template -Name $templateName

#Write-Output "`nWill create a VM in vCenter with following parameters:`nDatastore: $($datastore)`nTemplate: $($template)`nvCenter Server Name: $($vSphere)"
VMware.VimAutomation.Core\New-VM -Name $vcenterservername -Template $toClone -ResourcePool $ResourcePool -OSCustomizationSpec temp -Notes "" -Datastore $DatastoreDSC -DiskStorageFormat $DiskStorageFormat -Location $Location -NetworkName $NetworkName
Start-VM -VM $vcenterservername


################################################################################
#   Fin`
################################################################################
Get-OSCustomizationSpec -name temp | Remove-OSCustomizationSpec -Confirm:$false 
Write-Output "Loging Out"
Disconnect-viServer -server * -force -Confirm:$false