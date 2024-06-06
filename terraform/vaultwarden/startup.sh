#!/bin/bash

# this is used to make docker compose work
function docker-compose() {
    docker run --rm \
        -v /var/run/docker.sock:/var/run/docker.sock \
        -v "$PWD:$PWD" \
        -w="$PWD" \
        docker/compose "$@"
}

if [ -e /home/vaultwarden/bitwarden_gcloud ]; then
    cd /home/vaultwarden/bitwarden_gcloud
    # clean up existing containers to reload configuration
    docker-compose down
else
    mkdir /home/vaultwarden
    cd /home/vaultwarden

    # this is the repository that contains the scripts for setting up Vaultwarden on Google Cloud
    git clone https://github.com/dadatuputi/bitwarden_gcloud.git
    git checkout tags/v2.0.2
    cd bitwarden_gcloud

    # edit the docker-compose file to include extra environment variables
    # we use yq to edit the file, which is a nice yaml parser
    # we don't install it, because we only use it once
    docker run --user="$(id -u)" --rm -v "${PWD}:/workdir" mikefarah/yq -i '.services.bitwarden.environment += "SIGNUPS_DOMAINS_WHITELIST"' docker-compose.yml
fi


# here we set up variables that will be used for configuring Vaultwarden
# check the README.md for more information on how to get these values
export VAR_DOMAIN='[DOMAIN]'
export VAR_SUBDOMAIN='[SUBDOMAIN]'
export VAR_EMAIL='[EMAIL]'
export VAR_CLOUDFLARE_API_KEY='[CLOUDFLARE_API_KEY]'
export VAR_BACKUP_FOLDER='[BACKUP_FOLDER]'


# set up the environment variables according to our own preferences
cat > .env <<EOF
DOMAIN=$VAR_SUBDOMAIN
TZ=Europe/Bucharest

SIGNUPS_ALLOWED=false
ORG_CREATION_USERS=$VAR_EMAIL
SIGNUPS_DOMAINS_WHITELIST=$VAR_DOMAIN


BACKUP=rclone
BACKUP_SCHEDULE=0 0 * * *
BACKUP_DAYS=365
BACKUP_DIR=/data/backups
BACKUP_ENV=false
BACKUP_RCLONE_CONF=/data/rclone.conf

EMAIL=$VAR_EMAIL

PUID=$(id -u)
PGID=$(id -g)

COUNTRIES=CN HK AU
COUNTRYBLOCK_SCHEDULE=0 0 * * *

WATCHTOWER_SCHEDULE=0 0 3 ? * 0
EOF

# set up rclone to backup the data to Google Drive
cat > bitwarden/rclone.conf <<EOF
[remote]
type=drive
client_id =
client_secret =
scope = drive
root_folder_id = $VAR_BACKUP_FOLDER
service_account_file = /data/key.json
EOF

# set up the service account used for rclone
cat > bitwarden/key.json <<EOF
[SERVICE_ACCOUNT_KEY_JSON]
EOF

# set up ddns because of the ephemereal nature of the IP address
cat > ddns/ddclient.conf <<EOF
daemon=600
syslog=yes
pid=/var/run/ddclient/ddclient.pid
use=web, web=checkip.dyndns.org/, web-skip='IP Address'
protocol=cloudflare
zone=$VAR_DOMAIN
ttl=0
login=$VAR_EMAIL
password=$VAR_CLOUDFLARE_API_KEY
$VAR_SUBDOMAIN
EOF

docker-compose up