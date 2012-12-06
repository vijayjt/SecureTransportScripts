<#   
    .SYNOPSIS   
        Check expiry dates of SecureTransport Certificates
    .DESCRIPTION   
        Produces a HTML based report of all SecureTransport certificates and when they are due to expire. 
        This version of the script currently checks the admind, httpd, sshd,ca and tm certificates. 
        It does not check any intermediate CA certificates from third parties.
        
        
    .PARAMETER  ReportPath   
        Specify the full path to where the report should be saved E.g. C:\certificate_reports\
    .EXAMPLE   
        check-cert-expiry.ps1 -ReportPath C:\output\
    .NOTES  
        File Name  : check-cert-expiry.ps1 
        Author     : Vijay Thakorlal
        Requires   : PowerShell V2
        To Do      : 
        
        IMPORTANT NOTES
        1. Change the $threshold variable's value to suit your needs and to provide adequate time to plan for renewing certificates.
#>   


param(
	[ValidateScript({
		$vr = Test-Path $_
		if(!$vr){Write-Host "The provided path $_ is invalid!"}
		$vr
	})][String]$ReportPath
    )

# Enable debugging output
$DebugPreference = "continue"

Write-Output "Starting certificate validity checker script run at: $(Get-Date)" 


# HTML Report File Location
if( $ReportPath.Length -eq 0 ) 
{ 
	$ReportPath = "C:\" 
}
$ReportFile = Join-Path $ReportPath  "certificate_report.html"

Write-Output "Report will be written to $ReportFile"

## Get the hostname
$servername = $env:COMPUTERNAME

# Set location of the openssl command / binary and certificate store 
# based on the server name

$OpenSSLLocation= "c:\Program Files\Tumbleweed\SecureTransport\STServer\bin\"
$CertificateStoreLocation = "C:\Program Files\Tumbleweed\SecureTransport\STServer\lib\certs\"
$OpenSSLConfFile = "C:\Program Files\Tumbleweed\SecureTransport\STServer\etc\ssl\openssl.cnf"


# Set the OPENSSL_CONF environment variable to point to the 
# OpenSSL Configuration file
$env:OPENSSL_CONF = $OpenSSLConfFile

## If the certificate is due to expire in $threshold days or less then report this
$threshold = 60


## Certificate file names
$cert_names = @()
Get-ChildItem $CertificateStoreLocation -Filter "*-crt.pem" | % { $cert_names += ($_.FullName).ToString() }
Get-ChildItem ($CertificateStoreLocation + "db") -Filter "*-crt.pem" | % { $cert_names +=  ($_.FullName).ToString() }

$PrevWD = Get-Location

## BEGIN FUNCTION Get-CertInfo
function Get-CertInfo ($cert_to_check, $expiry_threshold) 
{
    # WARNING:
    # DO NOT use anything but WRITE-DEBUG within this function otherwise the output will be passed into the pipeline 
	# and into the object which will then be used to produce the HTML report
        
    Set-Location $OpenSSLLocation
    $CurrentDir = Get-Location
    
    #Write-Debug "Current Location is: $CurrentDir"
	
    Write-Debug "Checking certificate $cert_to_check"
    
    # We use hash variables to store the parameters to ensure PowerShell
    # correctly runs the external command line tool properly
    $OpenSSL = "openssl.exe"
    $params_date = @("x509","-dates","-in",$($cert_to_check),"-noout")
    $params_subject = @("x509","-in",$($cert_to_check),"-subject","-noout")
        
    [string]$cert_dates = & $OpenSSL $params_date

    $cert_dates -match "notAfter=(?<month>[A-z]{3})\s\s(?<day>\d{1}) (?<time>\d{2}\:\d{2}\:\d{2}) (?<year>\d{4})" | Out-Null
    $cert_expiry_date = [system.datetime] ($matches.day + $matches.month + $matches.year)

    $todays_date = Get-Date
    $days_to_expiry = ($cert_expiry_date - $todays_date).Days

    [string]$cert_subject = & $OpenSSL $params_subject
    
    #Find the common name of the certificate from within the output from the command using a RegEx
    $cert_subject -match "/CN=(?<commonname>.*)" | Out-Null
    $cert_cname = $matches.commonname
    
    $cert_type = ""
    if( $cert_to_check -like "*http*" ) { $cert_type = "HTTP" }
    elseif ( $cert_to_check -like "*admin*" ) { $cert_type = "Admin Interface" }
    elseif ( $cert_to_check -like "*ssh*" ) { $cert_type = "SSH" }
    elseif ( $cert_to_check -like "*tm*" ) { $cert_type = "Transaction Manager" }
    elseif ( $cert_to_check -like "*ca*" ) { $cert_type = "CA Certificate" }
    
    Write-Debug "The $cert_type certificate with the Common Name: $cert_cname is due to expire in $days_to_expiry days"
    
    
    if ($days_to_expiry -le $expiry_threshold )
    {
        # If the certificate is expiring highlight it by making the font colour red
        # We're using custom tags as a means to replace this with < and > tags otherwise
        # the ConverTo-HTML cmdlet will attempt to translate / parse this
        $hl_cert_type = "xopenFont color=Redxclose{0}xopen/Fontxclose" -f $cert_type
        $hl_cert_cname = "xopenFont color=Redxclose{0}xopen/Fontxclose" -f $cert_cname
        $hl_cert_to_check = "xopenFont color=Redxclose{0}xopen/Fontxclose" -f $cert_to_check
        $hl_cert_expiry_date = "xopenFont color=Redxclose{0}xopen/Fontxclose" -f $cert_expiry_date
        $hl_days_to_expiry = "xopenFont color=Redxclose{0}xopen/Fontxclose" -f $days_to_expiry
        
        $props = @{'Certificate Type'=$hl_cert_type
        'Common Name'=$hl_cert_cname
        'File Name'=$hl_cert_to_check
        'Expiry Date'=$hl_cert_expiry_date
        'Days to Expiry'=$hl_days_to_expiry}
       
    }
    else
    {
        $props = @{'Certificate Type'=$cert_type
        'Common Name'=$cert_cname
        'File Name'=$cert_to_check
        'Expiry Date'=$cert_expiry_date
        'Days to Expiry'=$days_to_expiry}       
       
    }
    
     
    $obj = New-Object -TypeName PSObject -Property $props
    Write-Output $obj
    
} ## END FUNCTION Get-CertInfo

$expiring = $false
$fraghash = @()

if( $cert_names -ne $null -or $cert_names.length -ne 0 )
{
    #Write-Output "After IF CERT NAMES NE NULL"
    foreach ($certificate_type in $cert_names)
    {
        #Write-Output "IN FOR LOOP"
        $cert_object = Get-CertInfo $certificate_type $threshold 
        
        # Extract number of days to expiry from within custom tags
        $expiry_val = ($cert_object."Days To Expiry").Replace("xopenFont color=Redxclose", "")
        $expiry_val = [int]$expiry_val.Replace("xopen/Fontxclose", "")
        
        if ($expiry_val -le $threshold ) { $expiring = $true }   
        
        $fraghash += $cert_object
        
                
    }
}
else
{
    Write-Output "Error: No certificate files found exiting script..."
    exit
}


$head = @'
<title>Certificate Validity Report</title>
<style>
body { background-color:#dddddd;
       font-family:Tahoma;
       font-size:12pt; }
td, th { border:1px solid black;
         border-collapse:collapse; }
th { color:white;
     background-color:black; }
table, tr, td, th { padding: 2px; margin: 0px }
table { margin-left:50px; }
</style>
'@

$rundate = Get-Date

$precontent = @"
<h1>Certificate Validity Report</h1>
<br />
<table>
<tr><th>Computername</th><td>$($servername)</td></tr>
<tr><th style="text-align:left">Run Date</th><td>$($rundate)</td></tr>
</table>
<br />
"@


Write-Output "Generating HTML report"

$fraghash = $fraghash | ConvertTo-Html -As Table -Fragment



# Replace the tag place holders to highlight certs that are expiring in red
# This uses a hack suggested by Jeffrey Hicks
$fraghash=$fraghash -replace "xopen","<"
$fraghash=$fraghash -replace "xclose",">"

#insert a blank line
$fraghash+="<br>"


if( $expiring )
{
    $action_msg="<p>Found certificates that are expiring in less than or equal to $threshold days. Please start the process of planning for the renewal of these certificates</p>
    <p>Self-signed certificates can be regenerated from within SecureTransport.</p>"
    $fraghash+=$action_msg
}

ConvertTo-HTML -head $head -PostContent $fraghash -PreContent $precontent > $ReportFile


# Modify these variables to match your environment
$mailSubject = "SecureTransport Certificate Validity Report"
$mailTo = "support@acme.com"
$mailFrom = "securetransport@acme.com"	
$SMTPServer = "192.168.0.1"

Send-MailMessage -SmtpServer $SMTPServer -From $mailFrom -To $MailTo -Subject $mailSubject -BodyAsHtml $action_msg -Attachments $ReportFile

Write-Output ""	
Write-Output "CERTIFICATE VALIDITY REPORT SENT TO: $mailTo # FROM: $mailFrom # SUBJECT: $mailSibject # MAILMSG: $action_msg"
Write-Output ""

Write-Output "Script finished and report produced"
Write-Output ""

Set-Location $PrevWD