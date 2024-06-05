#!/bin/bash

# this is the repository that contains the scripts for setting up Vaultwarden on Google Cloud
git clone https://github.com/dadatuputi/bitwarden_gcloud.git
cd bitwarden_gcloud

sh utilities/install-alias.sh
source ~/.bashrc

# here we set up variables that will be used for configuring Vaultwarden
# check the README.md for more information on how to get these values
export VAR_DOMAIN=[DOMAIN]
export VAR_SUBDOMAIN=[SUBDOMAIN]
export VAR_EMAIL=[EMAIL]
export VAR_CLOUDFLARE_API_KEY=[CLOUDFLARE_API_KEY]
export VAR_BACKUP_FOLDER=[BACKUP_FOLDER]

# edit the docker-compose file to include extra environment variables
# we use yq to edit the file, which is a nice yaml parser
# we don't install it, because we only use it once
docker run --user="$(id -u)" --rm -v "${PWD}:/workdir" mikefarah/yq -i '.services.bitwarden.environment += "SIGNUPS_DOMAINS_WHITELIST"' docker-compose.yml

# set up the environment variables according to our own preferences
cat > .env <<EOF
DOMAIN=$VAR_DOMAIN
TZ=Europe/Bucharest

SIGNUPS_ALLOWED=false
ORG_CREATION_USERS=$VAR_EMAIL
SIGNUPS_DOMAINS_WHITELIST=$VAR_DOMAIN


BACKUP=rclone
BACKUP_SCHEDULE=0 0 * * *
BACKUP_DAYS=365
BACKUP_DIR=/data/backups
BACKUP_ENV=false
BACKUP_RCLONE_CONF=/data/rclone/rclone.conf
BACKUP_RCLONE_DEST=/bw_backup

EMAIL=$VAR_EMAIL

PUID=$(id -u)
PGID=$(id -g)

COUNTRIES=CN HK AU
COUNTRYBLOCK_SCHEDULE=0 0 * * *

WATCHTOWER_SCHEDULE=0 0 3 ? * 0
EOF

# set up ddns because of the ephemereal nature of the IP address
cat > ddns/ddclient.conf <<EOF
use=web, web=checkip.dyndns.org/, web-skip='IP Address'
protocol=cloudflare
zone=$VAR_DOMAIN
ttl=0
login=$EMAIL
password=$VAR_CLOUDFLARE_API_KEY
$VAR_SUBDOMAIN
EOF

# set up rclone to backup the data to Google Drive
cat > rclone/rclone.conf <<EOF
[remote]
client_id =
client_secret =
scope = drive
root_folder_id = $VAR_BACKUP_FOLDER
service_account_file = rclone/key.json
EOF

# set up the service account used for rclone
cat > rclone/key.json <<EOF
[SERVICE_ACCOUNT_JSON]
EOF


docker-compose up
