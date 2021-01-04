FROM wordpress:latest

# Install dependencies like Redis, XDebug, and WP-CLI
RUN a2enmod rewrite
RUN docker-php-ext-install pdo pdo_mysql mysqli
RUN apt-get update && apt-get install -y nano mariadb-client

RUN pecl install igbinary
RUN pecl install -o -f redis \
  && docker-php-ext-enable redis

RUN yes | pecl install xdebug \
  && echo "zend_extension=$(find /usr/local/lib/php/extensions/ -name xdebug.so)" >> /usr/local/etc/php/conf.d/xdebug.ini

RUN curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar; \
	chmod +x wp-cli.phar; \
	mv wp-cli.phar /usr/local/bin/wp

COPY wp-docker-entrypoint.sh /usr/local/bin/
COPY apache2-blank /usr/local/bin/

WORKDIR /var/www/html

ENTRYPOINT ["wp-docker-entrypoint.sh"]
CMD ["apache2-foreground"]