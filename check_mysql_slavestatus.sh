#!/bin/bash
#########################################################################
# Script:	check_mysql_slavestatus.sh                              #
# Author:	Claudio Kuenzler www.claudiokuenzler.com                #
# Purpose:	Monitor MySQL Replication status with Nagios            #
# Description:	Connects to given MySQL hosts and checks for running    #
#		SLAVE state and delivers additional info                #
# Original:	This script is a modified version of                    #
#		check mysql slave sql running written by dhirajt        #
# Thanks to:	Victor Balada Diaz for his ideas added on 20080930      #
#		Soren Klintrup for stuff added on 20081015              #
#		Marc Feret for Slave_IO_Running check 20111227          #
#		Peter Lecki for his mods added on 20120803              #
#		Serge Victor for his mods added on 20131223             #
#               Omri Bahumi for his fix added on 20131230               #
# History:                                                              #
# 2008041700 Original Script modified                                   #
# 2008041701 Added additional info if status OK	                        #
# 2008041702 Added usage of script with params -H -u -p	                #
# 2008041703 Added bindir variable for multiple platforms               #
# 2008041704 Added help because mankind needs help                      #
# 2008093000 Using /bin/sh instead of /bin/bash                         #
# 2008093001 Added port for MySQL server                                #
# 2008093002 Added mysqldir if mysql binary is elsewhere                #
# 2008101501 Changed bindir/mysqldir to use PATH                        #
# 2008101501 Use $() instead of `` to avoid forks                       #
# 2008101501 Use ${} for variables to prevent problems                  #
# 2008101501 Check if required commands exist                           #
# 2008101501 Check if mysql connection works                            #
# 2008101501 Exit with unknown status at script end                     #
# 2008101501 Also display help if no option is given                    #
# 2008101501 Add warning/critical check to delay                        #
# 2011062200 Add perfdata                                               #
# 2011122700 Checking Slave_IO_Running                                  #
# 2012080300 Changed to use only one mysql query                        #
# 2012080301 Added warn and crit delay as optional args                 #
# 2012080302 Added standard -h option for syntax help                   #
# 2012080303 Added check for mandatory options passed in                #
# 2012080304 Added error output from mysql                              #
# 2012080305 Changed from 'cut' to 'awk' (eliminate ws)                 #
# 2012111600 Do not show password in error output                       #
# 2013042800 Changed PATH to use existing PATH, too                     #
# 2013050800 Bugfix in PATH export                                      #
# 2013092700 Bugfix in PATH export                                      #
# 2013092701 Bugfix in getopts                                          #
# 2013101600 Rewrite of threshold logic and handling                    #
# 2013101601 Optical clean up                                           #
# 2013101602 Rewrite help output                                        #
# 2013101700 Handle Slave IO in 'Connecting' state                      #
# 2013101701 Minor changes in output, handling UNKWNON situations now   #
# 2013101702 Exit CRITICAL when Slave IO in Connecting state            #
# 2013123000 Slave_SQL_Running also matched Slave_SQL_Running_State     #
#########################################################################
# Usage: ./check_mysql_slavestatus.sh -H dbhost -P port -u dbuser -p dbpass -s connection -w integer -c integer
#########################################################################
help="\ncheck_mysql_slavestatus.sh (c) 2008-2014 GNU GPLv2 licence
Usage: check_mysql_slavestatus.sh -H host -P port -u username -p password [-s connection] [-w integer] [-c integer]\n
Options:\n-H Hostname or IP of slave server\n-P Port of slave server\n-u Username of DB-user\n-p Password of DB-user\n-s Connection name (optional, with multi-source replication)\n-w Delay in seconds for Warning status (optional)\n-c Delay in seconds for Critical status (optional)\n
Attention: The DB-user you type in must have CLIENT REPLICATION rights on the DB-server. Example:\n\tGRANT REPLICATION CLIENT on *.* TO 'nagios'@'%' IDENTIFIED BY 'secret';"

STATE_OK=0		# define the exit code if status is OK
STATE_WARNING=1		# define the exit code if status is Warning (not really used)
STATE_CRITICAL=2	# define the exit code if status is Critical
STATE_UNKNOWN=3		# define the exit code if status is Unknown
export PATH=$PATH:/usr/local/bin:/usr/bin:/bin # Set path
crit="No"		# what is the answer of MySQL Slave_SQL_Running for a Critical status?
ok="Yes"		# what is the answer of MySQL Slave_SQL_Running for an OK status?

for cmd in mysql awk grep [
do
 if ! `which ${cmd} &>/dev/null`
 then
  echo "UNKNOWN: This script requires the command '${cmd}' but it does not exist; please check if command exists and PATH is correct"
  exit ${STATE_UNKNOWN}
 fi
done

# Check for people who need help - aren't we all nice ;-)
#########################################################################
if [ "${1}" = "--help" -o "${#}" = "0" ];
	then
	echo -e "${help}";
	exit 1;
fi

# Important given variables for the DB-Connect
#########################################################################
while getopts "H:P:u:p:s:w:c:h" Input;
do
	case ${Input} in
	H)	host=${OPTARG};;
	P)	port=${OPTARG};;
	u)	user=${OPTARG};;
	p)	password=${OPTARG};;
	s)	connection=\"${OPTARG}\";;
	w)      warn_delay=${OPTARG};;
	c)      crit_delay=${OPTARG};;
	h)      echo -e "${help}"; exit 1;;
	\?)	echo "Wrong option given. Please use options -H for host, -P for port, -u for user and -p for password"
		exit 1
		;;
	esac
done

# Connect to the DB server and check for informations
#########################################################################
# Check whether all required arguments were passed in
if [ -z "${host}" -o -z "${port}" -o -z "${user}" -o -z "${password}" ];then
	echo -e "${help}"
	exit ${STATE_UNKNOWN}
fi
# Connect to the DB server and store output in vars
ConnectionResult=`mysql -h ${host} -P ${port} -u ${user} --password=${password} -e "show slave ${connection} status\G" 2>&1`
if [ -z "`echo "${ConnectionResult}" |grep Slave_IO_State`" ]; then
	echo -e "CRITICAL: Unable to connect to server ${host}:${port} with username '${user}' and given password"
	exit ${STATE_CRITICAL}
fi
check=`echo "${ConnectionResult}" |grep Slave_SQL_Running: | awk '{print $2}'`
checkio=`echo "${ConnectionResult}" |grep Slave_IO_Running: | awk '{print $2}'`
masterinfo=`echo "${ConnectionResult}" |grep  Master_Host: | awk '{print $2}'`
delayinfo=`echo "${ConnectionResult}" |grep Seconds_Behind_Master: | awk '{print $2}'`

# Output of different exit states
#########################################################################
if [ ${check} = "NULL" ]; then
echo "CRITICAL: Slave_SQL_Running is answering NULL"; exit ${STATE_CRITICAL};
fi

if [ ${check} = ${crit} ]; then
echo "CRITICAL: ${host}:${port} Slave_SQL_Running: ${check}"; exit ${STATE_CRITICAL};
fi

if [ ${checkio} = ${crit} ]; then
echo "CRITICAL: ${host} Slave_IO_Running: ${checkio}"; exit ${STATE_CRITICAL};
fi

if [ ${checkio} = "Connecting" ]; then
echo "CRITICAL: ${host} Slave_IO_Running: ${checkio}"; exit ${STATE_CRITICAL};
fi

if [ ${check} = ${ok} ] && [ ${checkio} = ${ok} ]; then
 # Delay thresholds are set
 if [[ -n ${warn_delay} ]] && [[ -n ${crit_delay} ]]; then
  if ! [[ ${warn_delay} -gt 0 ]]; then echo "Warning threshold must be a valid integer greater than 0"; exit $STATE_UNKNOWN; fi
  if ! [[ ${crit_delay} -gt 0 ]]; then echo "Warning threshold must be a valid integer greater than 0"; exit $STATE_UNKNOWN; fi
  if [[ -z ${warn_delay} ]] || [[ -z ${crit_delay} ]]; then echo "Both warning and critical thresholds must be set"; exit $STATE_UNKNOWN; fi
  if [[ ${warn_delay} -gt ${crit_delay} ]]; then echo "Warning threshold cannot be greater than critical"; exit $STATE_UNKNOWN; fi

  if [[ ${delayinfo} -ge ${crit_delay} ]]
  then echo "CRITICAL: Slave is ${delayinfo} seconds behind Master | delay=${delayinfo}s"; exit ${STATE_CRITICAL}
  elif [[ ${delayinfo} -ge ${warn_delay} ]]
  then echo "WARNING: Slave is ${delayinfo} seconds behind Master | delay=${delayinfo}s"; exit ${STATE_WARNING}
  else echo "OK: Slave SQL running: ${check} Slave IO running: ${checkio} / master: ${masterinfo} / slave is ${delayinfo} seconds behind master | delay=${delayinfo}s"; exit ${STATE_OK};
  fi
 else
 # Without delay thresholds
 echo "OK: Slave SQL running: ${check} Slave IO running: ${checkio} / master: ${masterinfo} / slave is ${delayinfo} seconds behind master | delay=${delayinfo}s"
 exit ${STATE_OK};
 fi
fi

echo "UNKNOWN: should never reach this part (Slave_SQL_Running is ${check}, Slave_IO_Running is ${checkio})"
exit ${STATE_UNKNOWN}
