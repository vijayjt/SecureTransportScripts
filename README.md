SecureTransportScripts
======================

This repository contains scripts for managing / automating the Axway SecureTransport secure file transfer product. SecureTransport is one of a number of Managed File Transfer (MFT) solutions on the market. The product allows you to securely transfer files using a number of different protocols (HTTPS, SSHv2, SFTP, FTPS etc) and maintain an audit trail of file transfers.

The scripts provided here range from extracting information from the SecureTransport database for audit purposes, implementing file retention to startup scripts for supplementary SecureTransport modules/ products.

FileRetension.sh
----------------

SecureTransport (ST) on Windows relies on a number of components which run under Cygwin. This shell script can be executed as a cron job every day, it will delete all files with a modification time older than 30 days (or whatever retention policy you wish to implement). You will need to edit the script to change the TARGET_DIR variable to point to where the user home folders reside and the LOG_PATH variable to SecureTransport's var\logs directory. In doing so you'll have to enter Cygwin style paths i.e. /drives/c/some/path/ rather than Windows paths C:\some\path.

The file should be copied to the following directory (where D:\ should be changed to the drive where ST is installed)
```D:\Program Files (x86)\Tumbleweed\SecureTransport\STServer\bin\```

Next the script needs to be scheduled to run by creating a cron job entry:
1. Open a Windows command prompt
2. Type "D:\Program Files (x86)\Tumbleweed\SecureTransport\cygwin\"
3. Type Cygwin.bat to open a Cygwin shell
4. Type cd /var/cron/tabs
5. Type chmod 677 SYSTEM

This will change the permissions of the file so you can save your changes. While you can do this from windows, it's simpler to do it from a shell because in Windows you'll have to take ownership before you can give the administrator user write permissions.

6. Type vim SYSTEM to edit the file

After changing the permissions you can edit the file with wordpad / notepad but it is preferable to use vim from within the shell to avoid any DOS vs UNIX file format issues that lead to cron being unable to read the file.

7. Type "shift-g" to go to the last line of the file
8. Type the letter o to enable editing mode and enter a new line
9. Type the following line to the file to schedule the script to run on the 28th day of every month at 11:30 pm:

``` 30 23 * 28 * "/drives/d/Program Files (x86)/Tumbleweed/SecureTransport/STServer/bin/fileretention.sh" >> /tmp/ fileretention.out 2>&1```  

  This should all be on one line.

10. Type ":wq" to save the file and exit
11. Type exit

Restart the cron service after making changes to this file. To do this, start **Task Manager**, select the Services tab and find the cygwin_cron service in the list, right-click it, and select **Stop Service** and then select it again and select **Start Service**.


get-admin-to-bu-mapping.ps1
---------------------------

SecureTransport (ST) users can be allocated to Business Units. A business unit allows you to define a settings that are common to a group of users. Deleting a business unit can be convoluted because they cannot be deleted  if there are accounts, applications or administrators associated with the business unit.

Unfortunately, the GUI does not provide a means to easily identify which administrative users have been assigned which business units. So you have to manually check each administrative account. This Windows Powershell (requires v2.0) will extract the information from the MySQL database used by ST and generate a html report containing this information. This script is for a Windows based ST installation.

The script requires that the MySQL Connector for .NET is installed on the server. You will also need to change the MySQL password to match the one you set when installing ST. The default port used by the MySQL database that comes with ST is 33060, if you changed this to something else during installation you'll need to modify the script accordingly.


gen-account-audit-report.ps1
----------------------------

This Windows Powershell script generates a report on unused accounts or accounts that do not have a password expiry interval. The script is for a Windows based installation of SecureTransport. It extracts this information from ST's MySQL database and outputs the information as a HTML report. 

The script will need to be modified to reflect:
1. The drive where ST has been installed
2. The MySQL password for your environment
3. The password expiry threshold based on which you want accounts to be flagged on

The script requires that you have the MySQL Connector for .NET installed. The script assumes that ST has been deployed in a "streaming configuration" with an Internet facing SecureTransport Edge server and an internal SecureTransport server. You'll need to modify the InternalSTServer variable to match the hostname of your internal ST server.


check-cert-expiry.ps1
---------------------

SecureTransport has its own built in certificate authority which is used to generate certificates for the HTTPD, SSHD, ADMIND and other services. 

While you can manually review the validity dates, this script automates this using PowerShell. The script uses OpenSSL (bundled with SecureTransport) to check certificates.


* The variables $OpenSSLLocation, $CertificateStoreLocation , $OpenSSLConfFile to reflect the path to your SecureTransport installation 
* The variables $mailTo, $mailFrom, $SMTPServer will need to be modified to reflect your environment.
* The $threshold variable specifies the number of days prior to expiration that will trigger an email notification to be sent; this is set to 60 days.

Note the script requires you have PowerShell 2.0 deployed on the server.

st-db-backup.ps1
----------------

A powershell script to dump / backup SecureTransport's embedded MySQL databases. In order to use the script you will need to change the following items to reflect your environment:

* mysql_server_port - SecureTransport uses 33060 by default but if you changed this at installation time you will need to modify this variable
* mysql_password - the default password is tumbleweed, this will need to be changed accordingly
* backupstorefolder,latestbackupfolder,MySQLDumpErrorLog,Logfile - change the paths to reflect where you want the backups to be stored
* pathtostinstall - change this to reflect the installation path for your SecureTransport installation
* SMTPServer - change this to the SMTPServer you will be using for sending the email notifications
* mailTo, mailFrom - to reflect the from and to email addresses to be used for your environment


