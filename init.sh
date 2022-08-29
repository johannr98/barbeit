 #!/bin/bash         
 apt update
 apt upgrade

#install password gen  

apt install vim
apt install pwgen
apt install software-properties-common && echo | add-apt-repository ppa:ondrej/php -y
apt update
# install php 8.1
#apt install --no-install-recommends php8.1
yes | apt install php8.1-{bcmath,common,curl,fpm,gd,intl,mbstring,mysql,soap,xml,xsl,zip,cli}

# install apache
yes | apt install apache2

USER_POSTFIX=User
PASSPHRASE=$(pwgen -s -y 12)

PHP_VERSION=8.1
MARIADB_VERSION=10.4


yes|apt install software-properties-common
curl -o /etc/apt/trusted.gpg.d/mariadb_release_signing_key.asc 'https://mariadb.org/mariadb_release_signing_key.asc'
sh -c "echo 'deb https://mirror.kumi.systems/mariadb/repo/10.4/ubuntu focal main' >>/etc/apt/sources.list"
yes|apt-get update
yes|apt-get install mariadb-server


source /run/one-context/one_env

if [ "$INSTALL_SHOPWARE" = "YES" ]; then

SHOPWARE_USER=Shopware$USER_POSTFIX

echo "CREATE DATABASE shopware;
CREATE USER '${SHOPWARE_USER}' IDENTIFIED BY '${PASSPHRASE}';
GRANT ALL PRIVILEGES ON shopware.* TO '${SHOPWARE_USER}';"

cd /var/www/html
sudo rm index.nginx-debian.html
sudo wget https://releases.shopware.com/sw6/install_6.2.0_1589874223.zip
sudo unzip install_6.2.0_1589874223.zip
sudo rm install_6.2.0_1589874223.zip
sudo chown -R www-data:www-data .

fi

if [ "$INSTALL_SHOPWARE" = "NO" ]; then
MAGENTO_ADMIN_USERNAME="Magento$USER_POSTFIX"
MAGENTO_ADMIN_EMAIL=admin@admin.com
MAGENTO_ADMIN_PASSWORD=$PASSPHRASE

# Database
MAGENTO_DATABASE=magento 
MAGENTO_DATABASE_USERNAME="Magento$USER_POSTFIX"
MAGENTO_DATABASE_PASSWORD=$PASSPHRASE

SITE_NAME=mydomain # Site domain
BASE_URL=http://mydomain.com

# For ftp
MAGENTO_SYSTEM_USER=Magento$USER_POSTFIX
MAGENTO_SYSTEM_PASSWORD=$PASSPHRASE

#Elasticsearch
ELASTICSEARCH_HOST=localhost
ELASTICSEARCH_PORT=8080
MAGENTO_VERSION=2.4.2
ELASTICSEARCH_VERSION=7.16.0

OPTS=`getopt -o "" --long magento-username:,magento-email:,magento-password:,database:,database-user:,database-password:,site-name:,base-url:,system-user:,system-password:,elasticsearch-host:,elasticsearch-port: -- "$@"`
eval set -- "$OPTS"

while true ; do
	case "$1" in
		--magento-username)
			MAGENTO_ADMIN_USERNAME=$2 ; shift 2 ;;
			--magento-email)
			MAGENTO_ADMIN_EMAIL=$2 ; shift 2 ;;
			--magento-password)
			MAGENTO_ADMIN_PASSWORD=$2 ; shift 2;;
		--database)
			MAGENTO_DATABASE=$2 ; shift 2;;
		--database-user)
			MAGENTO_DATABASE_USERNAME=$2 ; shift 2;;
		--database-password)
			MAGENTO_DATABASE_PASSWORD=$2 ; shift 2;;
		--site-name)
			SITE_NAME=$2 ; shift 2;;
		--base-url)
			BASE_URL=$2 ; shift 2;;
		--system-user)
			MAGENTO_SYSTEM_USER=$2 ; shift 2;;	
		--system-password)
			MAGENTO_SYSTEM_PASSWORD=$2 ; shift 2;;
			--elasticsearch-host)
		ELASTICSEARCH_HOST=$2 ; shift 2;;
			--elasticsearch-port)
		ELASTICSEARCH_PORT=$2 ; shift 2;;

		--) shift ; break ;;
		*) echo "Error" ; exit 1 ;;
	esac
done


# MAGENTO_DIR=/var/www/html/${SITE_NAME}
MAGENTO_DIR=/home/${MAGENTO_SYSTEM_USER}/${SITE_NAME}


apt-get update -q

apt-get install -yq \
	apt-transport-https \
	openjdk-8-jdk \
	libapache2-mod-php${PHP_VERSION} \
	php${PHP_VERSION}-mysql 


wget -qO - https://artifacts.elastic.co/GPG-KEY-elasticsearch | apt-key add -

echo "deb https://artifacts.elastic.co/packages/7.x/apt stable main" | tee /etc/apt/sources.list.d/elastic-7.x.list

apt-get update && apt-get install -yq elasticsearch=${ELASTICSEARCH_VERSION}

systemctl enable --now elasticsearch
systemctl start elasticsearch

#install composer

apt install composer

echo "CREATE DATABASE ${MAGENTO_DATABASE};
CREATE USER '${MAGENTO_DATABASE_USERNAME}'@'localhost' IDENTIFIED BY '${MAGENTO_DATABASE_PASSWORD}';
ALTER USER '${MAGENTO_DATABASE_USERNAME}'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MAGENTO_DATABASE_PASSWORD}';
GRANT ALL PRIVILEGES ON *.* TO '${MAGENTO_DATABASE_USERNAME}'@'localhost' WITH GRANT OPTION;" | mysql -u root

sed "s+MAGENTO_HOME_DIR+/home/${MAGENTO_SYSTEM_USER}+g" apache2.conf > /etc/apache2/apache2.conf
a2dissite 000-default
a2ensite ${SITE_NAME}
a2enmod proxy_http rewrite
systemctl reload apache2
useradd -m -p $(openssl passwd -1 ${MAGENTO_SYSTEM_PASSWORD}) -s /bin/bash ${MAGENTO_SYSTEM_USER}
usermod -a -G www-data ${MAGENTO_SYSTEM_USER}


sudo -H -u ${MAGENTO_SYSTEM_USER} bash <<"EOF"
cd
mkdir -p ~/.config/composer
echo '{
	"http-basic": {
		"repo.magento.com": {
			"username": "418ecc0daef3f3081d36224fce2ed2cd",
			"password": "d4b572998c3cad1beed8a4f0d3f9fa84"
		}
	}
}' | tee ~/.config/composer/auth.json
EOF
rm -rf ${MAGENTO_DIR}
MAGENTO_DIR=${MAGENTO_DIR} MAGENTO_VERSION=${MAGENTO_VERSION} -H -u ${MAGENTO_SYSTEM_USER} bash <<"EOF"
cd
composer create-project --repository-url=https://repo.magento.com/ magento/project-community-edition=${MAGENTO_VERSION} ${MAGENTO_DIR}
EOF

sudo -H -u ${MAGENTO_SYSTEM_USER} bash -c "cd ${MAGENTO_DIR}; bin/magento setup:install \
--base-url=${BASE_URL} \
--db-host=localhost \
--db-name=${MAGENTO_DATABASE} \
--db-user=${MAGENTO_DATABASE_USERNAME} \
--db-password=${MAGENTO_DATABASE_PASSWORD} \
--admin-firstname=Admin \
--admin-lastname=Admin \
--admin-email=${MAGENTO_ADMIN_EMAIL} \
--admin-user=${MAGENTO_ADMIN_USERNAME} \
--admin-password=${MAGENTO_ADMIN_PASSWORD} \
--language=en_US \
--currency=EUR \
--timezone=Germany/Berlin \
--elasticsearch-host=${ELASTICSEARCH_HOST} \
--elasticsearch-port=${ELASTICSEARCH_PORT} \
--use-rewrites=1"

MAGENTO_DIR=${MAGENTO_DIR} -H -u ${MAGENTO_SYSTEM_USER} bash <<"EOF"
cd ${MAGENTO_DIR}
find var generated vendor pub/static pub/media app/etc -type f -exec chmod g+w {} +
find var generated vendor pub/static pub/media app/etc -type d -exec chmod g+ws {} +
EOF

chown -R ${MAGENTO_SYSTEM_USER}:www-data ${MAGENTO_DIR}
sudo -H -u ${MAGENTO_SYSTEM_USER} bash -c "cd ${MAGENTO_DIR}; php bin/magento module:disable Magento_TwoFactorAuth; bin/magento cron:install"
fi


UBUNTU=Ubuntu$USER_POSTFIX

su -c "useradd $UBUNTU -s /bin/bash -m -g sudo"

chpasswd << 'END'
mynewuser:$PASSPHRASE
END

systemctl restart apache2
systemctl enable --now apache2

yes | apt install ssmtp
sed -i "s/root=postmaster/SERVER=your@mail.server.com\nAuthUser=your@mail.com\nAuthPass=\YourPassword\nUseTLS=YES\nUseSTARTTLS=YES/" /etc/ssmtp/ssmtp.conf
sed -i "s/mailhub=mail/mailhub=smtp.mail.com:587/" /etc/ssmtp/ssmtp.conf
sed -i "s/#rewriteDomain=/rewriteDomain=mail.com/" /etc/ssmtp/ssmtp.conf

source /run/one-context/one_env
ssmtp yourMail@mail.com "passphrase:$PASSPHRASE\nUbuntuNutzer:$UBUNTU\nNutzerMagentoSystem:$MAGENTO_ADMIN_USERNAME\nIP:$ETH0_IP

