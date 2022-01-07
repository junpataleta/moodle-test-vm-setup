#!/bin/bash

# List supported PHP versions of supported Moodle versions (even security ones).
# - 39 supports 7.3.
# - 311 supports min 7.3 up to 8.0.
# - 400 will support min 7.4 up to 8.0.
PHP_VERSIONS=("7.3" "7.4" "8.0")

# Add ondrej/php ppa so we can install other PHP versions.
sudo add-apt-repository ppa:ondrej/php -y

# Update and upgrade.
sudo apt update && sudo apt upgrade -y

# Install docker.
echo "Installing docker..."
sudo apt-get install -y \
    apt-transport-https \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg

echo \
  "deb [arch=amd64 signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update

sudo apt-get install -y docker-ce docker-ce-cli containerd.io

# Install docker compose.
sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

sudo chmod +x /usr/local/bin/docker-compose

# Use docker as non-root user.
if [ $(getent group docker) ]; then
  echo "docker group already exists..."
else
  sudo groupadd docker
  sudo usermod -aG docker $USER
  newgrp docker
fi

# Create apps folder.
echo "Create apps folder."
mkdir ~/apps
cd ~/apps

# Create postgres.
echo "Installing postgres via docker-compose"
mkdir ~/apps/postgres
cd ~/apps/postgres
touch docker-compose.yml
echo 'version: "3"
services:
  db:
    image: "postgres:10"
    ports:
      - "5432:5432"
    environment:
      - POSTGRES_PASSWORD=moodle' >> docker-compose.yml

docker-compose up -d
# Make sure to run it on system start.

# Install mysql and other required programs.
echo "Install mysql and other required programs."
sudo apt install -y mysql-server curl git default-jdk xvfb

# Install PostgreSQL server.
#sudo apt install -y postgresql postgresql-contrib

# Set postgres account password.
#sudo -u postgres psql -c "ALTER ROLE postgres WITH PASSWORD 'moodle';"

# List required PHP extensions.
PHP_EXTS=(dev pgsql intl mysqli xml mbstring curl zip gd soap xmlrpc)
PHP_INSTALL=""
for phpver in "${PHP_VERSIONS[@]}"
do
  # Install supported PHP versions.
  PHP_INSTALL="$PHP_INSTALL php$phpver"

  # Install required PHP extensions per version.
  for j in "${PHP_EXTS[@]}"
  do
      PHP_INSTALL="$PHP_INSTALL php$phpver-$j"
  done
  # Install PHP and its required extensions.
  echo "Install PHP $phpver and its required extensions."
  sudo apt install -y $PHP_INSTALL

  # Set max_input_vars to 5000.
  sudo sed -i_bak "/;max_input_vars.*/a max_input_vars = 5000" /etc/php/$phpver/apache2/php.ini

done

# Clone moodle-browser-config.
git clone https://github.com/andrewnicols/moodle-browser-config.git

# Download Chrome.
wget https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb

# Install Chrome.
sudo apt install ./google-chrome-stable_current_amd64.deb

# Extract version of Chrome.
CHROME_VER=$(google-chrome --version | cut -d ' ' -f 3 | cut -d '.' -f 1,2,3 --output-delimiter='.')

# Install Chromium.
# sudo apt install chromium-browser

# Extract version of chromium
# CHROME_VER=$(chromium --version | cut -d ' ' -f 2 | cut -d '.' -f 1,2,3 --output-delimiter='.')

# Extract latest version of chromedriver matching Chromium.
CHROMEDRIVER_VER=$(curl --user-agent "fogent" --silent https://chromedriver.chromium.org/downloads | grep -o "${CHROME_VER}\.[0-9]*" | head -1)

# Download the zip file of the chromedriver.
wget https://chromedriver.storage.googleapis.com/$CHROMEDRIVER_VER/chromedriver_linux64.zip

# Extract it.
unzip chromedriver_linux64.zip

# Delete it.
rm chromedriver_linux64.zip

# Link it to /usr/local/bin.
sudo ln -s "$(pwd)/chromedriver" /usr/local/bin/chromedriver

# Download latest geckodriver.
curl -s https://api.github.com/repos/mozilla/geckodriver/releases/latest \
  | grep browser_download_url \
  | grep linux64 \
  | cut -d '"' -f 4 \
  | wget -qi -

# Extract it.
tar -xvzf "$(ls | grep 'geckodriver.*gz' | head -1)"

# Delete the geckodriver package.
rm geckodriver*.gz*

# Link it to /usr/local/bin.
sudo ln -s "$(pwd)/geckodriver" /usr/local/bin/geckodriver

# Download latest supported selenium standalone (3.141.59).
wget https://github.com/SeleniumHQ/selenium/releases/download/selenium-3.141.59/selenium-server-standalone-3.141.59.jar

# Set aliases for selenium.
echo "alias sel='java -jar ~/apps/selenium-server-standalone-3.141.59.jar'" >> ~/.bashrc
echo "alias xsel='xvfb-run java -jar ~/apps/selenium-server-standalone-3.141.59.jar'" >> ~/.bashrc

# Reload bashrc.
source ~/.bashrc

# MDK.

# Install required packages.
sudo apt install -y python3-pip libmysqlclient-dev libpq-dev python3-dev unixodbc-dev

# Install MDK.
sudo pip install moodle-sdk

# Create MDK config.json.
mkdir ~/.moodle-sdk
touch ~/.moodle-sdk/config.json
mdk config set defaultEngine pgsql
mdk config set db.pgsql.user postgres
mdk config set db.pgsql.passwd moodle

# Run mdk doctor to create moodle folders.
mdk doctor --fix --all

# Create a moodle.git master instance (stable_master).
mdk create -i -r users

# Create a integration.git master instance (integration_master).
mdk create -i -t -r users

cd ~/moodles/integration_master/moodle

sed -i_bak "/^.*setup\.php.*/i require_once('${HOME}/apps/moodle-browser-config/init.php');" config.php

# Initialise Behat
mdk behat

# Set up parallel run.
php admin/tool/behat/cli/init.php -j=2 -o
