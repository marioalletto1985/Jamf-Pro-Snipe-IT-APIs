#!/bin/bash

#############
# Written by Mario Alletto - October 2025
# Automates Snipe-IT checkout via API: assigns the asset to the last logged-in user (excluding jamfadmin, macadmin, 
# sets its status to “Deployed”, and posts a detailed Slack message with system info and location flag.
#############

# Jamf Parameters info
#$4 Slack webhookURL
#$5 Snipe-IT API_URL (e.g., https://snipe.company.io/api/v1)
#$6 Snipe-IT API TOKEN

# Jamf Parameters
webhookURL="${4:-}"
API_URL="${5:-}"
TOKEN="${6:-}"

# Function to get the country code from IP and return a Slack-compatible emoji
function getCountryCode() {
	countryCode=$(curl -s https://ipinfo.io/country)
	
	case "$countryCode" in
		"GB") countryFlag=":flag-gb: UK" ;;   # Slack-compatible emoji
		"PL") countryFlag=":flag-pl: Poland" ;;
		*) countryFlag=":earth_africa: Other ($countryCode)" ;; # Default for other countries
	esac
	
	echo "$countryFlag"
}


# Function to send Slack Webhook messages
function webHookMessage() {
	local webhookStatus="$1"
	local errorMessage="$2"
	
	# Get system details
	serialNumber=$(system_profiler SPHardwareDataType | awk '/Serial Number/{print $NF}')
	timestamp=$(date "+%Y-%m-%d %H:%M:%S")
	loggedInUser=$USERNAME
	osVersion=$(sw_vers -productVersion)
	osBuild=$(sw_vers -buildVersion)
	countryFlag=$(getCountryCode)  # Get the country code
	
	
	# Determine message type
	if [ "$webhookStatus" == "success" ]; then
		slackMessage="✅ *MacBook Checkout Successful*"
	else
		slackMessage="❌ *MacBook Checkout Failed: $errorMessage*"
	fi
	
	# Slack message payload
	webHookdata=$(cat <<EOF
{
	"blocks": [
		{
			"type": "section",
			"text": {
				"type": "mrkdwn",
				"text": "${slackMessage}"
			}
		},
		{
			"type": "section",
			"fields": [
				{ "type": "mrkdwn", "text": "*Computer Name:*\n${HOSTNAME}" },
				{ "type": "mrkdwn", "text": "*Serial Number:*\n${serialNumber}" },
				{ "type": "mrkdwn", "text": "*Timestamp:*\n${timestamp}" },
				{ "type": "mrkdwn", "text": "*User:*\n${loggedInUser}" },
				{ "type": "mrkdwn", "text": "*OS Version:*\n${osVersion} (${osBuild})" },
				{ "type": "mrkdwn", "text": "*Country Code:*\n${countryFlag}" }
			]
		}
	]
}
EOF
)
	
	# Debugging output before sending
	echo "Sending Slack Webhook Payload: $webHookdata"
	
	# Send the message to Slack
	curl_response=$(curl -s -X POST -H 'Content-type: application/json' --data "$webHookdata" "$webhookURL")
	echo "Slack Response: $curl_response"
}

# Define variables for ignored users
declare -a ignoredusers=("jamfadmin" "macadmin")
if [ -n "$1" ]; then
	ignoredusers=($1)
fi

echo "Ignore list: ${ignoredusers[@]}"

# Get the last logged-in user
USERNAME=$(defaults read /Library/Preferences/com.apple.loginwindow.plist lastUserName 2>/dev/null)
if [ -z "$USERNAME" ]; then
	echo "Error: Could not determine the last user. Exiting."
	exit 1
fi

echo "Last logged-in user: $USERNAME"

# Check if the user is on the ignore list
for ignored in "${ignoredusers[@]}"; do
	if [ "$USERNAME" == "$ignored" ]; then
		echo "User $USERNAME is on the ignore list. Exiting."
		exit 0
	fi
done

# Get the hostname
HOSTNAME=$(scutil --get ComputerName)
if [ -z "$HOSTNAME" ]; then
	echo "Error: Could not determine the hostname. Exiting."
	exit 1
fi

echo "Hostname: $HOSTNAME"

# Fetch the asset ID using the hostname
ASSET_ID=$(curl --silent --request GET \
	--url "$API_URL/hardware?search=$HOSTNAME" \
	--header "Authorization: Bearer $TOKEN" \
	--header 'accept: application/json' | jq -r '.rows[0].id')

if [ -z "$ASSET_ID" ] || [ "$ASSET_ID" == "null" ]; then
	echo "Error: Could not retrieve asset ID for hostname $HOSTNAME. Exiting."
	exit 1
fi

echo "Asset ID for $HOSTNAME: $ASSET_ID"

# Fetch the user ID from Snipe-IT based on the username
USER_ID=$(curl --silent --request GET \
	--url "$API_URL/users?search=$USERNAME" \
	--header "Authorization: Bearer $TOKEN" \
	--header 'accept: application/json' | jq -r '.rows[0].id')

if [ -z "$USER_ID" ] || [ "$USER_ID" == "null" ]; then
	echo "Error: Could not retrieve user ID for username $USERNAME. Exiting."
	exit 1
fi

echo "User ID for $USERNAME: $USER_ID"

# Perform the API call to checkout the hardware
response=$(curl --silent --write-out "\nHTTP_STATUS:%{http_code}" --request POST \
--url "$API_URL/hardware/$ASSET_ID/checkout" \
--header "Authorization: Bearer $TOKEN" \
--header 'accept: application/json' \
--header 'content-type: application/json' \
--data "{ \"checkout_to_type\": \"user\", \"assigned_user\": $USER_ID }")

# Parse the response
HTTP_STATUS=$(echo "$response" | tail -n 1 | sed -e 's/HTTP_STATUS://')
BODY=$(echo "$response" | sed '$ d')

echo "HTTP Status: $HTTP_STATUS"
echo "Response Body: $BODY"

# Check for errors in the response body
STATUS=$(echo "$BODY" | jq -r '.status')
ERROR_MESSAGE=$(echo "$BODY" | jq -r '.messages')

if [ "$HTTP_STATUS" -eq 200 ] && [ "$STATUS" == "success" ]; then
	echo "Checkout successful."
	webHookMessage "success"
	
	# --- Get ID for 'Deployed' status label ---
	echo "Fetching status ID for 'Deployed'..."
	DEPLOYED_STATUS_ID=$(curl --silent --request GET \
		--url "$API_URL/statuslabels?search=deployed" \
		--header "Authorization: Bearer $TOKEN" \
		--header 'accept: application/json' | jq -r '.rows[] | select(.name=="Deployed") | .id')
			
			if [ -z "$DEPLOYED_STATUS_ID" ] || [ "$DEPLOYED_STATUS_ID" == "null" ]; then
				echo "Warning: Could not retrieve 'Deployed' status label ID. Skipping status update."
			else
				echo "Updating asset status to 'Deployed' (ID: $DEPLOYED_STATUS_ID)..."
				curl --silent --request PUT \
				--url "$API_URL/hardware/$ASSET_ID" \
				--header "Authorization: Bearer $TOKEN" \
				--header 'accept: application/json' \
				--header 'content-type: application/json' \
				--data "{\"status_id\": $DEPLOYED_STATUS_ID}"
			fi
			
			else
			echo "Checkout failed with status $HTTP_STATUS."
			echo "Error details: $ERROR_MESSAGE"
			webHookMessage "failure" "$ERROR_MESSAGE"
			exit 1
			fi