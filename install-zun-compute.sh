#!/bin/sh

. ./config.sh

# Create User
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

# Create CNI Directories
mkdir -p /etc/cni/net.d
chown zun:zun /etc/cni/net.d

# Install dependencies
apt-get install -y python3-pip git numactl

# Clone and install zun
cd /var/lib/zun
git clone https://opendev.org/openstack/zun.git
chown -R zun:zun zun
cd zun
pip3 install -r requirements.txt
python3 setup.py install

# Generate a sample configuration file
su -s /bin/sh -c "oslo-config-generator \
    --config-file etc/zun/zun-config-generator.conf" zun
su -s /bin/sh -c "cp etc/zun/rootwrap.conf \
    /etc/zun/rootwrap.conf" zun
su -s /bin/sh -c "mkdir -p /etc/zun/rootwrap.d" zun
su -s /bin/sh -c "cp etc/zun/rootwrap.d/* \
    /etc/zun/rootwrap.d/" zun
su -s /bin/sh -c "cp etc/cni/net.d/* /etc/cni/net.d/" zun

# Configure sudoers for zun users
echo "zun ALL=(root) NOPASSWD: /usr/local/bin/zun-rootwrap \
    /etc/zun/rootwrap.conf *" | sudo tee /etc/sudoers.d/zun-rootwrap

# Write config
echo "[DEFAULT]
transport_url = rabbit://openstack:$RABBIT_PASS@ctl
state_path = /var/lib/zun

[database]
connection = mysql+pymysql://zun:$ZUN_DBPASS@ctl/zun
memcached_servers = ctl:11211
[keystone_auth]
www_authenticate_uri = http://ctl:5000
project_domain_name = default
project_name = service
user_domain_name = default
password = ZUN_PASS
username = zun
auth_url = http://ctl:5000
auth_type = password
auth_version = v3
auth_protocol = http
service_token_roles_required = True
endpoint_type = internalURL

[keystone_authtoken]
memcached_servers = ctl:11211
www_authenticate_uri= http://ctl:5000
project_domain_name = default
project_name = service
user_domain_name = default
password = ZUN_PASS
username = zun
auth_url = http://ctl:5000
auth_type = password

[oslo_concurrency]
lock_path = /var/lib/zun/tmp

[compute]
host_shared_with_nova = true" > /etc/zun/zun.conf

# Set owner of config
chown zun:zun /etc/zun/zun.conf

# Create docker service config
mkdir -p /etc/systemd/system/docker.service.d
echo "ExecStart=
ExecStart=/usr/bin/dockerd --group zun -H tcp://cp-1:2375 -H unix:///var/run/docker.sock --cluster-store etcd://ctl:2379" > /etc/systemd/system/docker.service.d/docker.conf

# restart docker
systemctl daemon-reload
systemctl restart docker

# configure containerd
containerd config default > /etc/containerd/config.toml
sed -i 's/gid \?=.*/gid = '$(getent group zun | cut -d: -f3)'/' /etc/containerd/config.toml
chown zun:zun /etc/containerd/config.toml

# restart containerd
systemctl restart containerd

# configure CNI
mkdir -p /opt/cni/bin
curl -L https://github.com/containernetworking/plugins/releases/download/v0.7.1/cni-plugins-amd64-v0.7.1.tgz \
      | tar -C /opt/cni/bin -xzvf - ./loopback
install -o zun -m 0555 -D /usr/local/bin/zun-cni /opt/cni/bin/zun-cni

# Create upstart config for zun
echo "[Unit]
Description = OpenStack Container Service Compute Agent

[Service]
ExecStart = /usr/local/bin/zun-compute
User = zun

[Install]
WantedBy = multi-user.target" > /etc/systemd/system/zun-compute.service

# Create upstart config for zun cni daemon
echo "[Unit]
Description = OpenStack Container Service CNI daemon

[Service]
ExecStart = /usr/local/bin/zun-cni-daemon
User = zun

[Install]
WantedBy = multi-user.target" > /etc/systemd/system/zun-cni-daemon.service

# Enable and start zun
systemctl enable zun-compute
systemctl start zun-compute

# Enable and start zun cni daemon
systemctl enable zun-cni-daemon
systemctl start zun-cni-daemon
