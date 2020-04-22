source ./config.sh

# install etcd
apt-get update
apt-get install etcd

# Set configuration values

# Start and enable services
systemctl enable etcd
systemctl restart etcd
