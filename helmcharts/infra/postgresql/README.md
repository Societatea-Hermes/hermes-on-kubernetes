To restore backups, yo 


Backups are created by running pg_dump and then copying the file to google drive using rclone. Aditionlly, files older a certain amount of days are deleted. This works because we're using init containers, which run sequentially. Check the vaultwarden documentation in this repo for more details on what things mean.

