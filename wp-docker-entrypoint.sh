#!/bin/bash
set -euo pipefail

echo >&2
echo >&2 "Your website is spinning up..."
# pause for 3 seconds while the DB container spins up
sleep 3

# Create initial WordPress directories
# and fix file permissions so that we can upload media
# and install plugins & themes
mkdir -p wp-content
chown www-data:www-data wp-content
mkdir -p wp-content/uploads
chown www-data:www-data wp-content/uploads
mkdir -p wp-content/themes
chown www-data:www-data wp-content/themes
mkdir -p wp-content/plugins
chown www-data:www-data wp-content/plugins

install_github_plugin() {
    echo >&2
    echo >&2 "Installing $1's $2 plugin";
    wp plugin install --allow-root https://github.com/$1/$2/archive/master.zip --activate
}

setup_dependencies() {
    echo >&2
    echo >&2 "Installing dependencies..."
    # Force the active theme to WP core while we install the PF Parent theme
    wp db query "UPDATE wp_options SET option_value = 'twentytwenty' WHERE option_name IN ('template', 'stylesheet');" --allow-root

    install_github_plugin afragen github-updater

    install_github_plugin mattras82 pf-wp-toolkit

    install_github_plugin mattras82 pf-cf7-extras

    install_github_plugin mattras82 contact-form-7-to-database-extension

    wp theme install --allow-root https://github.com/mattras82/pf-parent-theme/archive/master.zip

    wp plugin install --allow-root $PLUGINS_LIST

    # Now that our dependencies are installed, let's reactivate our site's theme
    wp theme activate $THEME_NAME --allow-root
}

pull_remote_db() {
    if [[ -v REMOTE_DB_PASSWORD && ! -z "$REMOTE_DB_PASSWORD" ]]; then
		echo >&2
		echo >&2 "Syncing local database from remote";
        wp db drop --allow-root --yes
		echo >&2
		echo >&2 "Pulling remote database now. Please be patient...";
		mysqldump -h $REMOTE_DB_HOST --user=$REMOTE_DB_USER --password=$REMOTE_DB_PASSWORD $REMOTE_DB_NAME > /tmp/dump.sql
		echo >&2
		echo >&2 "Remote database has been pulled. Recreating local DB now.";
		wp db create --allow-root
		wp db import /tmp/dump.sql --allow-root
        rm /tmp/dump.sql
		wp db query "UPDATE wp_options SET option_value = '$LOCAL_URL' WHERE option_name IN ('home', 'siteurl');" --allow-root
        echo >&2
        echo >&2 'Local DB synced from remote. Data is ready to roll';
    else
        echo >&2 'Could not import remote database';
        echo >&2;
        echo >&2 'Please add the REMOTE_DB_* environment variables in the .env file';
    fi
}

if [[ ! -e first_run ]]; then
    # This is the first time we're running this container.
    echo >&2
    echo >&2 "Looks like this is a fresh container!"
    echo >&2 "Pausing for 20 seconds so the database container can finish initializing"
    sleep 20
    echo >&2
    echo >&2 "Continuing on..."
    # Run the WordPress image's docker-entrypoint here
    # This will copy WP core files from /usr/src/wordpress into /var/www/html
    docker-entrypoint.sh apache2-blank
    # Pull the remote DB
    pull_remote_db
    # Install dependencies
    setup_dependencies
    # Create a file so we know it's been run before
    touch first_run
elif [[ "$REMOTE_DB_IMPORT" = "y" ]]; then
    pull_remote_db
else
    echo >&2
    echo >&2 "Skipping DB import"
fi

echo >&2
echo >&2 "Your website is ready to go at $LOCAL_URL"
echo >&2
echo >&2 "Happy Coding! :)"

# Run the apache2-foreground command
exec "$@"