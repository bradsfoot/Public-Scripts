<#
Written by Brad Egberts.
Free to use but give me the credit.


Cisco onboarding script for CUCM 12.5
Script will setup an existing phone and DN for a specific user and create a Jabber device.
Voicemails in CUC will need to be added manually.
This works by sending XML requests to the AXL API that is part of the CUCM server. An AXL API user will need to be created. 
For each of the requests the XML is stored into a variable then added to the function using the -XML parameter. The switch parameter is used to bypass the error catch for specific situations. 
You may need to use SOUPUI and the Cisco AXL Toolkit from your server to get the full XML that can be used in each request. 

*** NOTE ***
This script only works for existing phones and DN's in CUCM. You will need to manually add them if they are not already present.
There is an option to enter "none" for the physical phone for Jabber and VM only users.
A lot of this is specific to an environment so if you are going to try utilizing this you will need to go through and change some of the XML.
#>

###############################
##### Variables to Change #####
###############################

$CiscoUsername = "Username for the AXL API user in CUCM"
$Password = "Password for the AXK API user in CUCM"
$URI = "https://ServerFQDN:8443/axl/"
$TranscriptPath = "Place you want the logs to be saved if you want to keep them."
$LDAPName = "Name of LDAP in CUCM"

#####################
##### Functions #####
#####################

Function Send-APIRequest
{
   Param (
      [String] $XML,
      [Switch] $CatchBypass
   )

   #Credentials
   $CiscoPassword = ConvertTo-SecureString $Password -AsPlainText -Force
   $Credentials = New-Object System.Management.Automation.PSCredential $CiscoUsername, $CiscoPassword

   #Other info
   $Headers = @{
      SoapAction = "CUCM:DB ver=12.5";
      Accept     = "Accept: text/*";
   }

   #Send the request. If the $CatchBypass parameter is present then it removes the try/catch.
   If ($CatchBypass.IsPresent)
   {
      $Response = Invoke-WebRequest -ContentType "text/xml;charset=UTF-8" -Headers $Headers -Body $XML -Uri $URI -Method Post -Credential $Credentials
   }
   Else
   {
      Try
      {
         $Response = Invoke-WebRequest -ContentType "text/xml;charset=UTF-8" -Headers $Headers -Body $XML -Uri $URI -Method Post -Credential $Credentials
         If ($Response.StatusCode -eq "200")
         {
            #Do nothing. This is only here to remove any unneeded info from the console.
         }
      }
      Catch
      {
         Write-Host "---An error occurred---" -ForegroundColor:Red
         Write-Host $_.ErrorDetails.Message -ForegroundColor:Red
         Pause
      }
   }
}

##############################
##### Gather Information #####
##############################

#Start log
Start-Transcript -Path $TranscriptPath -Append

$RoutePT = $Null
$ShortExtension = $Null
$Exists = $Null
$Number = $Null
$Phone = $Null
$DP = $Null


#Get information about user.
Do
{
   $Username = Read-Host "Enter the username of the new phone user"

   #Verify user exists in AD and get make a full name
   If ($(Get-ADUser -Filter { SamAccountName -eq $Username }))
   {
      #Get users AD properties
      $User = Get-ADUser $Username
      $FirstName = $User.GivenName
      $LastName = $User.Surname
      $FullName = "$FirstName $LastName"

      $Exists = $True
   }
   Else
   {
      Write-Host "User doesn't exist. Please try again."
      $Exists = $False
   }

} Until ($Exists -eq $True)

#Get $Extension and determine route partition
Do
{
   $Extension = Read-Host "Enter an extension. If user has a 10 digit DN enter the full number including the \+."
   $Extension = $Extension.Trim()

   If ($Extension.Length -gt 4)
   {
      $RoutePT = "Global-ALL_PT"

      #Get the last 4 digits for the label
      $ShortExtension = $Extension.Substring($Extension.Length - 4)
   }
   Else
   {
      $RoutePT = "4DIGIT_PT"
      $ShortExtension = $Extension
   }

   #Verify extension
   Try
   {
      $GetLine = @"
        <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/12.5">
            <soapenv:Header/>
            <soapenv:Body>
                <ns:getLine>
                    <pattern>$Extension</pattern>
                    <routePartitionName>$RoutePT</routePartitionName>
                </ns:getLine>
            </soapenv:Body>
        </soapenv:Envelope>
"@
      Send-APIRequest -XML $GetLine -CatchBypass
      $Number = $True

      $Label = "$FullName - $ShortExtension"
   }
   Catch
   {
      Write-Host "Unable to find DN."
      $Number = $False
   }
} until ($Number -eq $True)

#Get phone name
Do
{
   $PhoneName = Read-Host "Enter the name of the physical phone the user will have. This appears as SEP### in CUCM. Enter 'none' if no phone is needed"
   $PhoneName = $PhoneName.Trim()

   If ($PhoneName -eq "none")
   {
      $Phone = $True
   }
   Else
   {
      Try
      {
         #Check if phone is valid
         $GetPhone = @"
            <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/12.5">
                <soapenv:Header/>
                <soapenv:Body>
                    <ns:getPhone>
                        <name>$PhoneName</name>
                    </ns:getPhone>
                </soapenv:Body>
            </soapenv:Envelope>
"@
         Send-APIRequest -XML $GetPhone -CatchBypass
         $Phone = $True
      }
      Catch
      {
         Write-Host "Phone is invalid. Try again."
         $Phone = $False
      }
   }
} Until ($Phone -eq $True)

#Get Device Pool
Do
{
   $DevicePool = Read-Host "Enter the Device Pool of phone. If no physical phone is needed this is still used to make a jabber phone."
   $DevicePool = $DevicePool.Trim()

   Try 
   {
      #Check if device pool is valid
      $Request = @"
        <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/12.5">
            <soapenv:Header/>
            <soapenv:Body>
                <ns:getDevicePool>
                    <name>$DevicePool</name>
                </ns:getDevicePool>
            </soapenv:Body>
        </soapenv:Envelope>
"@
      Send-APIRequest -XML $Request -CatchBypass
      $DP = $True
   }
   Catch 
   {
      Write-Host "Device Pool is invalid. Try again."
      $DP = $False
   }
} Until ($DP -eq $True)

#Review
Write-Host 
Write-Host "======================================="
Write-Host
(Get-ADUser $Username -Properties * | Format-List Name, SamAccountName, UserPrincipalName | Out-String).Trim()
Write-Host "Extension         : $Extension"
Write-Host "Phone             : $PhoneName"
Write-Host "Device Pool       : $DevicePool"
Write-Host "Phone Label       : $Label"
Write-Host
Write-Host "======================================="
Read-Host "Continuing will make changes to the above phone and user. Press ENTER to continue."

########################
##### XML Requests #####
########################

#Initiate LDAP Sync.
Write-Host "Forcing LDAP sync on Superman. Please wait."
$LDAPSync = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/12.5">
    <soapenv:Header/>
    <soapenv:Body>
        <ns:doLdapSync>
            <name>$LDAPName</name>
            <sync>true</sync>
        </ns:doLdapSync>
    </soapenv:Body>
</soapenv:Envelope>
"@
Send-APIRequest -XML $LDAPSync
Start-Sleep -Seconds 12       #In my envirnment the 12 seconds is sometimes not long enough. If you get errors saying that the user isn't found increase this.

#Update directory number
Write-Host "Updating directory number."
$UpdateLine = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/12.5">
   <soapenv:Header/>
   <soapenv:Body>
      <ns:updateLine>
         <pattern>$Extension</pattern>
         <routePartitionName>$RoutePT</routePartitionName>
         <description>$FullName</description>
         <callForwardBusy>
            <forwardToVoiceMail>true</forwardToVoiceMail>
            <callingSearchSpaceName>Voicemail_CSS</callingSearchSpaceName>
         </callForwardBusy>
         <callForwardBusyInt>
            <forwardToVoiceMail>true</forwardToVoiceMail>
            <callingSearchSpaceName>Voicemail_CSS</callingSearchSpaceName>
         </callForwardBusyInt>
         <callForwardNoAnswer>
            <forwardToVoiceMail>true</forwardToVoiceMail>
            <callingSearchSpaceName>Voicemail_CSS</callingSearchSpaceName>
         </callForwardNoAnswer>
         <callForwardNoAnswerInt>
            <forwardToVoiceMail>true</forwardToVoiceMail>
            <callingSearchSpaceName>Voicemail_CSS</callingSearchSpaceName>
         </callForwardNoAnswerInt>
         <callForwardNoCoverage>
            <forwardToVoiceMail>true</forwardToVoiceMail>
            <callingSearchSpaceName>Voicemail_CSS</callingSearchSpaceName>
         </callForwardNoCoverage>
         <callForwardNoCoverageInt>
            <forwardToVoiceMail>true</forwardToVoiceMail>
            <callingSearchSpaceName>Voicemail_CSS</callingSearchSpaceName>
         </callForwardNoCoverageInt>
         <callForwardOnFailure>
            <forwardToVoiceMail>true</forwardToVoiceMail>
            <callingSearchSpaceName>Voicemail_CSS</callingSearchSpaceName>
         </callForwardOnFailure>
         <callForwardNotRegistered>
            <forwardToVoiceMail>true</forwardToVoiceMail>
            <callingSearchSpaceName>Voicemail_CSS</callingSearchSpaceName>
         </callForwardNotRegistered>
         <callForwardNotRegisteredInt>
            <forwardToVoiceMail>true</forwardToVoiceMail>
            <callingSearchSpaceName>Voicemail_CSS</callingSearchSpaceName>
         </callForwardNotRegisteredInt>
         <alertingName>$FullName</alertingName>
         <asciiAlertingName>$FullName</asciiAlertingName>
         <voiceMailProfileName>Voicemail</voiceMailProfileName>
      </ns:updateLine>
   </soapenv:Body>
</soapenv:Envelope>
"@
Send-APIRequest -XML $UpdateLine

#Create Jabber device
Write-Host "Creating Jabber device"
$CreateJabber = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/12.5">
   <soapenv:Header/>
   <soapenv:Body>
      <ns:addPhone>
         <phone>
            <name>CSF$Username</name>
            <description>$Fullname</description>
            <product>Cisco Unified Client Services Framework</product>
            <class>Phone</class>
            <protocol>SIP</protocol>
            <protocolSide>User</protocolSide>
            <callingSearchSpaceName>Device_CSS</callingSearchSpaceName>
            <devicePoolName>$DevicePool</devicePoolName>
            <locationName>Default</locationName>
            <ownerUserName>$Username</ownerUserName>
            <lines>
               <line>
                  <index>1</index>
                  <label>$Label</label>
                  <display>$Label</display>
                  <dirn>
                     <pattern>$Extension</pattern>
                     <routePartitionName>$RoutePT</routePartitionName>
                  </dirn>
                  <displayAscii>$Label</displayAscii>
                  <callInfoDisplay>
                     <callerName>true</callerName>
                     <callerNumber>true</callerNumber>
                     <redirectedNumber>true</redirectedNumber>
                     <dialedNumber>true</dialedNumber>
                  </callInfoDisplay>
                  <associatedEndusers>
                     <enduser>
                        <userId>$Username</userId>
                     </enduser>
                  </associatedEndusers>
               </line>
            </lines>
         </phone>
      </ns:addPhone>
   </soapenv:Body>
</soapenv:Envelope>
"@
Send-APIRequest -XML $CreateJabber

#Update physical phone if needed
If ($PhoneName -ine "None")
{
   Write-Host "Updating phone."
   $UpdatePhone = @"
   <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/12.5">
      <soapenv:Header/>
      <soapenv:Body>
         <ns:updatePhone>
            <name>$PhoneName</name>
            <description>$FullName</description>
            <lines>
               <line>
                  <index>1</index>
                  <label>$Label</label>
                  <display>$Label</display>
                  <dirn>
                     <pattern>$Extension</pattern>
                     <routePartitionName>$RoutePT</routePartitionName>
                  </dirn>
                  <displayAscii>$Label</displayAscii>
                  <callInfoDisplay>
                     <callerName>true</callerName>
                     <callerNumber>true</callerNumber>
                     <redirectedNumber>true</redirectedNumber>
                     <dialedNumber>true</dialedNumber>
                  </callInfoDisplay>
                  <associatedEndusers>
                     <enduser>
                        <userId>$Username</userId>
                     </enduser>
                  </associatedEndusers>
               </line>
            </lines>
            <ownerUserName>$Username</ownerUserName>
         </ns:updatePhone>
      </soapenv:Body>
   </soapenv:Envelope>
"@
   Send-APIRequest -XML $UpdatePhone

   #Apply phone settings
   Write-Host "Applying phone settings."
   $ApplyPhone = @"
   <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/12.5">
      <soapenv:Header/>
      <soapenv:Body>
         <ns:applyPhone>
            <name>$PhoneName</name>
         </ns:applyPhone>
      </soapenv:Body>
   </soapenv:Envelope>
"@
   Send-APIRequest -XML $ApplyPhone
}


#Update User. The XML changes depending on $PhoneName
Write-Host "Updating User."
If ($PhoneName -eq "none") 
{
   $UpdateUser = @"
   <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/12.5">
      <soapenv:Header/>
      <soapenv:Body>
         <ns:updateUser>
            <userid>$Username</userid>
            <associatedDevices>
               <device>CSF$Username</device>
            </associatedDevices>
            <primaryExtension>
               <pattern>$extension</pattern>
               <routePartitionName>$RoutePT</routePartitionName>
            </primaryExtension>
            <enableMobility>true</enableMobility>
            <homeCluster>true</homeCluster>
            <imAndPresenceEnable>true</imAndPresenceEnable>
         </ns:updateUser>
      </soapenv:Body>
   </soapenv:Envelope>
"@
}
Else
{
   $UpdateUser = @"
   <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/12.5">
      <soapenv:Header/>
      <soapenv:Body>
         <ns:updateUser>
            <userid>$Username</userid>
            <associatedDevices>
               <device>$PhoneName</device>
               <device>CSF$Username</device>
            </associatedDevices>
            <primaryExtension>
               <pattern>$extension</pattern>
               <routePartitionName>$RoutePT</routePartitionName>
            </primaryExtension>
            <enableMobility>true</enableMobility>
            <homeCluster>true</homeCluster>
            <imAndPresenceEnable>true</imAndPresenceEnable>
         </ns:updateUser>
      </soapenv:Body>
   </soapenv:Envelope>
"@
}
Send-APIRequest -XML $UpdateUser

#Ending stuff
Stop-Transcript
Read-Host "Press ENTER to close."