## What is this?
This script is used to create a free VM in GCP and install Vaultwarden on it. Vaultwarden is an alternative implementation of the Bitwarden password manager. We take advantage of [this repository](https://github.com/dadatuputi/bitwarden_gcloud) to configure the VM and Vaultwarden.

Dynamic DNS and Backups are configured by default.

Only users from the configured domain can sign up and use Vaultwarden.

## How to run
1. Install the [gcloud CLI](https://dl.google.com/dl/cloudsdk/channels/rapid/GoogleCloudSDKInstaller.exe) locally(follow the instructions as seen in the provided link). The **Hermes admin** should authenticate using the admin account. If you didn't authenticate when installing gcloud, do it using `gcloud auth application-default login`.
2. Install terraform locally. Their official documentation can be found [here](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli).
   1. Download the right binary from [the install page](https://developer.hashicorp.com/terraform/install).
   2. Make sure the `terraform` binary is on your `PATH`. You can check how to do that in Windows by following [this link](https://stackoverflow.com/a/1618297).
3. Make sure the `Google Compute Engine` API is enabled in the project you want to use. The **Hermes admin** should use the default project they see when logging in. Also make sure the `Google Drive API` is enabled to be able to save backups to Google Drive.
4. Modify the `startup.sh` file to contain requried secrets that the **Hermes admin** should have access to.
   1. Replace "[DOMAIN]" with the domain that's set up in Cloudflare.
   2. Replace "[SUBDOMAIN]" with the subdomain that Vaultwarden will be running at. Should look like `subdomain.domain`.
   3. Replace "[EMAIL]" with the **Hermes admin** email.
   4. Replace "[CLOUDFLARE_API_KEY]" with the global Cloudflare API key you can find using the **Hermes admin** account.
   5. Replace "[BACKUP_FOLDER]" with the id of the Google Drive folder in which to store the backups. This is where the backups are stored for now: `11a_lKSAeo2VaCKHKcDBFt--zJrIeDS_3f`.
   6. Replace "[SERVICE_ACCOUNT_JSON]" with a service account key of the service account that is configured to have access to the Google Drive folder used. You should paste the whole JSON file there.
5. Run the following commands from this directory.
```bash
terraform init
terraform plan
```
6. If everything looks as it should, run a `terraform apply` as well.
7. You should be provided with the IP of the VM. Configure DNS to point your desired domain to it. The **Hermes admin** should do this in Cloudflare. **Make sure the Cloudflare proxy is off**. 
8. If vaultwarden isn't up in a few minutes, reboot the VM. I ran into some issues where caddy would be stuck on issuing a certificate, and this would be the easiest fix. Alternatively, things might work by adding CAA DNS records for sectigo.com and letsencrypt.org

## How to restore backups
Take the latest backup available (or any backup you like), and upload the files to the VM in the `gcloud_bitwarden/bitwarden` folder, replacing the existing ones. You should create a firewall rule to allow TCP:22 on the VM to be able to SSH into it through the GCP UI, and then upload the the backed up files using the provided terminal.

## Implementation details
We take advantage of Google Free tier products. You can have a free e2 instance for one month (every month) in GCP, and that's where we're storing Vaultwarden. The public IP is ephemereal, though, which is why `ddns` is used to update the Cloudlfare DNS configuration to point to the correct IP.

Our DNS provider is Cloudflare.

The **Hermes admin** account needs to be used for all of these operations, as most of the required information can be found by using it. 

We have Google Workspaces for Nonprofits which provides us with 100TB of Google Drive storage. Thanks to that, we configure the backups to be saved to a folder in Google Drive. The **Hermes admin** account has a `Backups/Vaultwarden` folder in which everything is stored, and that folder is shared with the `hermes-backups` service account, which is an editor on it. The `hermes-backups` service account is used to do the uploading, and you can generate a new key by going [here](https://console.cloud.google.com/iam-admin/serviceaccounts/) and choosing the `hermes-backups` service account. Domain-wide Delegation is used in the [admin console](admin.google.com) to give `hermes-backups` the necessary permissions to access Google Drives (https://www.googleapis.com/auth/drive). Also check the [rclone documentation](https://rclone.org/drive/).

## Files
- main.tf holds the actual terraform script
- startup.sh holds the script that runs every time the VM reboots
- README.md contains this description