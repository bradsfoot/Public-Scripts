<#
Written by Brad Egberts.
Free to use but give me the credit.


Offboarding script to be used with my onboarding script. 
We disable the user, move their personal fileshare to an archive, then export all AD properties to a CSV for future reference.
Also give the option to share the mailbox with a specified person.

After we disable the user is moved into the disabled users OU and then add the ticket number and date in the description for reference. 
Licenses are removed automatically because we use group based licensing in Azure AD and remove the keyword.
#>

###############################
##### Variables to Change #####
###############################

$Password = "Default password you give to new user accounts."
$FileshareArchive = "Path to personal fileshare archive"
$Fileshare = "Path to personal fileshare"
$CSVpath = "Path to where you want the CSV to be saved. We save ours in the archived personal fileshare."
$SharedMailboxOU = "OU where you put shared mailboxes is you have one."
$DisabledUsersOU = "OU for disabled users"
$Domain = "@yourdomain.here"

# $Groups array is so we can add multiple groups we want the user to be removed from but not recorded in the CSV. 

#########################
##### Prerequisites #####
#########################

#Start log
Start-Transcript -Path $TranscriptPath -Append

#Import required modules
Import-Module ActiveDirectory

##############################
##### Gather Information #####
##############################

#Get needed variables and check is username is valid
Do
{
    $Username = Read-Host "Enter username of the person to offboard"
    $Username = $Username.Trim()
    If ($(Get-ADUser -Filter { SamAccountName -eq $Username }))
    {
        $Valid = $True
    }
    Else
    {
        $Valid = $False
        Write-Host "Username is invalid. Try again." -ForegroundColor:Yellow
    }
} Until ($Valid -eq $True)
$Inc = Read-Host "Enter ticket number"
$Inc = $Inc.Trim()

#Convert to shared mailbox prompt
$Convert = Read-Host "Does the mailbox need to be shared? [y/n]"
If ($Convert -eq "y")
{
    #Connect to Exchange online console to convert the mailbox later
    Write-Host "Please provide your login credentials. Use your full email." -ForegroundColor:Yellow
    $Credential = Get-Credential
    $ExchangeSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri https://outlook.office365.com/powershell-liveid/ -Credential $Credential -Authentication Basic -AllowRedirection
    Import-PSSession $ExchangeSession -DisableNameChecking | Out-Null

    If (Get-Mailbox $Username)
    {
        $MailboxDeligation = Read-Host "Enter the username of who will see the shared mailbox."
    }
    Else
    {
        Write-Host "User doesn't have a mailbox."
        $Convert = "No mailbox found."
    }
}

#Review
Write-Host
Write-Host "======================================="
Write-Host
(Get-ADUser $Username | Format-List Name, SamAccountName, UserPrincipalName | Out-String).Trim()
Write-Host "Incident          : $Inc"
Write-Host "Convert to shared : $Convert"
Write-Host "Mailbox Deligation: $MailboxDeligation"
Write-Host
Write-Host "======================================="
Read-Host "Continuing will make permanent changes to the above account. Press ENTER to continue."

########################
##### Disable User #####
########################

#Disable account
Write-Host "Disabling Account"
Disable-ADAccount $Username

#Reset password
Write-Host "Resetting password"
$Password = ConvertTo-SecureString -AsPlainText "$Password" -Force
Set-ADAccountPassword -Identity $Username -Reset -NewPassword $Password

#Check for fileshare. If not present then create the directory in the archive folder for the CSV to be stored. We user robocoby so that details of the transfer is saved in the log.
$FileshareCheck = Test-Path $Fileshare
If ($FileshareCheck -eq $True)
{
    Write-Host "Moving I drive." -ForegroundColor:Green
    New-Item -Path "$FileshareArchive" -Name "$Username" -ItemType "Directory" | Out-Null
    Robocopy.exe "$Fileshare" "$FileshareArchive\$Username" /move /s /r:1 /w:10
}
Else 
{
    Write-Host "Unable to find fileshare. You might want to check manually." -ForegroundColor:Yellow
    New-Item -Path "$FileshareArchive" -Name "$Username" -ItemType "Directory" | Out-Null
}

#Remove groups that we don't want being exported in the CSV and possibly copied to new users
$Groups = @(
    #Enter the groups you want to include here. Remove if you don't need this.
)
Foreach ($Group in $Groups)
{
    Remove-AdGroupMember -Identity $Group -Members $Username -Confirm:$False
}

#Get $Username AD attributes and export to CSV
Write-Host "Exporting $Username's AD attributes. File can be found in the users archived fileshare."
$User = Get-ADUser $Username -Properties *
$Data = [PSCustomObject]@{
    Title                = $User.Title
    Department           = $User.Department
    Description          = $User.Description
    Office               = $User.Office
    OFficePhone          = $User.OfficePhone
    IpPhone              = $User.IpPhone
    Fax                  = $User.Fax
    EmployeeNumber       = $User.EmployeeNumber
    StreetAddress        = $User.StreetAddress
    City                 = $User.City
    State                = $User.State
    PostalCode           = $User.PostalCode
    Company              = $User.Company
    extensionAttribute1  = $User.extensionAttribute1
    extensionAttribute2  = $User.extensionAttribute2
    extensionAttribute3  = $User.extensionAttribute3
    extensionAttribute4  = $User.extensionAttribute4
    extensionAttribute5  = $User.extensionAttribute5
    extensionAttribute6  = $User.extensionAttribute6
    extensionAttribute7  = $User.extensionAttribute7
    extensionAttribute8  = $User.extensionAttribute8
    extensionAttribute9  = $User.extensionAttribute9
    extensionAttribute10 = $User.extensionAttribute10
    extensionAttribute11 = $User.extensionAttribute11
    extensionAttribute12 = $User.extensionAttribute12
    extensionAttribute13 = $User.extensionAttribute13
    extensionAttribute14 = $User.extensionAttribute14
    extensionAttribute15 = $User.extensionAttribute15
    OU                   = ($User.DistinguishedName -Split ",", 3)[2]
    Memberof             = ((Get-ADPrincipalGroupMembership -Identity $Username | Where-Object { $_.Name -ine "Domain Users" } | Select-Object -ExpandProperty Name) -Join ',')
}
$Data | Export-Csv -Path $CSVpath -NoTypeInformation

#Clear out AD attributes
Write-Host "Clearing $Username's AD attributes."
$Attributes = @(
    "Title"
    "Department"
    "Description"
    "physicalDeliveryOfficeName"    #Office
    "StreetAddress"
    "L"                             #City
    "St"                            #State
    "PostalCode"
    "Company"
    "ipPhone"
    "telephoneNumber"
    "extensionAttribute1"
    "extensionAttribute2"
    "extensionAttribute3"
    "extensionAttribute4"
    "extensionAttribute5"
    "extensionAttribute6"
    "extensionAttribute7"
    "extensionAttribute8"
    "extensionAttribute9"
    "extensionAttribute10"
    "extensionAttribute11"
    "extensionAttribute12"
    "extensionAttribute13"
    "extensionAttribute14"
    "extensionAttribute15"
)
ForEach ($A in $Attributes)
{
    Set-ADuser -Identity $Username -Clear $A
}

#Add date/incident into description field
$Date = Get-Date -Format "MM/dd/yyyy"
Set-ADUser -Identity $Username -Description "Disabled $Date per $Inc"

#Remove from groups.
Write-Host "Removing from AD Groups"
Get-AdPrincipalGroupMembership -Identity $Username | Where-Object -Property Name -NE -Value 'Domain Users' | Remove-AdGroupMember -Members $Username -Confirm:$False

#Move to correct OU
If ($Convert -eq "y")
{
    #Move user to Shared Mailbox OU
    Write-Host "Moving to Shared Mailbox OU"
    Get-ADUser "$Username" | Move-ADObject -TargetPath $SharedMailboxOU
}
Else 
{
    #Move user to Disabled Users OU
    Write-Host "Moving to Disabled OU"
    Get-ADUser "$Username" | Move-ADObject -TargetPath $DisabledUsersOU
}

#Convert mailbox to shared.
If ($Convert -eq "y")
{
    $Email = "$Username + $Domain"

    #Re-add to O365 AD Sync Group (My org used group based Azure AD syncing)
    Get-ADUser $Username | Add-ADPrincipalGroupMembership -MemberOf "O365 AD Sync"

    #Convert to shared
    Set-Mailbox -Identity "$Email" -Type:Shared
    Write-Host "Mailbox has been converted."

    #Set Deligation if provided.
    If (![string]::IsNullOrWhiteSpace($MailboxDeligation))
    {
        Add-MailboxPermission -Identity "$Email" -User $MailboxDeligation -AccessRights FullAccess -InheritanceType All
        Write-Host "$MailboxDeligation now has rights to $Email."
    }
}

#End session and end script
If ($ExchangeSession -eq $True)
{
    Remove-PSSession $ExchangeSession
}
Write-Host "Script finished."
Stop-Transcript
Read-Host "Press ENTER to close."