#!/bin/bash
#
# Publish AutoPyFactory service metrics


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

# set -x

tmpfile=$(mktemp)
logfile=/var/log/apf/apf.log
shortname=$(hostname -s)
timestamp=$(date +%Y-%m-%dT%H:%M:%S)
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
logfile=/var/log/apf/apf.log
d2=$(date '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u)
d_first=$(head -n30 ${logfile} | grep '^2' | cut -f1-3 -d" " | head -n1)

### last 15 min
suffix="last15min"
logfile_15min=/tmp/apf.log.${suffix}
resultfile_15min=$(mktemp)
d1_15min=$(date --date="-15 min" '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u)

### last 1 hr
suffix="last1hr"
logfile_1hr=/tmp/apf.log.${suffix}
resultfile_1hr=$(mktemp)
d1_1hr=$(date --date="-1 hour" '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u)

### last 4 hr
suffix="last4hr"
logfile_4hr=/tmp/apf.log.${suffix}
resultfile_4hr=$(mktemp)
d1_4hr=$(date --date="-4 hour" '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u)

### last 12 hr
suffix="last12hr"
logfile_12hr=/tmp/apf.log.${suffix}
resultfile_12hr=$(mktemp)
d1_12hr=$(date --date="-12 hour" '+%Y-%m-%d %H:%M:%S,%3N (UTC)' -u)

### prepare last15min
if [[ "${d_first}" < "$d1_15min" ]]; then
	cat ${logfile} | grep "Preparing to submit" | awk -v d1="$d1_15min" -v d2="$d2" '$0 > d1 && $0 < d2 || $0 ~ d2' > $logfile_15min 
else
	cat ${logfile}* | grep "Preparing to submit" | awk -v d1="$d1_15min" -v d2="$d2" '$0 > d1 && $0 < d2 || $0 ~ d2' > $logfile_15min 
fi

### prepare last1hr
if [[ "${d_first}" < "$d1_1hr" ]]; then
	cat ${logfile} | grep "Preparing to submit" | awk -v d1="$d1_1hr" -v d2="$d2" '$0 > d1 && $0 < d2 || $0 ~ d2' >$logfile_1hr
else
	cat ${logfile}* | grep "Preparing to submit" | awk -v d1="$d1_1hr" -v d2="$d2" '$0 > d1 && $0 < d2 || $0 ~ d2' >$logfile_1hr
fi

### prepare last4hr
if [[ "${d_first}" < "$d1_4hr" ]]; then
	cat ${logfile} | grep "Preparing to submit" | awk -v d1="$d1_4hr" -v d2="$d2" '$0 > d1 && $0 < d2 || $0 ~ d2' >$logfile_4hr
else
	cat ${logfile}* | grep "Preparing to submit" | awk -v d1="$d1_4hr" -v d2="$d2" '$0 > d1 && $0 < d2 || $0 ~ d2' >$logfile_4hr
fi

### prepare last12hr
if [[ "${d_first}" < "$d1_12hr" ]]; then
	cat ${logfile} | grep "Preparing to submit" | awk -v d1="$d1_12hr" -v d2="$d2" '$0 > d1 && $0 < d2 || $0 ~ d2' >$logfile_12hr
else
	cat ${logfile}* | grep "Preparing to submit" | awk -v d1="$d1_12hr" -v d2="$d2" '$0 > d1 && $0 < d2 || $0 ~ d2' >$logfile_12hr
fi


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


if ! curl -s -F file=@$tmpfile xsls.cern.ch >/dev/null ; then
  err "Error sending XML to xsls.cern.ch"
 exit 1
fi

rm -f $tmpfile $logfile_15min $resultfile_15min $logfile_1hr $resultfile_1hr $logfile_4hr $resultfile_4hr $logfile_12hr $resultfile_12hr 

### check validity
# xmllint --noout --schema http://itmon.web.cern.ch/itmon/files/xsls_schema.xsd $tmpfile
