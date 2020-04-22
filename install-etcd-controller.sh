#!/bin/sh

. ./config.sh

# install etcd
apt-get update
apt-get install -y etcd

# Set configuration values
echo 'ETCD_NAME="controller"
ETCD_DATA_DIR="/var/lib/etcd"
ETCD_INITIAL_CLUSTER_STATE="new"
ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster-01"
ETCD_INITIAL_CLUSTER="controller=http://'"$MIIP"':2380"
ETCD_INITIAL_ADVERTISE_PEER_URLS="http://'"$MIIP"':2380"
ETCD_ADVERTISE_CLIENT_URLS="http://'"$MIIP"':2379"
ETCD_LISTEN_PEER_URLS="http://0.0.0.0:2380"
ETCD_LISTEN_CLIENT_URLS="http://'"$MIIP"':2379"' > /etc/default/etcd

# Start and enable services
systemctl enable etcd
systemctl restart etcd
