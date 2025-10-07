🎯 Project Overview

This automation integrates Jamf Pro with Snipe-IT to streamline device provisioning and lifecycle management. The workflow automatically tags devices in Snipe-IT as soon as they’re enrolled in Jamf Pro, ensuring accurate asset tracking from the very first touchpoint.

⚙️ Key Features

Automated Device Tagging:
Upon enrollment in Jamf Pro, each device is instantly matched and tagged in Snipe-IT via REST API calls — no manual input required.

Deployment Status Updates:
Devices are automatically marked as Deployed in Snipe-IT once assigned to an end user, keeping inventory records always up-to-date.

Real-Time Slack Notifications:
A Slack webhook posts a customized message whenever a device is allocated to a user — providing immediate visibility for IT and operations teams.

API-Driven Efficiency:
The entire process is powered by API automation, ensuring reliability, speed, and seamless synchronization across systems.

🧠 Tech Stack

Jamf Pro API (for device enrollment and management data)

Snipe-IT API (for asset tagging and status updates)

Slack Webhooks (for real-time notifications)

Bash (for automation scripting)

💡 Impact

This integration eliminates repetitive manual work, reduces data discrepancies between Jamf and Snipe-IT, and improves team awareness through proactive Slack alerts — delivering a fully automated and transparent device deployment pipeline.
