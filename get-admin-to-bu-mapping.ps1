<#   
    .SYNOPSIS   
        Queries the SecureTransport MySQL database to produce a report on the mapping between administrative users and the business units which they can manage. 
		
    .DESCRIPTION   
        Queries the SecureTransport MySQL database to produce a report on the mapping between administrative users and the business units which they can manage. This information can be used to when deleting a business unit which can only be achieved if you 
			- Delete accounts within the business unit.
			- Remove the business unit from applications. Since at this stage there are no plans to create applications this does not apply.
			- Administrative accounts can be assigned business units which allow the administrator to modify settings for users in the business unit; you must un-assign the business unit from all administrators first. 
        
    .PARAMETER  
        
		
    .EXAMPLE   
        
		
    .NOTES  
        File Name  : get-admin-to-bu-mapping.ps1 
        Author     : Vijay Thakorlal
        Requires   : PowerShell V2
        To Do      : 
		
        IMPORTANT NOTES
			1. You must change the password to the mysql database password set during installation of SecureTransport
            2. The script requires that the MySQL Connector for .NET is installed on the server (http://dev.mysql.com/downloads/connector/net/). 
            3. The default port used by the MySQL database that comes with ST is 33060, if you changed this to something else during installation you'll need to modify the script accordingly.
        
#>   

[CmdletBinding()]
param()

############################
# BEGIN VARIABLE DEFINITIONS
############################

# Get the hostname
$servername = $env:COMPUTERNAME

# MySQL Connection String
$MySQLServer = "localhost"
$MySQLPort = "33060"
$MySQLUser = "root"
$MySQLPassword = "tumbleweed"
$MySQLDatbase = "st"
$connString = "Server=$MySQLServer;port=$MySQLPort;Uid=$MySQLUser;Pwd=$MySQLPassword;database=$MySQLDatbase;"

# HTML Report File Location
$ReportPath = "C:\scripts\"
$ReportFile = Join-Path $ReportPath  "securetransport-admin-to-bu-report.html"

###########################
# END VARIABLE DEFINITIONS
###########################


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


# 
function get-Mapping()
{
    $Query = "SELECT T12.name AS AdminAccount, T3.name AS BusinessUnit FROM (SELECT * FROM administrator AS T1 JOIN administrator_businessunit AS T2 ON T1.id=T2.administratorId) AS T12 JOIN businessunit AS T3 ON T12.businessunitId=T3.id"
    $QueryResults = run-MySQLQuery -connectionString $connString -query $Query
	
	$TempHash = @()
	$ObjProps = @()
	
	foreach ( $row in $QueryResults )
	{
		$ObjProps = @{'Admin Account'=$row.AdminAccount;
			'Business Unit'=$row.BusinessUnit;}
		$object = New-Object –TypeName PSObject –Prop $ObjProps
		$TempHash += $object
	}
	
	return $TempHash
} # END FUNCTION get-Mapping




$head = @'
<title>SecureTransport Report</title>
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
<h1>SecureTransport Admin Accounts Assigned to Business Units</h1>
<br />
<table>
<tr><th>Computername</th><td>$($servername)</td></tr>
<tr><th style="text-align:left">Run Date</th><td>$($rundate)</td></tr>
</table>
<br />
"@

##########################
# BEGIN MAIN SCRIPT LOGIC
##########################

Write-Output ""
Write-Output "Starting user account audit script run at: $(Get-Date)" 
Write-Output ""
Write-Output "Report will be written to $ReportFile"
Write-Output ""

Write-Output " "
Write-Output "Generating HTML report"
Write-Output " "

$MappingHash = get-Mapping
$HTMLFragment = $MappingHash | ConvertTo-Html -As Table -Fragment | Out-String

ConvertTo-HTML -head $head -PostContent $HTMLFragment -PreContent $precontent > $ReportFile

Write-Output " "
Write-Output "Script finished and report produced at $(Get-Date)"
Write-Output " "

$HTMLFragment = $null
$MappingHash = $null

[GC]::Collect()


##########################
# END MAIN SCRIPT LOGIC
##########################
