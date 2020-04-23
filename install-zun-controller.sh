#!/bin/sh

. ./config.sh

# Setup Database
mysql --user="root" --password="$ZUN_DBPASS" --execute="
CREATE DATABASE zun;
GRANT ALL PRIVILEGES ON zun.* TO 'zun'@'localhost' \
  IDENTIFIED BY '$ZUN_DBPASS';
GRANT ALL PRIVILEGES ON zun.* TO 'zun'@'%' \
  IDENTIFIED BY '$ZUN_DBPASS';"

# Source admin variables
. ./admin-openrc.sh

# create zun user and add as admin
openstack user create --domain default --password $USER_PASS zun
openstack role add --project service --user zun admin

# Create container service API endpoints
openstack service create --name zun \
    --description "Container Service" container
openstack endpoint create --region RegionOne \
    container public http://ctl:9517/v1
openstack endpoint create --region RegionOne \
    container internal http://ctl:9517/v1
openstack endpoint create --region RegionOne \
    container admin http://ctl:9517/v1

# Create zun user
groupadd --system zun
useradd --home-dir "/var/lib/zun" \
      --create-home \
      --system \
      --shell /bin/false \
      -g zun \
      zun

# Create directories
mkdir -p /etc/zun
chown zun:zun /etc/zun

# install dependencies
apt-get update
apt-get install -y python3-pip git

# clone and install zun
cd /var/lib/zun
git clone https://opendev.org/openstack/zun.git
chown -R zun:zun zun
cd zun
pip3 install -r requirements.txt
python3 setup.py install

# Copy api-paste
su -s /bin/sh -c "cp etc/zun/api-paste.ini /etc/zun" zun

echo "[DEFAULT]
transport_url = rabbit://openstack:$RABBIT_PASS@ctl

[api]
host_ip = $MIIP
port = 9517

[database]
connection = mysql+pymysql://zun:$ZUN_DBPASS@ctl/zun

[keystone_auth]
memcached_servers = ctl:11211
www_authenticate_uri = http://ctl:5000
project_domain_name = default
project_name = service
user_domain_name = default
password = $ZUN_PASS
username = zun
auth_url = http://ctl:5000
auth_type = password
auth_version = v3
auth_protocol = http
service_token_roles_required = True
endpoint_type = internalURL

[keystone_authtoken]
memcached_servers = ctl:11211
www_authenticate_uri = http://ctl:5000
project_domain_name = default
project_name = service
user_domain_name = default
password = $ZUN_PASS
username = zun
auth_url = http://ctl:5000
auth_type = password
auth_version = v3
auth_protocol = http
service_token_roles_required = True
endpoint_type = internalURL

[oslo_concurrency]
lock_path = /var/lib/zun/tmp

[oslo_messaging_notifications]
driver = messaging

[websocket_proxy]
wsproxy_host = $MIIP
wsproxy_port = 6784
base_url = ws://ctl:6784/" > /etc/zun/zun.conf

# Set owner to zun
chown zun:zun /etc/zun/zun.conf

# Populate zun database
su -s /bin/sh -c "zun-db-manage upgrade" zun

# Create upstart config for zun api
echo "[Unit]
Description = OpenStack Container Service API

[Service]
ExecStart = /usr/local/bin/zun-api
User = zun

[Install]
WantedBy = multi-user.target" > /etc/systemd/system/zun-api.service

# Create upstart config for zun wsproxy
echo "[Unit]
Description = OpenStack Container Service Websocket Proxy

[Service]
ExecStart = /usr/local/bin/zun-wsproxy
User = zun

[Install]
WantedBy = multi-user.target" > /etc/systemd/system/zun-wsproxy.service

# Enable and start zun api
systemctl enable zun-api
systemctl start zun-api

# Enable and start zun wsproxy
systemctl enable zun-wsproxy
systemctl start zun-wsproxy
