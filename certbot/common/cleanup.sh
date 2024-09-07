#!/bin/bash
# NameSileCertbot-DNS-01 0.2.2
## https://stackoverflow.com/questions/59895
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE"  ]; do
  DIR="$( cd -P "$( dirname "$SOURCE"  )" && pwd  )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /*  ]] && SOURCE="$DIR/$SOURCE"
done
DIR="$( cd -P "$( dirname "$SOURCE"  )" && pwd  )"
echo "  Certbot: Received request for" "${CERTBOT_DOMAIN}"
cd ${DIR}
source config.sh

DOMAIN=${CERTBOT_DOMAIN}

## Get current list (updating may alter rrid, etc)
curl -s "https://www.namesilo.com/api/dnsListRecords?version=1&type=xml&key=$APIKEY&domain=$DOMAIN" > $CACHE$DOMAIN.xml

## Check for existing ACME record
if grep -q "_acme-challenge" $CACHE$DOMAIN.xml ; then

	## Get record ID - possible to have many here
	RECORD_IDs=(`xmllint --xpath "//namesilo/reply/resource_record/record_id[../host/text() = '_acme-challenge.$DOMAIN' ]" $CACHE$DOMAIN.xml | grep -oP '(?<=<record_id>)([a-f0-9]+)(?=</record_id>)'`)

	## Iterate through all of them and recursively deleting.
	for RECORD_ID in ${RECORD_IDs[@]}; do
		## Update DNS record in Namesilo:
		curl -s "https://www.namesilo.com/api/dnsDeleteRecord?version=1&type=xml&key=$APIKEY&domain=$DOMAIN&rrid=$RECORD_ID" > $RESPONSE
		RESPONSE_CODE=`xmllint --xpath "//namesilo/reply/code/text()"  $RESPONSE`
		## Process response, maybe wait

		case $RESPONSE_CODE in
			300)
				echo "  Certbot: ACME challenge record successfully removed."
				;;
			280)
				RESPONSE_DETAIL=`xmllint --xpath "//namesilo/reply/detail/text()"  $RESPONSE`
				echo "Record removal failed."
				echo "Namesilo returned code: $RESPONSE_CODE"
				echo "reason: $RESPONSE_DETAIL"
				echo "Domain: $DOMAIN"
				echo "rrid: $RECORD_ID"
				;;
			*)
				RESPONSE_DETAIL=`xmllint --xpath "//namesilo/reply/detail/text()"  $RESPONSE`
				echo "Namesilo returned code: $RESPONSE_CODE"
				echo "Reason: $RESPONSE_DETAIL"
				echo "Domain: $DOMAIN"
				echo "rrid: $RECORD_ID"
				;;
		esac
	done
fi

## Self Cleanup
if [ -f $RESPONSE ] ; then
	rm $RESPONSE
fi
if [ -f $CACHE$DOMAIN.xml ] ; then
	rm $CACHE$DOMAIN.xml
fi