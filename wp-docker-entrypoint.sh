#!/usr/bin/env bash
set -Eeuo pipefail

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
# Creating WPCF7 file upload temp directory 
# with needed permissions
mkdir -p /var/www/temp
chown www-data:www-data /var/www/temp
# Creating WordFence logs directory
# with needed permissions
mkdir -p wp-content/wflogs
chown -R www-data:www-data wp-content/wflogs

setup_local_url() {
    if [[ "$LOCAL_PORT" = "80" ]]; then
        echo "$LOCAL_URL";
    else
        echo "$LOCAL_URL:$LOCAL_PORT";
    fi
}

url=$(setup_local_url)

update_url_in_db() {
    wp db query "UPDATE ${WORDPRESS_TABLE_PREFIX}options SET option_value = '$url' WHERE option_name IN ('home', 'siteurl');" --allow-root
}

update_theme_in_db() {
    wp db query "UPDATE ${WORDPRESS_TABLE_PREFIX}options SET option_value = 'twentytwentyfour' WHERE option_name IN ('template', 'stylesheet');" --allow-root
    wp theme activate --allow-root $THEME_NAME
}

install_github_plugin() {
    echo >&2
    echo >&2 "Installing $1's $2 plugin";
    wp plugin install --allow-root https://github.com/$1/$2/archive/master.zip --activate
}

setup_dependencies() {
    echo >&2
    echo >&2 "Installing dependencies..."
    # Force the active theme to WP core while we install the PF Parent theme
    wp db query "UPDATE ${WORDPRESS_TABLE_PREFIX}options SET option_value = 'twentytwentyfour' WHERE option_name IN ('template', 'stylesheet');" --allow-root

    # Remove unneeded default plugins
    wp plugin delete --allow-root akismet hello

    install_github_plugin mattras82 pf-wp-toolkit

    install_github_plugin mattras82 pf-cf7-extras

    install_github_plugin mattras82 contact-form-7-to-database-extension

    wp theme install --allow-root https://github.com/mattras82/pf-parent-theme/archive/master.zip

    chown -R www-data:www-data /var/www/html/wp-content/plugins

    wp plugin install --allow-root --activate $PLUGINS_LIST

    chown -R www-data:www-data /var/www/html/wp-content/themes

    # Now that our dependencies are installed, let's reactivate our site's theme
    wp theme activate $THEME_NAME --allow-root

    echo >&2
    echo >&2 "Initial dependencies installed successfully"
}

restore_db_from_dump() {
    echo >&2
    echo >&2 "Restoring database from local dump file: $DB_DUMP_FILE";
    wp db drop --allow-root --yes
    wp db create --allow-root
    wp db import $DB_DUMP_FILE --allow-root
    update_url_in_db
    echo >&2
    echo >&2 'Local DB restored from dump file. Data is ready to roll';
}

pull_remote_db() {
    if [[ -v REMOTE_DB_PASSWORD && ! -z "$REMOTE_DB_PASSWORD" ]]; then
		echo >&2
		echo >&2 "Syncing local database from remote";
		echo >&2
		echo >&2 "Pulling remote database now. Please be patient...";
        if [[ -v REMOTE_DB_EXTRAS && ! -z "$REMOTE_DB_EXTRAS" ]]; then
		    mysqldump -h $REMOTE_DB_HOST --no-tablespaces --user=$REMOTE_DB_USER --password=$REMOTE_DB_PASSWORD $REMOTE_DB_NAME $REMOTE_DB_EXTRAS > /tmp/dump.sql
        else
            mysqldump -h $REMOTE_DB_HOST --no-tablespaces --user=$REMOTE_DB_USER --password=$REMOTE_DB_PASSWORD $REMOTE_DB_NAME > /tmp/dump.sql
        fi
        wp db drop --allow-root --yes
		echo >&2
		echo >&2 "Remote database has been pulled. Recreating local DB now.";
		wp db create --allow-root
		wp db import /tmp/dump.sql --allow-root
        rm /tmp/dump.sql
		update_url_in_db
        echo >&2
        echo >&2 'Local DB synced from remote. Data is ready to roll';
    else
        echo >&2 'Could not import remote database';
        echo >&2;
        echo >&2 'Please add the REMOTE_DB_* environment variables in the .env file';
    fi
}

setup_xdebug_ini() {
    echo "xdebug.mode=${XDEBUG_MODE}" >> php.ini;
    echo "xdebug.start_with_request=${XDEBUG_START_WITH_REQUEST}" >> php.ini;
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
    # If we have a remote DB to pull from, then we'll get everything set up.
    # Otherwise, we'll bypass so we can let WP Core init the database
    if [[ -v DB_DUMP_FILE && ! -z "$DB_DUMP_FILE" ]]; then
        restore_db_from_dump
        setup_dependencies
    elif [[ -v REMOTE_DB_PASSWORD && ! -z "$REMOTE_DB_PASSWORD" ]]; then
        # Pull the remote DB
        pull_remote_db
        # Install dependencies
        setup_dependencies
    else
        echo >&2
        echo >&2 "Skipping database & plugin setup."
    fi
    # Setup php.ini file so that Xdebug works properly
    setup_xdebug_ini
    # Create a file so we know it's been run before
    touch first_run
elif [[ "$REMOTE_DB_IMPORT" = "y" || "$REMOTE_DB_IMPORT" = "Y" ]]; then
    pull_remote_db
    # Fix for remote site not using the same theme as local
    update_theme_in_db
elif [[ -v DEPENDENCY_SETUP && "$DEPENDENCY_SETUP" = "Y" ]]; then
    setup_dependencies
elif [[ -v DB_DUMP_FILE && ! -z "$DB_DUMP_FILE" ]]; then
    restore_db_from_dump
else
    echo >&2
    echo >&2 "Skipping DB import"
    update_url_in_db
fi

echo >&2
echo >&2 "Your website is ready to go at $url"
echo >&2
echo >&2 "Happy Coding! :)"

# Run the apache2-foreground command
exec "$@"