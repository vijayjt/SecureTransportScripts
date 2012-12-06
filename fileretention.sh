#!/bin/sh
#################################################################
# Author   : Vijay Thakorlal                                    #
# Date     : 20-03-2012                                         #
#                                                               #
# Purpose  : Delete transferred files that are older            #
#            than (not modified in the last) 30 days            #
#                                                               #
# Dependencies: This script is for a Windows based installation #
#               of SecureTransport which runs under Cygwin.     #
#                                                               #
# History  :                                                    #
# --------------------------------------------------------------#
# Date         |Author          |Description                    #
# --------------------------------------------------------------#
# 20-03-2012   |Vijay Thakorlal |Creation                       #
#                                                               #
#################################################################

#The directory containing the files that should be deleted
#The script assumes the user home folders are under the "d" drive and under the path D:\MFT\BusinessUnits
TARGET_DIR="/drives/d/MFT/BusinessUnits"

#The directory where a log file will be maintained of actions taken
LOG_PATH='/drives/d/Program Files/Tumbleweed/SecureTransport/STServer/var/logs'

#The file to log information on which files were deleted
STATUS_FILE=$LOG_PATH/fileretentionlog.txt


#The variable below will be used to define the number of days after which files should be
#deleted if they have not been modified since this date
DAYS='30'

#The Elapsed function calculates the number of days between two dates
Elapsed()	{
   HRS=$((($(date -d "$2" +%s)-$(date -d "$1" +%s))/3600))
   NUM_DAYS=$((HRS/24))
   echo $NUM_DAYS
}

#In order to keep the log file for this script a manageable size
#a new file will be used every day and old files removed every 30 days
CURR_DATE=`date +%F`
TIME=`date +%H-%M-%S`

#If the scripts log file exists, extract the last two lines to obtain the date
#the script was last run
if [ -e "$STATUS_FILE" ];
then
	LAST_RUN=`tail -2 "${STATUS_FILE}" | cut -d: -f2`
else
	touch "${STATUS_FILE}"
fi

#If the log file is not empty (i.e. there is a LAST RUN date)
#the determine if 30 days have passed, if so clear the log file
if [ -n "${LAST_RUN}" ];
then
	DIFF=$(Elapsed "$LAST_RUN" "$CURR_DATE")
	if [ "$DIFF" > 30 ];
	then
		touch "${STATUS_FILE}"
		echo "" > $STATUS_FILE
	fi
else
	touch "${STATUS_FILE}"
fi

#Find and delete files that have not been modified in $DAYS days
echo " START FILE DELETION"   				            	    >> $STATUS_FILE
echo " DATE (yyyy-mm-dd hh-mm-ss): ${CURR_DATE} ${TIME}"		>> $STATUS_FILE
echo ""                                     	             	>> $STATUS_FILE

cd $TARGET_DIR

echo "		These log files were removed:" 			            >> $STATUS_FILE
for T_FILE in `find . -type f -mtime +"$DAYS" -print 2>&1`
do
	echo "                $T_FILE"                            	>> $STATUS_FILE
	rm $T_FILE
done
echo " END FILE DELETION"   				            	    >> $STATUS_FILE
echo " LAST RUN:${CURR_DATE}"                      	            >> $STATUS_FILE
echo ""                                     	             	>> $STATUS_FILE