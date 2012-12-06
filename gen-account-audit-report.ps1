<#   
    .SYNOPSIS   
        Check expiry dates of SecureTransport user account passwords
    .DESCRIPTION   
        
        
    .PARAMETER  
        -SkipUserNotification
			Specifying this switch will prevent the script from notifying users if their password is expiring soon. This is useful if the script is run on an ad-hoc basis and you do not wish to notify the users because the script already runs a a scheduled task.
		
    .EXAMPLE   
        
		
    .NOTES  
        File Name  : gen-account-audit-report.ps1 
        Author     : Vijay Thakorlal
        Requires   : PowerShell V2
        To Do      : Use read-secure string to store credentials in a file
		
        IMPORTANT NOTES
			1. You must change the password to the mysql database password set during installation of SecureTransport
        
#>   

[CmdletBinding()]
param([Switch]$SkipUserNotification)

############################
# BEGIN VARIABLE DEFINITIONS
############################

# Get the hostname
$servername = $env:COMPUTERNAME
# Modify this variable to match your environment
$InternalSTServer = "GBNTHDA3534SRV"

# MySQL Connection String
$MySQLServer = "localhost"
$MySQLPort = "33060"
$MySQLUser = "root"
$MySQLPassword = "tumbleweed"
$MySQLDatbase = "st"
$connString = "Server=$MySQLServer;port=$MySQLPort;Uid=$MySQLUser;Pwd=$MySQLPassword;database=$MySQLDatbase;"

# Threshold in days based on which to report on expiring passwords / accounts
# E.g. report on accounts that are due to expire in 14 days or less
$passwd_expiry_threshold = 14
$unusedThreshold = 30
$NoPasswordExpirySetAccountsHash = @()
$UnusedUserAccountsHash = @()
$DisabledUserAccountsHash = @()
$NoLoginInXDaysAccountsHash = @()
$ExpUserPassHash = @()
$AdminAccStatus = @()

# Administrative account expiry threshold is stored in a configuration file
$FILEDRIVECONF="C:\Program Files\Tumbleweed\SecureTransport\STServer\conf\filedrive.conf"

# HTML Report File Location
$ReportPath = "C:\scripts\"
$ReportFile = Join-Path $ReportPath  "securetransport-accounts-report.html"

###########################
# END VARIABLE DEFINITIONS
###########################


############################
# BEGIN FUNCTION DEFINITIONS
############################

Function get-AdminPassConfig()
{
    $content = Get-Content -Path (Resolve-Path $FILEDRIVECONF) -Delimiter "\n"
	if ( $content -match "(.*)admin\-password\-expiration\s\d+" )
	{
		# We have to use substring here because there appear to be weired control characters before the digits
		# that are not spaces
		$expValue = ( [string]($matches[0] -split  "admin\-password\-expiration\s+")).subString(1)
		return $expValue
	}
	return $null
} # END FUNCTION  get-AdminPassConfig

[string] $admin_password_expiry = get-AdminPassConfig

Function Run-MySQLQuery 
{

    Param(
        [Parameter(
            Mandatory = $true,
            ParameterSetName = '',
            ValueFromPipeline = $true)]
            [string]$query,   
        [Parameter(
            Mandatory = $true,
            ParameterSetName = '',
            ValueFromPipeline = $true)]
            [string]$connectionString
        )
    Begin 
    {
        Write-Debug "Starting Begin Section"     
    }
    Process 
    {
        Write-Debug "Starting Process Section"
        try 
        {
            # load MySQL driver and create connection
            Write-Debug "Create Database Connection"
            # You could also could use a direct Link to the DLL File the path assumes x86 system and the system has 
            # a version of .NET framework lower than 4.0 if the system is running .NET Framework 4.0 repalce v2.0 with v4.0 in the path
            # $mySQLDataDLL = "C:\Program Files\MySQL\MySQL Connector Net 6.5.4\Assemblies\v2.0\MySql.Data.dll"
            # For x64 use
            # $mySQLDataDLL = "C:\Program Files (x86)\MySQL\MySQL Connector Net 6.5.4\Assemblies\v2.0\MySql.Data.dll"
            # [void][system.reflection.Assembly]::LoadFrom($mySQLDataDLL)
            [void][System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")
            $connection = New-Object MySql.Data.MySqlClient.MySqlConnection
            $connection.ConnectionString = $ConnectionString
            Write-Debug "Open Database Connection"
            $connection.Open()
             
            # Run MySQL Query
            Write-Debug "Run MySQL Query $query"
            $command = New-Object MySql.Data.MySqlClient.MySqlCommand($query, $connection)
            $dataAdapter = New-Object MySql.Data.MySqlClient.MySqlDataAdapter($command)
            $dataSet = New-Object System.Data.DataSet
            $dataAdapter.Fill($DataSet) | Out-Null
            return $DataSet.Tables[0]
            #$recordCount = $dataAdapter.Fill($dataSet, "data") | Out-Null
            #return $dataSet.Tables["data"] | Format-Table

        }       
        catch 
        {
            #Write-Output "Could not run MySQL Query ( $query )" $Error[0]
			Write-Host "Could not run MySQL Query" $Error[0]    
        }   
        Finally 
        {
            Write-Debug "Close Connection"
            $connection.Close()
        }
    }
    End 
    {
        Write-Debug "Starting End Section"
    }
} # END FUNCTION Run-MySQLQuery


function is-null($value)
{
  return  [System.DBNull]::Value.Equals($value)
} # END FUNCTION is-null

# Sends email notification to a user whose password is due to expire
function notify-User ($object)
{
	$UserName = $object.("Name")
	$daysToExpiry =  $object.("Days to Password Expiry")
	$mailMessage = "This is a notification from SecureTransport. Your password (for the account $UserName) is due to expire in $daysToExpiry days or less. Please change your password at your earliest convenience."
	$mailSubject = "SecureTransport: Password Expiry Notification"
	$mailTo = $object.("Email")
	$mailFrom = "securetransport@acme.com"	
	$SMTPServer = "192.168.0.1"
	
	$htmlEmail = @"
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
    "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">

	<html xmlns="http://www.w3.org/1999/xhtml">
		<!-- Created on: 05/06/2005 -->
		<head>
			<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
			<title></title>
			<style type="text/css">
				* {margin: 0; padding: 0;}
				body {background: #fff; font: 12px/14px Arial, sans-serif;}
				#wrapper { margin: 10px;  border: 1px solid #5c9fce;}
				#content { margin: 10px; }
				.header { background: #ccc; color: white; padding: 8px; margin: 2px; font-size: 20px; font-weight:normal; }
				a:link,a:visited {text-decoration: none; color: blue;}
				a:active {text-decoration: none}
				a:hover {text-decoration: underline; color: red;}
			</style>
		</head>
		<body>
			<div id="wrapper">		
				<br />
				<div class="header">
				<strongSecureTransport</strong>
				</div>
				<div id="content">
					<br /><br />
					<div>
					$($mailMessage)
					</div>
					<br /><br />					
				</div>
			</div>
		</body>
	</html>
"@
	
	
	Send-MailMessage -SmtpServer $SMTPServer -From $mailFrom -To $MailTo -Subject $mailSubject -BodyAsHtml $htmlEmail
	
	Write-Verbose "EXPIRY NOTIFICATION SENT # TO: $mailTo # FROM: $mailFrom # SUBJECT: $mailSibject # MAILMSG: $mailMessage "
}

function send-Report()
{
	$mailMessage = "This is a notification from the NS&I Managed File Transfer Service. Please find attached a HTML report of the accounts on the SecureTransport Server $servername"
	$mailSubject = "SecureTransport: Password Expiry Notification"
	$mailTo = "audit@acme.com"
	$mailFrom = "securetransport@acme.com"	
	$SMTPServer = "192.168.0.1"
	
	$htmlEmail = @"
	<?xml version="1.0" encoding="UTF-8"?>
	<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN"
    "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">

	<html xmlns="http://www.w3.org/1999/xhtml">
		<!-- Created on: 05/06/2005 -->
		<head>
			<meta http-equiv="Content-Type" content="text/html; charset=UTF-8" />
			<title></title>
			<style type="text/css">
				* {margin: 0; padding: 0;}
				body {background: #fff; font: 12px/14px Arial, sans-serif;}
				#wrapper { margin: 10px;  border: 1px solid #5c9fce;}
				#content { margin: 10px; }
				.header { background: #00649f; color: white; padding: 8px; margin: 2px; font-size: 20px; font-weight:normal; }
				a:link,a:visited {text-decoration: none; color: blue;}
				a:active {text-decoration: none}
				a:hover {text-decoration: underline; color: red;}
			</style>
		</head>
		<body>
			<div id="wrapper">
				<br />
				<div class="header">
				<strongSecureTransport</strong>
				</div>
				<div id="content">
					<br /><br />
					<div>
					$($mailMessage)
					</div>
					<br /><br />					
				</div>
			</div>
		</body>
	</html>
"@
	
	
	Send-MailMessage -SmtpServer $SMTPServer -From $mailFrom -To $MailTo -Subject $mailSubject -BodyAsHtml $htmlEmail -Attachments $ReportFile
	
	Write-Verbose "EXPIRY NOTIFICATION SENT # TO: $mailTo # FROM: $mailFrom # SUBJECT: $mailSibject # MAILMSG: $mailMessage "
}

# Returns a given user's email address
function get-UserEmail($user)
{
    $getEmailQuery = "SELECT email from account WHERE name = '$user'"
    $geqResults = run-MySQLQuery -connectionString $connString -query $getEmailQuery
	
	if (is-null $geqResults[0] ) { return "No email address configured for $user"  }			
	return $geqResults[0]   
} # END FUNCTION get-UserEmail

# Returns a list of accounts and their status
function get-DisabledAccounts()
{
	$TempHash = @()
	$ObjProps = @()
	
	$getAccountStatusQuery = "SELECT name,email,disabled from account WHERE BIN(disabled)='1'"
    $gasResults = run-MySQLQuery -connectionString $connString -query $getAccountStatusQuery
	
	if( $gasResults -eq $null )
	{
		$ObjProps = @{'Name'='no users found';
			'Email'='-';
			'Disabled'='-';}
		$disabled_user_accounts_obj = New-Object –TypeName PSObject –Prop $ObjProps
		$TempHash += $disabled_user_accounts_obj
		return $TempHash
	}
	
	foreach ( $row in $gasResults )
	{
		if ( $row.disabled -eq 0) { $UserAccountStatus = "Active"  }
		elseif ( $row.disabled -eq 1) { 
			$UserAccountStatus = "Disabled" 
			Write-Verbose "User $($row.name) is disabled"
		}
		else { $UserAccountStatus = "" }
				
		$ObjProps = @{'Name'=$row.name;
			'Email'=$row.email;
			'Disabled'=$UserAccountStatus;}
		$disabled_user_accounts_obj = New-Object –TypeName PSObject –Prop $ObjProps
		$TempHash += $disabled_user_accounts_obj
		
	}
	return $TempHash
} # END FUNCTION get-AccountStatus


function get-UnusedAccounts()
{
	$TempHash = @()
	$ObjProps = @()
	$gllnQuery = "SELECT LoginName FROM virtualuser WHERE LastLogin IS NULL"
    $gllnResults = run-MySQLQuery -connectionString $connString -query $gllnQuery
	
	if( $guawnpeResults -eq $null )
	{
		$ObjProps = @{'Name'='no users found';
			'Email'='-';}
		$unused_user_accounts_obj = New-Object –TypeName PSObject –Prop $ObjProps
		$TempHash += $unused_user_accounts_obj
		return $TempHash
	}
	
	foreach ( $row in $gllnResults )
	{
		$email = get-UserEmail $row.LoginName
		
		$ObjProps = @{'Name'=$row.LoginName;
			'Email'=$email;}
		$unused_user_accounts_obj = New-Object –TypeName PSObject –Prop $ObjProps
		$TempHash += $unused_user_accounts_obj
		Write-Verbose "User $($row.LoginName) has no last login date - it has never been used"
	}
	return $TempHash
} # END FUNCTION get-UnusedAccounts


function get-UsrAccountsWithNoPasswordExpiry()
{
	$TempHash = @()
	$ObjProps = @()
	$guawnpeQuery = "SELECT LoginName FROM virtualuser WHERE passwordExpireInterval IS NULL"
	$guawnpeResults = run-MySQLQuery -connectionString $connString -query $guawnpeQuery
    
	if( $guawnpeResults -eq $null )
	{
		$ObjProps = @{'Name'='no users found';
			'Email'='-';}
		$no_passwd_expiry_user_accounts_obj = New-Object –TypeName PSObject –Prop $ObjProps
		$TempHash += $no_passwd_expiry_user_accounts_obj
		return $TempHash
	}
	
	foreach ( $row in $guawnpeResults )
	{
		$email = get-UserEmail $row.LoginName
		
		$ObjProps = @{'Name'=$row.LoginName;
			'Email'=$email;}
		$no_passwd_expiry_user_accounts_obj = New-Object –TypeName PSObject –Prop $ObjProps
		$TempHash += $no_passwd_expiry_user_accounts_obj
		Write-Verbose "User $($row.LoginName) has no password expiry date set"
	}
	return $TempHash
} # END FUNCTION get-UsrAccountsWithNoPasswordExpiry


function get-AccountsNotUsedinXDays($days)
{
	$TempHash = @()
	$ObjProps = @()
	$timeinseconds = $days * 86400
	$ganuixdQuery = "SELECT LoginName, LastLogin FROM virtualuser WHERE LastLogin > (UNIX_TIMESTAMP(NOW()) - $timeinseconds)"
	$ganuixdResults = run-MySQLQuery -connectionString $connString -query $ganuixdQuery
    
	if( $ganuixdResults -eq $null )
	{
		$ObjProps = @{'Name'='no users found';
			'Email'='-';
			'LastLogin'='-';}
		$no_login_in_x_days_user_accounts_obj = New-Object –TypeName PSObject –Prop $ObjProps
		$TempHash += $no_login_in_x_days_user_accounts_obj
		return $TempHash
	}
	
	foreach ( $row in $ganuixdResults )
	{
		$email = get-UserEmail $row.LoginName
		
		$ObjProps = @{'Name'=$row.LoginName;
			'Email'=$email;
			'LastLogin'=$row.LastLogin;}
		$no_login_in_x_days_user_accounts_obj = New-Object –TypeName PSObject –Prop $ObjProps
		$TempHash += $no_login_in_x_days_user_accounts_obj
		Write-Verbose "User $($row.LoginName) has not been used in $days days"
	}
	return $TempHash
} #END FUNCTION get-AccountsNotUsedinXDays


function get-ExpiringUserAccounts()
{
	$TempHash =@()
	$ObjProps = @()
	$virtualUserTableQuery = "SELECT LoginName, passwordExpireInterval, LastLogin FROM virtualuser"
	$results = run-MySQLQuery -connectionString $connString -query $virtualUserTableQuery	
	
	if( $results -eq $null )
	{
		$ObjProps = @{'Name'='no users found';
						'Email'='-';
						'LastLogin'='-';
						'Days to Password Expiry'='-'}
		$expiring_passwd_obj = New-Object –TypeName PSObject –Prop $ObjProps
		$TempHash += $expiring_passwd_obj
		return $TempHash
	}
	
	foreach ( $row in $results)
	{
		if (is-null $row.LastLogin)
		{
			Write-Verbose "No LastLogin date for user: $($row.LoginName), the user has never logged in. Skipping user."
		} 
		else 
		{				
			 if (is-null $row.passwordExpireInterval)
			 {
				Write-Verbose "The password is not set to expire for user: $($row.LoginName)"
			 } 
			 else
			 {
				$culture = New-Object system.globalization.cultureinfo("en-GB")
				$LastLoginDate = Get-Date -Format ($culture.DateTimeFormat.ToLongDateString) -Date $row.LastLogin
				$mail = get-UserEmail $row.LoginName
			
				# Check how many days are left to expiry (negative values indicate the password has already expired!)
				$days_to_expiry = ($LastLoginDate.AddDays($row.passwordExpireInterval) - $LastLoginDate).Days
				
				if ( $days_to_expiry -lt $passwd_expiry_threshold )
				{
					$mail = get-UserEmail $row.LoginName                  
					$ObjProps = @{'Name'=$row.LoginName;
						'Email'=$mail;
						'LastLogin'=$LastLoginDate;
						'Days to Password Expiry'=$days_to_expiry}
					$expiring_passwd_obj = New-Object –TypeName PSObject –Prop $ObjProps
					$TempHash += $expiring_passwd_obj
					Write-Verbose "User $($row.LoginName), password is expiring in: $days_to_expiry days"
					
					if ( -not $SkipUserNotification ) {	notify-User $expiring_passwd_obj	}
				}
			 }   
		}
		#Write-Verbose ""
	} # END FOR LOOP	
	return $TempHash
} # END FUNCTION get-ExpiringUserAccounts


function get-AdminAccStatus()
{
	$TempHash = @()
	$AdminTableQuery = "SELECT name, lastPasswordChangeTime, lastLoginTime, isChangePassword FROM administrator"
	$results = run-MySQLQuery -connectionString $connString -query $AdminTableQuery
	
	if( $results -eq $null )
	{
		$props = @{'Name'='no users found';
				   'Last Login Date'='-';
				   'Last Password Change Date'='-';
				   'Account Status'='-';
				   'Password Expires in _ Days'='-';
				   }
		$account_obj = New-Object –TypeName PSObject –Prop $props
		$TempHash += $account_obj
		return $TempHash
	}
	
	foreach( $row in $results )
	{
		$culture = New-Object system.globalization.cultureinfo("en-GB")
		
		$lldisNull = $lpcdisNull = $FALSE;
		if (is-null $row.lastLoginTime) 
		{ 
			[string] $AdminLastLoginDate = "never"
			$lldisNull=$TRUE 
		}
		else  
		{ 
			$row.lastLoginTime -match "(?<xday>\d{2})\/(?<xmonth>\d{2})\/(?<xyear>\d{4})(.*)" | Out-Null
			[system.datetime] $AdminLastLoginDate =   Get-Date -Month $matches.xday -Day $matches.xmonth -Year $matches.xyear		
		}
		
		if (is-null $row.lastPasswordChangeTime) 
		{ 
			[string] $LastPasswordChangeDate = "never"
			$lpcdisNull=$TRUE 
		}
		else 
		{ 
			$row.lastPasswordChangeTime -match "(?<xday>\d{2})\/(?<xmonth>\d{2})\/(?<xyear>\d{4})(.*)" | Out-Null
			[system.datetime] $LastPasswordChangeDate =   Get-Date -Month $matches.xday -Day $matches.xmonth -Year $matches.xyear
		}    
		
		if (   (-not $lldisNull)  -and (-not $lpcdisNull) )
		{
			if ( $admin_password_expiry -eq $null )
			{
				# Check how many days are left to expiry (negative values indicate the password has already expired!)
				$daysToAdd = [int] $admin_password_expiry
				
				$DaysToExpiry = ( $LastPasswordChangeDate.AddDays($daysToAdd) - $LastPasswordChangeDate ).Days
				
				Write-Debug "Admin account, $($row.name), expiring in $DaysToExpiry days"
				
				if ( $DaysToExpiry -lt $passwd_expiry_threshold )
				{
					Write-Debug "Admin password for $($row.name) is due to expire soon."
				}
			}
			else
			{
				$DaysToExpiry = '-'
			}
		}
		else
		{
			$DaysToExpiry = '-'
		}
			
		if( $row.isChangePassword -eq 0) { $AccountStatus = "Active" }
		elseif ( $row.isChangePassword -eq 1) { $AccountStatus = "Disabled" }
		
		$props = @{'Name'=$row.name;
				   'Last Login Date'=$AdminLastLoginDate;
				   'Last Password Change Date'=$LastPasswordChangeDate;
				   'Account Status'=$AccountStatus;
				   'Password Expires in _ Days'=$DaysToExpiry;
				   }
		$account_obj = New-Object –TypeName PSObject –Prop $props
				
		$TempHash += $account_obj     
		
		#Write-Debug ""
		
	} # END FOR LOOP
	return $TempHash
} # END FUNCTION get-AdminAccStatus

##########################
# END FUNCTION DEFINITIONS
##########################


		
##########################
# BEGIN MAIN SCRIPT LOGIC
##########################

Write-Output ""
Write-Output "Starting user account audit script run at: $(Get-Date)" 

$LoadAssembly = [System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")

if ( -not $LoadAssembly ) 
{ 
	throw "Error! Assembly not found {MySql.Data}. Script execution will be halted."
	exit 1
}

Write-Output ""
Write-Output "Report will be written to $ReportFile"
Write-Output ""

# Only the internal SecureTransport Server holds user accounts
if ($servername -contains $InternalSTServer)
{
	$NoPasswordExpirySetAccountsHash = get-UsrAccountsWithNoPasswordExpiry
	$UnusedUserAccountsHash = get-UnusedAccounts
	$DisabledUserAccountsHash = get-DisabledAccounts 
	$NoLoginInXDaysAccountsHash = get-AccountsNotUsedinXDays $unusedThreshold 
}
$ExpUserPassHash = get-ExpiringUserAccounts

$AdminAccStatus = get-AdminAccStatus


##############################
# BEGIN HTML REPORT GENERATION
##############################

$head = @'
<title>SecureTransport Account Status Report</title>
<style>
body { background-color:#dddddd;
       font-family:Verdana;
       font-size:12pt; }
td, th { border:1px solid black;
         border-collapse:collapse; }
th { color:white;
     background-color:black; }
table, tr, td, th { padding: 2px; margin: 0px }
table { margin-left:50px; }
a:link, a:visited { color: #6600ff; text-decoration:none;}
a:hover  { color: #ff4b33; text-decoration:underline;}
table { 
	font-family: Verdana; 
	border-style: dashed; 
	border-width: 1px; 
	border-color: #FF6600; 
	padding: 5px; 
	background-color: #FFFFCC; 
	table-layout: auto; 
	text-align: center; 
	font-size: 10pt; 
} 
table th { 
	border-bottom-style: solid; 
	border-bottom-width: 1px; 
} 
table td { 
	border-top-style: solid; 
	border-top-width: 1px; 
} 
</style>
'@

$rundate = Get-Date

$precontent = @"
<h1>SecureTransport Account Status Report</h1>
<br />
<table>
<tr><th>Computername</th><td>$($servername)</td></tr>
<tr><th style="text-align:left">Run Date</th><td>$($rundate)</td></tr>
</table>
<br />
"@

 #insert navigation bookmarks
$nav=@"
<br /><br />
<a href='#userpe'>User Password Expiry</a>
<a href='#dua'>Disabled User Accounts</a>
<a href='#usernpe'>User Accounts with no Password Expiry Date</a>
<a href='#uuacc'>Unused User Accounts</a>
<a href='#nlixd'>Accounts Unused in $unusedThreshold days</a>
<a href='#adminaccinfo'>Admin Account Information</a>
<br /><br />
"@

$userpe=@"
<H2><a name='userpe'>User Password Expiry</a></H2>
<br />
<p>The table below lists user accounts that are due to expire in $($passwd_expiry_threshold) days or less</p>
"@
$dua=@"
<H2><a name='dua'>Disabled User Accounts</a></H2>
<br />
<p>The table below lists user accounts that have been disabled</p>
"@
$usernpe=@"
<H2><a name='usernpe'>User Accounts with no Password Expiry Date</a></H2>
<br />
<p>The table below lists user accounts that do not have a password expiry date (i.e. the password never expires)</p>
"@
$uuacc=@"
<H2><a name='uuacc'>Unused User Accounts</a></H2>
<br />
<p>The table below lists the accounts where the user has never logged in.</p>
"@
$nlixd=@"
<H2><a name='nlixd'>Accounts Not Used in the Last $unusedThreshold days</a></H2>
<br />
<p>The table below lists the accounts where the user has not logged in $unusedThreshold days </p>
"@
$adminaccinfo=@"
<H2><a name='adminaccinfo'>Admin Account Information</a></H2>
<br />
<p>The table below provides information on administrative accounts. The account expired column indicates whether the account has been expired (i.e. locked out via the administrative interface).</p>
"@

Write-Output " "
Write-Output "Generating HTML report"
Write-Output " "


if ($servername -contains $InternalSTServer)
{
$fraghash+=$nav
$fraghash += $ExpUserPassHash | ConvertTo-Html -As Table -Fragment -PreContent $userpe | Out-String
$fraghash+=$nav
$fraghash += $DisabledUserAccountsHash  | ConvertTo-Html -As Table -Fragment -PreContent $dua | Out-String
$fraghash+=$nav
$fraghash += $NoPasswordExpirySetAccountsHash | ConvertTo-Html -As Table -Fragment -PreContent $usernpe | Out-String
$fraghash+=$nav
$fraghash += $UnusedUserAccountsHash | ConvertTo-Html -As Table -Fragment -PreContent $uuacc | Out-String
$fraghash+=$nav
$fraghash += $NoLoginInXDaysAccountsHash | ConvertTo-Html -As Table -Fragment -PreContent $nlixd | Out-String
$fraghash+=$nav
}
$fraghash += $AdminAccStatus | ConvertTo-Html -As Table -Fragment -PreContent $adminaccinfo | Out-String

if ($servername -contains $InternalSTServer)
{
	$fraghash+=$nav
}
ConvertTo-HTML -head $head -PostContent $fraghash -PreContent $precontent > $ReportFile

Write-Output "Sending audit report via email"
send-Report
Write-Output " "

############################
# END HTML REPORT GENERATION
############################

Write-Output " "
Write-Output "Script finished and report produced at $(Get-Date)"
Write-Output " "

$fraghash = $null
$ExpUserPassHash = $null
$DisabledUserAccountsHash = $null
$NoPasswordExpirySetAccountsHash = $null
$UnusedUserAccountsHash = $null
$NoLoginInXDaysAccountsHash = $null
$AdminAccStatus = $null

[GC]::Collect()


##########################
# END MAIN SCRIPT LOGIC
##########################