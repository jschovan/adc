#!/bin/bash
#
# Publish AutoPyFactory service metrics
# retro-fill


#docs: http://itmon.web.cern.ch/itmon/recipes/how_to_publish_service_metrics.html
#      http://itmon.web.cern.ch/itmon/recipes/how_to_create_a_service_xml.html

function err() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $@" >&2
}

function age() {
  local filename=$1
  local changed=$(stat -c %Y "$filename")
  local now=$(date +%s)
  local elapsed

  let elapsed=now-changed
  echo $elapsed
}

set -x

logfile=/tmp/apf-prep-for-submit.log
echo -n >${logfile}
for lll in /var/log/apf/apf.log-* /var/log/apf/apf.log
do
	grep 'Preparing to submit' ${lll} >>${logfile}
done

max_timestamp_str=$(date '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u)
min_timestamp_str=$(head -n30 $logfile | grep '^2' | cut -f1-3 -d" " | head -n1)
max_timestamp=$(date +%s --date "${max_timestamp_str}")
min_timestamp=$(date +%s --date "${min_timestamp_str}")
step=$((60*60))
nsteps=$(( (max_timestamp-min_timestamp)/step ))

for i in `seq 0 ${nsteps}`
do
#	min_ts=$((min_timestamp+i*step))
	max_ts=$((min_timestamp+(i+1)*step))
#	min_ts_str=$(date '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u --date "1970-01-01 ${min_ts} sec GMT")
	max_ts_str=$(date '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u --date "1970-01-01 ${max_ts} sec GMT")
	max_ts_filename=$(date '+%Y-%m-%d.%H%M%S' -u --date "1970-01-01 ${max_ts} sec GMT")
	echo "###### $i:   ${max_ts_str}"


#tmpfile=$(mktemp)
tmpfile=/tmp/apf-service-mon.${max_ts_filename}.xml
# logfile=/var/log/apf/apf.log
shortname=$(hostname -s)
# timestamp=$(date +%Y-%m-%dT%H:%M:%S)
timestamp=$(date +%Y-%m-%dT%H:%M:%S -u --date "${max_ts_str}")
logage=$(age "$logfile")

availability=0
if [[ $age -lt 300 ]]; then
    # availability=100
    availability="available"
elif [[ $age -lt 600 ]]; then
    # availability=75
    availability="degraded"
elif [[ $age -lt 1800 ]]; then
    # availability=25
    availability="unavailable"
fi

cat <<EOF > $tmpfile
<?xml version="1.0" encoding="UTF-8"?>
<serviceupdate xmlns="http://sls.cern.ch/SLS/XML/update">
  <id>PilotFactory_$shortname</id>
  <status>$availability</status>
  <webpage>http://apfmon.lancs.ac.uk</webpage>
  <contact>atlas-project-adc-operations-pilot-factory@cern.ch</contact>
  <timestamp>$timestamp</timestamp>
  <data>
    <numericvalue desc="Age of log file in seconds" name="age">$logage</numericvalue>
EOF

### log parsing
# logfile=/var/log/apf/apf.log
# d2=$(date '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u)
d2=$max_ts_str
# d_first=$(head -n30 ${logfile} | grep '^2' | cut -f1-3 -d" " | head -n1)

### last 15 min
suffix="last15min"
logfile_15min=/tmp/apf.log.${suffix}
resultfile_15min=$(mktemp)
# d1_15min=$(date --date="-15 min" '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u)
d1_15min=$(date --date "1970-01-01 $((max_ts-15*60)) sec GMT" '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u)

### last 1 hr
suffix="last1hr"
logfile_1hr=/tmp/apf.log.${suffix}
resultfile_1hr=$(mktemp)
# d1_1hr=$(date --date="-1 hour" '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u)
d1_1hr=$(date --date "1970-01-01 $((max_ts-60*60)) sec GMT" '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u)

### last 4 hr
suffix="last4hr"
logfile_4hr=/tmp/apf.log.${suffix}
resultfile_4hr=$(mktemp)
# d1_4hr=$(date --date="-4 hour" '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u)
d1_4hr=$(date --date "1970-01-01 $((max_ts-4*60*60)) sec GMT" '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u)

### last 12 hr
suffix="last12hr"
logfile_12hr=/tmp/apf.log.${suffix}
resultfile_12hr=$(mktemp)
# d1_12hr=$(date --date="-12 hour" '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u)
d1_12hr=$(date --date "1970-01-01 $((max_ts-12*60*60)) sec GMT" '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u)

### prepare last15min
cat ${logfile} | awk -v d1="$d1_15min" -v d2="$d2" '$0 > d1 && $0 < d2 || $0 ~ d2' > $logfile_15min 

### prepare last1hr
cat ${logfile} | awk -v d1="$d1_1hr" -v d2="$d2" '$0 > d1 && $0 < d2 || $0 ~ d2' > $logfile_1hr 

### prepare last4hr
cat ${logfile} | awk -v d1="$d1_4hr" -v d2="$d2" '$0 > d1 && $0 < d2 || $0 ~ d2' > $logfile_4hr 

### prepare last12hr
cat ${logfile} | awk -v d1="$d1_12hr" -v d2="$d2" '$0 > d1 && $0 < d2 || $0 ~ d2' > $logfile_12hr 


### process logs
python /root/xlog.py $logfile_15min $resultfile_15min last15min > $resultfile_15min
python /root/xlog.py $logfile_1hr $resultfile_1hr last1hr > $resultfile_1hr
python /root/xlog.py $logfile_4hr $resultfile_4hr last4hr > $resultfile_4hr
python /root/xlog.py $logfile_12hr $resultfile_12hr last12hr > $resultfile_12hr


for file in $resultfile_15min $resultfile_1hr $resultfile_4hr $resultfile_12hr
do
	cat $file >> $tmpfile
done

echo "</data></serviceupdate>" >> $tmpfile


# if ! curl -s -F file=@$tmpfile xsls.cern.ch >/dev/null ; then
#   err "Error sending XML to xsls.cern.ch"
#  exit 1
# fi

# rm -f $tmpfile 
rm -f $logfile_15min $resultfile_15min $logfile_1hr $resultfile_1hr $logfile_4hr $resultfile_4hr $logfile_12hr $resultfile_12hr 

### check validity
# xmllint --noout --schema http://itmon.web.cern.ch/itmon/files/xsls_schema.xsd $tmpfile


done ### end: for i in `seq 0 ${nsteps}`

