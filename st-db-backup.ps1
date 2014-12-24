<#   
    .SYNOPSIS   
        Backups up SecureTransport's embedded MySQL database.
    .DESCRIPTION   
        This script backs up the SecureTransport MySQL database using the mysqldump utility.
        
    .PARAMETER  -SkipLog   
        If specified the script will not dump the TransferStatus and TransferData tables
    .EXAMPLE   
        
    .NOTES  
        File Name     :  st-db-backup.ps1
        Requires      : PowerShell V2
		Author        : This is a modified version of the MySQL backup script available here
					    http://support.appliedconsultancy.com/knowledgebase/default.asp?category_id=0&content_id=3233		
		Modified by   : Vijay Thakorlal
        Modifications : Changed variables to reflect MySQL credentials and localtion of mysqldump utility
						Changed all write-host to write-output
						Added error reporting code
        To Do         : Modify the script to issue email alerts when backup jobs fail?
					    Use read-secure string to store credentials in a file in an encrypted form?
		
        IMPORTANT NOTES
			1. You must change the password to the mysql database password set during installation of SecureTransport
        
#> 

# Get the hostname
$servername = $env:COMPUTERNAME

# Core settings
$mysql_server = "localhost"
$mysql_server_port = "33060"
$mysql_user = "root"
$mysql_password = "tumbleweed"
$backupstorefolder= "E:\mysqlbackups\backupfiles\"
$latestbackupfolder = "E:\mysqlbackups\backupfiles\latest\"
$MySQLDumpErrorLog = "E:\mysqlbackups\mysqldump-error-log.txt"

# The logfile to which the status information will be logged
$Logfile = "E:\mysqlbackups\st-db-backup-script-log-file.txt"
$statusMsg = ""
$global:BackupErrors = ""

# Modify the path below to reflect the fact ST is running on a 64-bit system (i.e. add x86 
$pathtostinstall = "C:\Program Files\Tumbleweed\SecureTransport\STServer\"
$pathtomysqlconf = $pathtostinstall + "conf\mysql.conf"
$pathtomysqldump = $pathtostinstall + "mysql\bin\mysqldump.exe"
$stdbname = "st"
$mysqldumpoptions = "--defaults-file=`"$pathtomysqlconf`" --single-transaction --ignore-table=$($stdbname).Event"

# HTML Report File Location
if ($SkipLog)
{ 
	$mysqldumpoptions += " --ignore-table=${$stdbname}.TransferStatus --ignore-table=${$stdbname}.TransferData"
}

if ( (Test-Path -Path $backupstorefolder) -ne $True -or (Test-Path -Path $latestbackupfolder) -ne $True ) 
{
	Write-Output "Error $backupstorefolder or $latestbackupfolder folder does not exist. Exiting script."
	exit 1;

}


#--------------------------------------------------------

function get-BackupSize ($filepath)
{
    $sizeInBytes = 0
    Get-ChildItem $filepath -Recurse | % { $sizeInBytes += $_.Length }

    switch ($sizeInBytes)
    {
        {$sizeInBytes -ge 1TB} {"{0:n$sigDigits}" -f ($sizeInBytes/1TB) + " TB" ; break}
        {$sizeInBytes -ge 1GB} {"{0:n$sigDigits}" -f ($sizeInBytes/1GB) + " GB" ; break}
        {$sizeInBytes -ge 1MB} {"{0:n$sigDigits}" -f ($sizeInBytes/1MB) + " MB" ; break}
        {$sizeInBytes -ge 1KB} {"{0:n$sigDigits}" -f ($sizeInBytes/1KB) + " KB" ; break}
        Default { "{0:n$sigDigits}" -f $sizeInBytes + " Bytes" }
    }
}

function Log-Maintenance($thelogfile)
{
	# If the log file doesn't exist this is the first run of the script (or it was manually deleted)
	if( Test-Path $thelogfile )
	{
		## Clear out the log file after say 63 days to prevent the file from getting too big
		$LogFileProperties = Get-Item $thelogfile
		$OlderThanXDays = 30
		$NumDaysOld = ( (Get-Date) - $LogFileProperties.CreationTime).Days
		if ( $NumDaysOld -gt $OlderThanXDays )
		{
			Write-Output "Log file is $NumDaysOld days old, overwriting contents of the log file..."
			Write-Output "" | Out-File -FilePath $thelogfile
			Write-Output "Log file cleared on $(Get-Date)" | Out-File -FilePath $thelogfile
			# Reset file creation time, otherwise the file will be overwritten on the next run of the script
			$LogFileProperties.CreationTime = Get-Date
		}
	}
} # END FUNCTION Log-Maintenance

Function backupDatabase()
{

[cmdletbinding(SupportsShouldProcess=$True)]
param ( )

# Determine Today's Date Day (monday, tuesday etc)
$gd = get-date
$dayofweek = [string] $gd.DayOfWeek


# Connect to MySQL database via MySQL Connector for .NET
#[system.reflection.assembly]::LoadWithPartialName("MySql.Data")
[void][System.Reflection.Assembly]::LoadWithPartialName("MySql.Data")
$cn = New-Object -TypeName MySql.Data.MySqlClient.MySqlConnection
If (!$cn)   
{  
  $statusMsg = "ERROR: Failed to load MySQL Connector for .NET"
  Write-Output $statusMsg
  Write-Output $statusMsg | Out-File -FilePath $LogFile -Append
  Exit
}

$cn.ConnectionString = "SERVER=$mysql_server;PORT=$mysql_server_port;DATABASE=information_schema;UID=$mysql_user;PWD=$mysql_password"
$cn.Open()

  

If ($cn.State -eq 1) 
{

# Query MySQL 
$cm = New-Object -TypeName MySql.Data.MySqlClient.MySqlCommand

If ($cm) 
{
	$sql = "SELECT DISTINCT CONVERT(SCHEMA_NAME USING UTF8) AS dbName, CONVERT(NOW() USING UTF8) AS dtStamp FROM SCHEMATA ORDER BY dbName ASC"
	$cm.Connection = $cn
	$cm.CommandText = $sql
	$dr = $cm.ExecuteReader() 

	# Loop through MySQL Records
	while ($dr.Read())
	{
		# Start By Writing MSG to screen
		$dbname = [string]$dr.GetString(0)
		
		# Startime for backing up this database
		$startTime = Get-Date
		
		
			$statusMsg = "Backing up database: $dbname" 
			Write-Output $statusMsg
			Write-Output $statusMsg | Out-File -FilePath $LogFile -Append
			Write-Output " "
			
			$statusMsg = ("Backup of DB: $dbname started at: " + (Get-Date -format yyyy-MM-dd-HH:mm:ss));
			Write-Output $statusMsg
			Write-Output $statusMsg | Out-File -FilePath $LogFile -Append

			# Set backup filename and check if exists, if so delete existing
			$backupfilename = $dayofweek + "_" + $dr.GetString(0) + ".sql"
			$backuppathandfile = $backupstorefolder + "" + $backupfilename
			If (test-path($backuppathandfile)) 
			{
				$statusMsg = "Backup file $backuppathandfile already exists.  Existing file will be deleted"
				Write-Output $statusMsg
				Write-Output $statusMsg | Out-File -FilePath $LogFile -Append
				Remove-Item $backuppathandfile
			}
			Else
			{
				$statusMsg = "Backup file $($backuppathandfile) doesn't exists. This will be created."
				Write-Output $statusMsg
				Write-Output  $statusMsg | Out-File -FilePath $LogFile -Append
				Write-Output " "
				
			}

			New-Item  -Path $backuppathandfile -ItemType File | Out-Null
			
			# Invoke backup Command. /c forces the system to wait to do the backup
			cmd /c " `"$pathtomysqldump`" $mysqldumpoptions --log-error=$MySQLDumpErrorLog -h $mysql_server -u $mysql_user --port $mysql_server_port -p$mysql_password $dbname " | Out-File $backuppathandfile -Encoding UTF8
			
			If ( (test-path($backuppathandfile)) -and ((Get-Content $backuppathandfile) -ne 0) ) 
			{
				
				$BackupSize = get-BackupSize $backuppathandfile
				$statusMsg =  "Backup created ($BackupSize). Presence of backup file verified" 
				$global:BackupErrors = $statusMsg
				Write-Output $statusMsg
				Write-Output $statusMsg | Out-File -FilePath $LogFile -Append
				Write-Output " "
				
				# Handle LatestBackup functionality
				If (test-path($backuppathandfile) ) 
				{
					$latestbackupfilenameandpath = $latestbackupfolder + "latest_" + $dbname + ".sql"
					&cmd /c "copy /y `"$backuppathandfile`" `"$latestbackupfilenameandpath`" " | Out-Null
					
					$statusMsg = "Backup file copied to latestbackup folder" 
					Write-Output $statusMsg 
					Write-Output $statusMsg  | Out-File -FilePath $LogFile -Append
					Write-Output " "
				}
			}
			else
			{
				$statusMsg = "ERROR: Could not create backup"
				$global:BackupErrors = $statusMsg
				Write-Output $statusMsg 
				Write-Output $statusMsg  | Out-File -FilePath $LogFile -Append
				Write-Output " "
			}
			
			$statusMsg = ("Backup Completed at: " + (Get-Date -format  yyyy-MM-dd-HH:mm:ss));
			Write-Output $statusMsg 
			Write-Output $statusMsg  | Out-File -FilePath $LogFile -Append
			Write-Output " "
			
		
		
		$endTime = Get-Date
		$completionTime = New-TimeSpan $startTime $endTime		
		$StatusMsg = "The backup of $dbname took $($completionTime.Hours) hours, $($completionTime.Minutes) minutes $($completionTime.Seconds) seconds"
		Write-Output $statusMsg 
		Write-Output $statusMsg  | Out-File -FilePath $LogFile -Append
		
	}# END WHILE
}
else
{
	$statusMsg = "ERROR: Cannot create SqlCommand object!"
	Write-Output $statusMsg 
	Write-Output $statusMsg  | Out-File -FilePath $LogFile -Append
}
}  #END IF CN.State -eq 1
else
{
	$statusMsg = "ERROR: Connection cannot be opened!"
	Write-Output $statusMsg 
	Write-Output $statusMsg  | Out-File -FilePath $LogFile -Append
}
$cn.Close()
$cn = $Null

} #END FUNCTION backupDatabase



#################
## MAIN SCRIPT ##
#################

Log-Maintenance $LogFile

$startTime = Get-Date

$statusMsg = "SECURETRANSPORT MySQL Database Backup Run Started at $startTime"
Write-Output $statusMsg 
Write-Output $statusMsg  | Out-File -FilePath $LogFile -Append

backupDatabase

$endTime = Get-Date
$completionTime = New-TimeSpan $startTime $endTime

$statusMsg = "The Backup Run took $($completionTime.Hours) hours, $($completionTime.Minutes) minutes $($completionTime.Seconds) seconds"
Write-Output $statusMsg 
Write-Output $statusMsg  | Out-File -FilePath $LogFile -Append

$statusMsg = "SECURETRANSPORT MySQL Database Backup Run Completed at $endTime"
Write-Output $statusMsg 
Write-Output $statusMsg  | Out-File -FilePath $LogFile -Append

$statusMsg = "###########################################################################"
Write-Output $statusMsg  | Out-File -FilePath $LogFile -Append
Write-Output "" 

$SMTPServer = "192.168.0.1"
$mailTo = "supportteam@acme.com"
$mailFrom = "securetransport@acme.com"
Send-MailMessage -SmtpServer $SMTPServer -From $mailFrom -To $mailTo -Subject "SecureTransport DB Backup on $servername" -Body "This is a notification from SecureTransport Server ($servername). The backup of the SecureTransport MySQL database has completed with the result: $($BackupErrors) " -Attachments $LogFile 

# END OF SCRIPT
