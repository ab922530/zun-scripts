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
    container public http://$CONTROLLER:9517/v1
openstack endpoint create --region RegionOne \
    container internal http://$CONTROLLER:9517/v1
openstack endpoint create --region RegionOne \
    container admin http://$CONTROLLER:9517/v1

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

# Generate sample config
su -s /bin/sh -c "oslo-config-generator \
    --config-file etc/zun/zun-config-generator.conf" zun
su -s /bin/sh -c "cp etc/zun/zun.conf.sample \
    /etc/zun/zun.conf" zun

# Copy api-paste
su -s /bin/sh -c "cp etc/zun/api-paste.ini /etc/zun" zun

crudini --set /etc/zun/zun.conf DEFAULT transport_url $RABBIT_URL

crudini --set /etc/zun/zun.conf api host_ip $MIIP
crudini --set /etc/zun/zun.conf api port 9517

crudini --set /etc/zun/zun.conf database connection "mysql+pymysql://zun:$ZUN_DBPASS@$CONTROLLER/zun"

crudini --set /etc/zun/zun.conf keystone_auth memcached_servers $CONTROLLER:11211
crudini --set /etc/zun/zun.conf keystone_auth www_authenticate_uri http://$CONTROLLER:5000
crudini --set /etc/zun/zun.conf keystone_auth project_domain_name default
crudini --set /etc/zun/zun.conf keystone_auth project_name service
crudini --set /etc/zun/zun.conf keystone_auth user_domain_name default
crudini --set /etc/zun/zun.conf keystone_auth password "$ZUN_PASS"
crudini --set /etc/zun/zun.conf keystone_auth username zun
crudini --set /etc/zun/zun.conf keystone_auth auth_url http://$CONTROLLER:5000
crudini --set /etc/zun/zun.conf keystone_auth auth_type password
crudini --set /etc/zun/zun.conf keystone_auth auth_version v3
crudini --set /etc/zun/zun.conf keystone_auth auth_protocol http
crudini --set /etc/zun/zun.conf keystone_auth service_token_roles_required True
crudini --set /etc/zun/zun.conf keystone_auth endpoint_type internalURL

crudini --set /etc/zun/zun.conf keystone_authtoken memcached_servers $CONTROLLER:11211
crudini --set /etc/zun/zun.conf keystone_authtoken www_authenticate_uri http://$CONTROLLER:5000
crudini --set /etc/zun/zun.conf keystone_authtoken project_domain_name default
crudini --set /etc/zun/zun.conf keystone_authtoken project_name service
crudini --set /etc/zun/zun.conf keystone_authtoken user_domain_name default
crudini --set /etc/zun/zun.conf keystone_authtoken password "$ZUN_PASS"
crudini --set /etc/zun/zun.conf keystone_authtoken username zun
crudini --set /etc/zun/zun.conf keystone_authtoken auth_url http://$CONTROLLER:5000
crudini --set /etc/zun/zun.conf keystone_authtoken auth_type password
crudini --set /etc/zun/zun.conf keystone_authtoken auth_version v3
crudini --set /etc/zun/zun.conf keystone_authtoken auth_protocol http
crudini --set /etc/zun/zun.conf keystone_authtoken service_token_roles_required True
crudini --set /etc/zun/zun.conf keystone_authtoken endpoint_type internalURL

crudini --set /etc/zun/zun.conf oslo_concurrency lock_path /var/lib/zun/tmp
crudini --set /etc/zun/zun.conf oslo_messaging_notifications driver messaging

crudini --set /etc/zun/zun.conf websocket_proxy wsproxy_host $MIIP
crudini --set /etc/zun/zun.conf websocket_proxy wsproxy_port 6784
crudini --set /etc/zun/zun.conf websocket_proxy base_url ws://$CONTROLLER:6784/

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
