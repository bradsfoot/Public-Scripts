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
There is an option to enter "none" for the physical phone
A lot of this is specific to an environment so if you are going to try utilizing this you will need to go through and change some of the XML.
#>

###############################
##### Variables to Change #####
###############################

$CiscoUsername = "Username for the AXL API user in CUCM"
$Password = "Password for the AXK API user in CUCM"
$URI = "https://ServerFQDN:8443/axl/"
$TranscriptPath = "Place you want the logs to be saved if you want to keep them."

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

$Exists = $Null
$Phone = $Null

#Get user and check if they are valid
Do
{
   $Username = Read-Host "Enter the username to offboard"

   #Verify user exists
   If (Get-ADUser $Username)
   {
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
   }
   Else
   {
      $RoutePT = "4DIGIT_PT"
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
   }
   Catch
   {
      Write-Host "Unable to find DN. Number might need to be created in Superman."
      $Number = $False
   }
} until ($Number -eq $True)

#Get phone name
Do
{
   $PhoneName = Read-Host "Enter the name of the physical phone the user has. This appears as SEP### in CUCM. Enter 'none' if no phone exists"
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

#Review
Write-Host 
Write-Host "======================================="
Write-Host
(Get-ADUser $Username -Properties * | Format-List Name, SamAccountName, UserPrincipalName | Out-String).Trim()
Write-Host "Extension         : $Extension"
Write-Host "Phone             : $PhoneName"
Write-Host
Write-Host "======================================="
Read-Host "Continuing will make changes to the above phone and user. Press ENTER to continue."

########################
##### XML Requests #####
########################

#Convert user to Local User in CUCM
Write-Host "Converting user to a local user."
$ConvertToLocal = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/12.5">
   <soapenv:Header/>
   <soapenv:Body>
      <ns:updateUser>
         <userid>$Username</userid>
         <ldapDirectoryName></ldapDirectoryName>
      </ns:updateUser>
   </soapenv:Body>
</soapenv:Envelope>
"@
Send-APIRequest -XML $ConvertToLocal

#Delete User
Write-Host "Deleting local user."
$DeleteUser = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/12.5">
   <soapenv:Header/>
   <soapenv:Body>
      <ns:removeUser>
         <userid>$Username</userid>
      </ns:removeUser>
   </soapenv:Body>
</soapenv:Envelope>
"@
Send-APIRequest -XML $DeleteUser

#This loop searches for the three additional types of phone and deletes them if they are found. If they are not found then it will say it doesn't exist.
Write-Host "Deleting unneeded devices."
$Phones = "CSF$Username", "BOT$Username", "TCT$Username"
Foreach ($Phone in $Phones)
{
   Try
   {
      $RemovePhone = @"
      <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/12.5">
         <soapenv:Header/>
         <soapenv:Body>
            <ns:removePhone>
               <name>$Phone</name>
            </ns:removePhone>
         </soapenv:Body>
      </soapenv:Envelope>
"@

      Send-APIRequest -XML $RemovePhone -CatchBypass
   }
   Catch
   {
      Write-Host "$Phone does not exist"
   }
}

#Update phone line settings
Write-Host "Updating phone settings."
$UpdateLine = @"
<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/12.5">
   <soapenv:Header/>
   <soapenv:Body>
      <ns:updateLine>
         <pattern>$Extension</pattern>
         <description>Vacant</description>
         <alertingName>Vacant</alertingName>
         <asciiAlertingName>Vacant</asciiAlertingName>
      </ns:updateLine>
   </soapenv:Body>
</soapenv:Envelope>
"@
Send-APIRequest -XML $UpdateLine

#Update phone if needed
If ($PhoneName -ine "none")
{
   Write-Host "Updating Phone."
   $UpdatePhone = @"
   <soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" xmlns:ns="http://www.cisco.com/AXL/API/12.5">
      <soapenv:Header/>
      <soapenv:Body>
         <ns:updatePhone>
            <name>$PhoneName</name>
            <description>Vacant</description>
            <lines>
               <line>
                  <index>1</index>
                  <label>Vacant</label>
                  <display>Vacant</display>
                  <dirn>
                     <pattern>$Extension</pattern>
                     <routePartitionName>$RoutePT</routePartitionName>
                  </dirn>
                  <displayAscii>Vacant</displayAscii>
               </line>
            </lines>
            <ownerUserName></ownerUserName>
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

#Ending stuff
Stop-Transcript
Read-Host "Press ENTER to close."