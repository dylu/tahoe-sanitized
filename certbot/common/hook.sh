#!/bin/bash
## modified dlu
## References: NameSileCertbot-DNS-01 0.2.2
## https://stackoverflow.com/questions/59895
echo "[$(date +'%Y_%m_%d')] - " "Certbot: Starting hook.sh"
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE"  ]; do
  DIR="$( cd -P "$( dirname "$SOURCE"  )" && pwd  )"
  SOURCE="$(readlink "$SOURCE")"
  [[ $SOURCE != /*  ]] && SOURCE="$DIR/$SOURCE"
done
DIR="$( cd -P "$( dirname "$SOURCE"  )" && pwd  )"
echo "  Certbot: Received request for" "${CERTBOT_DOMAIN}" ", with Validation " "${CERTBOT_VALIDATION}"
cd ${DIR}
source config.sh

DOMAIN=${CERTBOT_DOMAIN}
VALIDATION=${CERTBOT_VALIDATION}

## Add the record
echo "  Certbot: Executing dnsAddRecord API call."
curl -s "https://www.namesilo.com/api/dnsAddRecord?version=1&type=xml&key=$APIKEY&domain=$DOMAIN&rrtype=TXT&rrhost=_acme-challenge&rrvalue=$VALIDATION&rrttl=3600" > $RESPONSE
RESPONSE_CODE=`xmllint --xpath "//namesilo/reply/code/text()"  $RESPONSE`

## Process response, maybe wait
case $RESPONSE_CODE in
	300)
		echo "  Certbot: Add Record Success."
		# Only wait if this is the final challenge to add.
		if (( ${CERTBOT_REMAINING_CHALLENGES} == 0 ))
		then
			echo "  Certbot: Final record added; please wait ~25 minutes for validation..."
			# NameSilo records are published every 15 minutes. Waiting 25 minutes before proceeding.
			for (( i=0; i<25; i++ )); do
				echo "   | waiting.. min" ${i}
				sleep 60s
			done
		fi
		;;
	280)
		RESPONSE_DETAIL=`xmllint --xpath "//namesilo/reply/detail/text()"  $RESPONSE`
		echo "DNS add_record aborted, please check your NameSilo account."
		echo "NameSilo returned code: $RESPONSE_CODE"
		echo "Reason: $RESPONSE_DETAIL"
		echo "Domain: $DOMAIN"
		echo "rrid: $RECORD_ID"
		;;
	*)
		RESPONSE_DETAIL=`xmllint --xpath "//namesilo/reply/detail/text()"  $RESPONSE`
		echo "NameSilo returned code: $RESPONSE_CODE"
		echo "Reason: $RESPONSE_DETAIL"
		echo "Domain: $DOMAIN"
		echo "rrid: $RECORD_ID"
		;;
esac
