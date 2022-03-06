<#
Written by Brad Egberts.
Free to use but give me the credit.


Onboarding script for Exchange Hybrid environment. Script is based on the New-RemoteMailbox cmdlet which will create a user in on-prem Exchange which adds it to AD and enables the remote mailbox.
Special thanks to u/jimb2 on Reddit for the function to cycle through all the $CopiedUsers AD properties. Without it, the original script would error each time it copied a blank field from $CopiedUser.
Microsoft licenses are applied by adding a key word into extensionAttribute1 which is used in a dynamic license group in Azure AD. In order for the license to be removed or changed, extensionAttribute1 must be cleared in AD.

*** IMPORTANT NOTES ***
In my organization we remove all attributes, groups, ect from users when we disable them. We export that info to a CSV that we then save to an archive of their personal fileshare.
Because of this if the $CopiedUser is disabled we need to find the attributes.csv. 

In the Attribute Updates section, the IF statements are written in a way to be all inclusive to what type of copied user is being used is why I have the functions and call them in each instead of just running the code outside the statements once.

# $Groups array is so we can add multiple groups we want the user to be removed from but not recorded in the CSV.
#>

###############################
##### Variables to Change #####
###############################

$TranscriptPath = "Place you want the logs to be saved if you want to keep them."
$ExchangeServerURI = "The URI used to connect to Exchange."
$Domain = "Your email domain."
$CSVpath = "Path to the $CopiedUsers archived personal fileshare."
$Password = "Default password you give to new user accounts."
$LicenseKeyWord = "Key word used for the dynamic license group in Azure AD."
$Fileshare = "Location of users personal fileshare is going to be."

#####################
##### Functions #####
#####################

#Function gets all properties from the CopiedUser and then loops through them basically checking for empty values. This prevents errors when adding them.
Function Add-Attributes
{
    Write-Host "Adding AD Attributes"
    $PropertyString = 'Title,Department,physicalDeliveryOfficeName,Description,StreetAddress,L,St,PostalCode,Company,extensionAttribute2,extensionAttribute3,extensionAttribute4,extensionAttribute5,extensionAttribute6,extensionAttribute7,extensionAttribute8,extensionAttribute9,extensionAttribute10,extensionAttribute11,extensionAttribute12,extensionAttribute13,extensionAttribute14,extensionAttribute15'
    $Props = $PropertyString.Split(',')
    $Source = Get-ADUser -Identity $CopiedUser -Property $Props
    $Add = @{}
    $Ignore = @()
    Foreach ($P in $Props)
    {
        If ($Source.$P)
        {
            #Property exists
            $Add.$P = $Source.$P
        }
        Else
        {
            #Property does not exist
            $Ignore += $P
        }
    }
    Set-AdUser -Identity $Username -Replace $Add
    Set-ADUser -Identity $Username -Country "US"
    Start-Sleep 2
}

#Compares title of copied user to one entered at the start. If it's different, the title entered at the start replaces the copied one.
Function Compare-Title
{
    If (![string]::IsNullOrWhiteSpace($Title))
    {
        $CopiedTitle = Get-ADUser -Identity $Username -Property Title
        If ($Title -ine $CopiedTitle) 
        {
            Set-ADUser -Identity $Username -Replace @{title = "$Title" }
        }
    }
}

#Set Phone number
Function Set-PhoneNumber
{
    If (![string]::IsNullOrWhiteSpace($Extension))
    {
        Set-ADuser -Identity $Username -Replace @{ipPhone = $Extension; telephoneNumber = $Extension }
    }
}

#Add to groups
Function Add-Groups
{
    Write-Host "Adding to groups"
    Foreach ($Group in $MemberOf)
    {
        Try
        {
            $GroupName = Get-ADGroup $Group | Select-Object -ExpandProperty DistinguishedName
            Get-ADUser $Username | Add-ADPrincipalGroupMembership -MemberOf $GroupName
        }
        Catch
        {
            Write-Host "Unable to find $Group. You may need to search AD and add them manually." -ForegroundColor:Yellow
        }
    }
}

#########################
##### Prerequisites #####
#########################

#Start log
Start-Transcript -Path $TranscriptPath -Append

#Connect to Exchange Server.
$UserCredential = Get-Credential
$ExchangeSession = New-PSSession -ConfigurationName Microsoft.Exchange -ConnectionUri $ExchangeServerURI -Authentication Kerberos -Credential $UserCredential

#Import required modules. DisableNameChecking and Out-Null remove the warning and output for the module.
Write-Output "Importing Required Modules..."
Import-PSSession $ExchangeSession -AllowClobber -DisableNameChecking | Out-Null
Import-Module ActiveDirectory
Write-Host

#######################################
##### Gather New User Information #####
#######################################

#Gather new user information including if a license is needed.
$FirstName = Read-Host "Enter the First Name"
$FirstName = $FirstName.Trim()
$PreferredName = Read-Host "Enter a Preferred name if provided"
$PreferredName = $PreferredName.Trim()
$MiddleInitial = Read-Host "Enter the Middle Initial"
$MiddleInitial = $MiddleInitial.Trim()
$LastName = Read-Host "Enter the Last Name"
$LastName = $LastName.Trim()
$Title = Read-Host "Enter the users Title"
$Title = $Title.Trim()
$Extension = Read-Host "Enter the users Extension"
$Extension = $Extension.Trim()
$License = Read-Host "Does the user need a 365 license? [y/n]"
$License = $License.Trim()
$CopiedUser = Read-Host "Enter a username to copy"
$CopiedUser = $CopiedUser.Trim()
$Welcome = Read-Host "Do you want to send a welcome email? [y/n]"

#Sets full name depending on if a preferred name is given
If (![string]::IsNullOrWhiteSpace($PreferredName)) 
{
    $FullName = "$LastName, $PreferredName"
}
Else 
{
    $FullName = "$LastName, $FirstName"
}

#Create Username using first initial of first name and last name
$FirstInitial = $FirstName.Substring(0, 1)
$Username = $FirstInitial + $LastName -Replace '[\W]', ''   #The -Replace removes all special character.
$I = 1
Do
{
    #Check if username exists
    Write-Host "Checking if username already exists..." -ForegroundColor:Green

    If ($(Get-ADUser -Filter { SamAccountName -eq $Username }))
    {
        Write-Host "WARNING: Logon name $Username already exists!!" -ForegroundColor:Yellow
        
        #If middle name is not provided, use additional letters of the first name until a valid username is found.
        If ([string]::IsNullOrWhiteSpace($MiddleInitial))
        {
            $Taken = $True
            $I++
            $Username = $FirstName.substring(0, $I) + $LastName
        }
        Else 
        {
            $Taken = $True
            $Username = $FirstName.substring(0, 1) + $MiddleInitial + $LastName
        }
        $Email = $Username + $Domain 
        Write-Host "Changing Logon name to" $Username -ForegroundColor:Yellow
    } 
    Else
    {
        $Taken = $False
        Write-Host "No duplicates found." -ForegroundColor:Green
    }
    $Username = $Username.ToLower()
} Until ($Taken -eq $False)

#Trim for max length
If ($Username.Length -gt 12)
{
    $Username = $Username.Substring(0, 12)
}

#Create email
$Email = $Username + $Domain

#Check for $CopiedUser
Do
{
    Write-Host "Checking if $CopiedUser is a valid user..." -ForegroundColor:Green

    If ($(Get-ADUser -Filter { SamAccountName -eq $CopiedUser }))
    {
        Write-Host "$CopiedUser is valid" -ForegroundColor:Green
    }
    Else
    {
        Write-Host "Username doesn't exist." -ForegroundColor:Red
        $CopiedUser = Read-Host "Enter a username to copy"
    }
} Until ($(Get-ADUser -Filter { SamAccountName -eq $CopiedUser }))

#Variable review
Write-Host
Write-Host "======================================="
Write-Host
Write-Host "First name:      $FirstName"
Write-Host "Preferred Name:  $PreferredName"
Write-Host "Middle Initial:  $MiddleInitial"
Write-Host "Last name:       $LastName"
Write-Host "Display name:    $FullName"
Write-Host "Username:        $Username"
Write-Host "Title:           $Title"
Write-Host "Phone Number:    $Extension"
Write-Host "Email:           $Email"
Write-Host "License:         $License"
Write-Host "Copied User:     $CopiedUser"
Write-Host "Welcome Email:   $Welcome"
Write-Host
Write-Host "======================================="
Read-Host "If this is correct, press ENTER. Continuing will start creating the user. Press CTRL + C to cancel."

################################
##### Classify $CopiedUser #####
################################

#Checks to see if User is disabled or not.
If ($(Get-ADUser $CopiedUser).enabled -eq $False)
{
    $CopiedUserArchived = $True
}
Else
{
    $CopiedUserArchived = $False
}

############################
##### Account Creation #####
############################

#Create account using basic attributes
Write-Host "Creating mailboxes, user and setting OU."
$Password = ConvertTo-SecureString $Password -AsPlainText -Force
$UserAttributes = @{
    Name                     = "$FullName"
    FirstName                = $FirstName
    LastName                 = $LastName
    DisplayName              = $FullName
    Initials                 = $MiddleInitial
    UserPrincipalName        = $Email
    Password                 = $Password
    resetpasswordonnextlogon = $true
}
New-RemoteMailbox @UserAttributes | Format-Table -Property DisplayName, PrimarySmtpAddress, SamAccountName

#Check for user in AD before trying to make changes. Wait if not found.
Do 
{
    If ($(Get-ADUser -Filter { SamAccountName -eq $Username }))
    {
        $Sync = $True
    }
    Else
    {
        $Sync = $False
        Start-Sleep 2
    }
} Until ($Sync -eq $True)

#############################
##### Attribute Updates #####
#############################

Write-Host "Making changes in AD."

#CopiedUser is disabled. All AD attributes are then pulled from a CSV created when the user is disabled
If ($CopiedUserArchived -eq $True)
{
    #Sanity check for easy troubleshooting.
    Write-Host "Copying from CSV" -ForegroundColor:Green

    #Import CSV and get all the values.
    $Datasheet = Import-Csv $CSVpath | Where-Object { $_.PSObject.Properties.Value -ne $null }
    ForEach ($User in $Datasheet)
    {
        $CopiedTitle = $User.Title
        $Department = $User.Department
        $Description = $User.Description
        $Office = $User.Office
        $StreetAddress = $User.StreetAddress
        $City = $User.City
        $State = $User.State
        $PostalCode = $User.PostalCode
        $Company = $User.Company
        $EA2 = $User.extensionAttribute2
        $EA3 = $User.extensionAttribute3
        $EA4 = $User.extensionAttribute4
        $EA5 = $User.extensionAttribute5
        $EA6 = $User.extensionAttribute6
        $EA7 = $User.extensionAttribute7
        $EA8 = $User.extensionAttribute8
        $EA9 = $User.extensionAttribute9
        $EA10 = $User.extensionAttribute10
        $EA11 = $User.extensionAttribute11
        $EA12 = $User.extensionAttribute12
        $EA13 = $User.extensionAttribute13
        $EA14 = $User.extensionAttribute14
        $EA15 = $User.extensionAttribute15
        $OU = $User.OU
        $MemberOf = ($User.Memberof -Split ",")
    }

    #IF statements only make changes is the CSV fields are not empty. This eliminates the errors that happen whenever you try adding $Null to AD. I don't honestly know how else to do this.
    If (![string]::IsNullOrWhiteSpace($CopiedTitle)) { Set-ADUser $Username -Title $CopiedTitle }
    If (![string]::IsNullOrWhiteSpace($Department)) { Set-ADUser $Username -Department $Department }
    If (![string]::IsNullOrWhiteSpace($Description)) { Set-ADUser $Username -Description $Description }
    If (![string]::IsNullOrWhiteSpace($Office)) { Set-ADUser $Username -Office $Office }
    If (![string]::IsNullOrWhiteSpace($StreetAddress)) { Set-ADUser $Username -StreetAddress $StreetAddress }
    If (![string]::IsNullOrWhiteSpace($City)) { Set-ADUser $Username -City $City }
    If (![string]::IsNullOrWhiteSpace($State)) { Set-ADUser $Username -State $State }
    If (![string]::IsNullOrWhiteSpace($PostalCode)) { Set-ADUser $Username -PostalCode $PostalCode }
    If (![string]::IsNullOrWhiteSpace($Company)) { Set-ADUser $Username -Company $Company }
    If (![string]::IsNullOrWhiteSpace($EA2)) { Set-ADUser $Username -Replace @{extensionAttribute2 = $EA2 } }
    If (![string]::IsNullOrWhiteSpace($EA3)) { Set-ADUser $Username -Replace @{extensionAttribute3 = $EA3 } }
    If (![string]::IsNullOrWhiteSpace($EA4)) { Set-ADUser $Username -Replace @{extensionAttribute4 = $EA4 } }
    If (![string]::IsNullOrWhiteSpace($EA5)) { Set-ADUser $Username -Replace @{extensionAttribute5 = $EA5 } }
    If (![string]::IsNullOrWhiteSpace($EA6)) { Set-ADUser $Username -Replace @{extensionAttribute6 = $EA6 } }
    If (![string]::IsNullOrWhiteSpace($EA7)) { Set-ADUser $Username -Replace @{extensionAttribute7 = $EA7 } }
    If (![string]::IsNullOrWhiteSpace($EA8)) { Set-ADUser $Username -Replace @{extensionAttribute8 = $EA8 } }
    If (![string]::IsNullOrWhiteSpace($EA9)) { Set-ADUser $Username -Replace @{extensionAttribute9 = $EA9 } }
    If (![string]::IsNullOrWhiteSpace($EA10)) { Set-ADUser $Username -Replace @{extensionAttribute10 = $EA10 } }
    If (![string]::IsNullOrWhiteSpace($EA11)) { Set-ADUser $Username -Replace @{extensionAttribute11 = $EA11 } }
    If (![string]::IsNullOrWhiteSpace($EA12)) { Set-ADUser $Username -Replace @{extensionAttribute12 = $EA12 } }
    If (![string]::IsNullOrWhiteSpace($EA13)) { Set-ADUser $Username -Replace @{extensionAttribute13 = $EA13 } }
    If (![string]::IsNullOrWhiteSpace($EA14)) { Set-ADUser $Username -Replace @{extensionAttribute14 = $EA14 } }
    If (![string]::IsNullOrWhiteSpace($EA15)) { Set-ADUser $Username -Replace @{extensionAttribute15 = $EA15 } }

    #Set Country
    Set-ADUser -Identity $Username -Country "US"

    #Set phone number
    Set-PhoneNumber
    
    #Confirm title is correct
    Compare-Title

    #Add to groups
    Add-Groups

    #Move to OU
    Write-Host "Moving to OU"
    Get-ADUser $Username | Move-ADObject -TargetPath $OU
}

#CopiedUser is currently enabled. Straight copy from one user to another.
If ($CopiedUserArchived -eq $False)
{
    #Sanity check for easy troubleshooting.
    Write-Host "Copy from enabled user" -ForegroundColor:Green

    #Add attributes with function
    Add-Attributes

    #Set phone number
    Set-PhoneNumber

    #Confirm title is correct
    Compare-Title

    #Add to groups
    $MemberOf = Get-ADPrincipalGroupMembership $CopiedUser | Where-Object { $_.Name -ine "Domain Users" }
    Add-Groups

    #Remove groups that shouldn't be copied over
    $Groups = @(
        #Add a list of groups that shouldn't be copied over to the new users. My org keeps a list of groups that can only be added by a directors explicit orders. 
    )
    Foreach ($Group in $Groups)
    {
        Remove-AdGroupMember -Identity $Group -Members $Username -Confirm:$False
    }

    #Move to OU
    Write-Host "Moving to OU"
    $CopiedUserOU = Get-ADUser $CopiedUser -Properties CanonicalName
    $OU = ($CopiedUserOU.DistinguishedName -Split ",", 3)[2]
    Get-ADUser $Username | Move-ADObject -TargetPath $OU
}

#############################
##### Finishing Touches #####
#############################

#Add keyword for license if needed
If ($License -eq 'y')
{
    Set-ADUser $Username -Add @{extensionAttribute1 = "$LicenseKeyWord" }
    Write-Host "Microsoft 365 licenses will be applied after the next AD sync."
}

#Create personal fileshare. Out-Null hides the output of new-item.
Write-Host "Creating personal fileshare."
New-Item -Path $Fileshare -Name "$Username" -ItemType "Directory" | Out-Null
Start-Sleep -Seconds 2
$ACL = Get-Acl -Path "$Fileshare\$Username"
$AccessRule = New-Object System.Security.AccessControl.FileSystemAccessRule("$Username", "FullControl", "ContainerInherit,ObjectInherit", "None", "Allow")
$ACL.SetAccessRule($AccessRule)
$ACL | Set-Acl -Path "$Fileshare\$Username"

#Email info to requester
If ($Welcome -eq "y")
{
    #Generate $Phone info if provided
    If (![string]::IsNullOrWhiteSpace($Extension))
    {
        $Phone = "Extension: $Extension<br> Voicemail PIN: 1234"
    }

    #Get requester username
    $Requester = Read-Host "Enter the username of the requester"
    $Requester = $Requester.Trim()
    $From = "Helpdesk@yourdomain.here <Helpdesk>"
    $To = "$Requester + $Domain"
    $Subject = "New User account - $FullName"
    $Body = "
    <html>
        <body>
            <p>A user account has been created as requested for:</p>
            <p>Name: $FullName<br>
            User ID: $Username<br>
            Password: <strong>$Password</strong><br>
            Email Address: $Email<br>
            $Phone</p>
            <p>Body text that can be changed to fit what you need</p>
        </body>
    </html>"

    #Send email
    Write-Host "Sending email."
    Send-MailMessage -To $To -From $From -Subject $Subject -Body $Body -BodyAsHtml -SmtpServer $ExchangeServer
}

#End session
Remove-PSSession $ExchangeSession
Write-Host "Exchange session ended."
Write-Host "Script finished."
Stop-Transcript
Read-Host "Press ENTER to close."