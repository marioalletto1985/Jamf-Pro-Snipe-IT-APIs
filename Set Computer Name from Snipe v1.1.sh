#!/bin/bash

# Mario Alletto for Zilch October 2025 rev 1.1
# Jamf Pro ↔ Snipe-IT Naming Sync — Mario Alletto (Zilch) • Oct 2025 • rev 1.1
# Reads Jamf Pro computer record by UDID and Snipe-IT hardware by serial, then:
# • If Snipe-IT asset_tag exists, sets local Computer Name to that tag; else falls back to serial.
# • Updates Jamf asset tag via `jamf recon` (keeps only tags starting Z00*/Z01*; otherwise clears).
# Inputs (Jamf policy params 4–7): $4 apiUser, $5 apiPass, $6 apiURL (no trailing /), $7 SNIPEIT_TOKEN.

set -x

# Jamf Parameters
apiUser="${4:-}"
apiPass="${5:-}"
apiURL="${6:-}"

# Jamf info
jamf=$(which jamf)

# Mac Info
macSerial=$(ioreg -d2 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformSerialNumber/{print $(NF-1)}')
udid=$(ioreg -d2 -c IOPlatformExpertDevice | awk -F\" '/IOPlatformUUID/{print $(NF-1)}')
computerRecord=$(curl -X GET --silent --output -k -u "$apiUser:$apiPass" -H "Accept:text/xml" "$apiURL/JSSResource/computers/udid/$udid")
name=$(echo $computerRecord | xmllint --xpath '/computer/general/name/text()' - )
asset=$(echo $computerRecord | xmllint --xpath '/computer/general/asset_tag/text()' - 2>/dev/null)
serial=$(echo $computerRecord | xmllint --xpath '/computer/general/serial_number/text()' - )

echo "Name = $name"
echo "Asset = $asset"
echo "Serial = $serial"

#Script to retrieve asset name from SnipeIT
TOKEN="${7:-}"
JSON=$(curl --silent --request GET --silent \
			--url "https://type-your-SnipeIT-url.snipe-it.io/api/v1/hardware/byserial/${macSerial}" \
			--header 'Accept: application/json' \
			--header "Authorization: Bearer $TOKEN" \
			)

snipeit_asset=$(echo "$JSON" | awk -F 'asset_tag\":' '{print$2}' | awk -F '"' '{$0=$2}1')

if [ ! -z "$snipeit_asset" ]; then
	echo "SnipeIT asset value found"
	if [ "$asset" != "$snipeit_asset" ]; then
		echo "Asset name not same"
		asset="$snipeit_asset"
		change="true"
	fi
fi


if [ -z "$asset" ]; then
	echo "Empty asset"
	if [ "$name" != "$macSerial" ]; then
		echo "Does not equal serial"
		echo "Set to serial"
		name="$macSerial"
		echo "New name = $name"
		change="true"
	else
		echo "Does equal serial"
		change="false"
		echo "Do nothing"
	fi
else
	if [ "$name" != "$asset" ]; then
		echo "Does not equal asset"
		echo "Set to asset"
		name="$asset"
		echo "New name = $name"
		change="true"
	else
		echo "Does equal asset"
		change="false"
		echo "Do nothing"
	fi
fi

if [ "$change" = "true" ]; then
	echo "Do local rename"
	"$jamf" setcomputername -name "$name"
fi

if [[ $asset = Z00* || $asset = Z01* ]]; then
	echo "Valid asset = $asset"
	"$jamf" recon -skipApps -skipFonts -skipPlugins -assetTag "$asset"
	
else
	echo "clear asset"
	"$jamf" recon -skipApps -skipFonts -skipPlugins -assetTag ""
fi



exit