#!/bin/bash
# shell script dialog form to dump MySQL database

# FEATURES: Progress bar with ETA
# INPUT: dbhost, dbname, dbuser, destination folder, dbpassword on a separate hidden input form

# REQUIREMENTS:
# =============
# GNU Core Utilities, mysql, mysqldump, pv, dialog

export NCURSES_NO_UTF8_ACS=1

# variables declaration

declare -a fields

dbhost=""
dbname=""
dbuser=""
folder=""

# goto function

function jumpto
{
    label=$1
    cmd=$(sed -n "/$label:/{:a;n;p;ba};" $0 | grep -v ':$')
    eval "$cmd"
    exit
}

start=${1:-"start"}

jumpto $start

start:

# open fd

exec 3>&1

# store data

VALUES=$(dialog \
          --backtitle "MySQL Database Dump" \
          --title "Parameters" \
          --form "Please Input Values" \
15 50 0 \
        "Host:"     1 1 "$dbhost"       1 10 50 0 \
        "Database:" 2 1 "$dbname"       2 10 50 0 \
        "User:"     3 1 "$dbuser"       3 10 50 0 \
        "Folder:"   4 1 "$folder"       4 10 50 0 \
2>&1 1>&3)
exitCode=$?

# close fd
exec 3>&-

if [ $exitCode -eq 1 ]
then
   exit 1
fi

# catch values into field and array to check for empty values (all field required)

fields[0]=$(echo "$VALUES" | sed -n 1p) ; dbhost=$(echo ${fields[0]})
fields[1]=$(echo "$VALUES" | sed -n 2p) ; dbname=$(echo ${fields[1]})
fields[2]=$(echo "$VALUES" | sed -n 3p) ; dbuser=$(echo ${fields[2]})
fields[3]=$(echo "$VALUES" | sed -n 4p) ; folder=$(echo ${fields[3]})

file="$folder$dbname.sql.gz"
log=$folder/mydump.log

empty_fields=0

for var in "${fields[@]}"
do
   if [[ -z "$var" ]]
   then
      empty_fields=$((empty_fields+1))
   fi
done

if [ "$empty_fields" -ne 0 ]
then
   dialog --title "WARNING!" --msgbox "Please fill all Fields!" 10 50
   jumpto start
fi

# check if destination folder exist

if [ ! -d "$folder" ]
then
   dialog --title "WARNING!" --msgbox "Destination Folder '$folder' does not exist!" 10 50
   jumpto start
fi

# ask for password in a separate hidden field
# password storage

password=$(tempfile 2>/dev/null)

# trap it
trap "rm -f $password" 0 1 2 5 15

# get MySQL databse password
dialog --title "Database Password" \
--clear \
--insecure \
--passwordbox "Enter your password" 10 30 2> $password

exitCode=$?

if [ $exitCode -eq 1 ]
then
   jumpto start
fi

DB_PASSWORD=$(cat $password)
export MYSQL_PWD
MYSQL_PWD=$DB_PASSWORD

# check for db connection

temp_file=$(mktemp)

mysql \
    -h "$dbhost" \
    -u "$dbuser" \
    --silent \
    --skip-column-names \
    -e "SELECT ROUND(SUM(data_length) * 1.09) AS \"size_bytes\" \
    FROM information_schema.TABLES \
    WHERE table_schema='$dbname';" 2>$temp_file

if [ `cat $temp_file | wc -l` -eq 0 ]
then

   # check if destination file exist

   if dialog --stdout --title "WARNING!" \
             --yesno "Overwrite File '$file'!" 10 50
   then
      sleep 1
   else
      jumpto start
   fi
else
   dialog --title "WARNING!" --msgbox "`cat $temp_file`" 10 50
   jumpto start
fi

rm $temp_file

# Get database size

db_size=$(mysql \
    -h "$dbhost" \
    -u "$dbuser" \
    --silent \
    --skip-column-names \
    -e "SELECT ROUND(SUM(data_length) * 1.09) AS \"size_bytes\" \
    FROM information_schema.TABLES \
    WHERE table_schema='$dbname';"
)

db_size=$(($db_size * 2))
size=$(numfmt --to=iec-i --suffix=B "$db_size")

time=$(date --rfc-3339=seconds)
echo "[$time] - Dumping database '$dbname' (≈$size) into $file ..." >> $log

# Dump database into $dbname.sql.gz 

(mysqldump \
    -v \
    -h "$dbhost" \
    -u "$dbuser" \
    --compact \
    --databases \
    --dump-date \
    --hex-blob \
    --order-by-primary \
    --quick \
    "$dbname" \
| pv -n -s "$db_size" \
| gzip -c > "$file") 2>&1 \
| dialog --gauge "Dumping database '$dbname' (≈$size) into $file ..." 10 75

# go back to form with all field filled

time=$(date --rfc-3339=seconds)
echo "[$time] - Dumped database '$dbname'" >> $log
dialog --title "INFO" --msgbox "Dumping database '$dbname' (≈$size) into '$file' complete!" 10 50

jumpto start
