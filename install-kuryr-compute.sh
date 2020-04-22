source ./config.sh

# Creating kuryr user
groupadd --system kuryr
useradd --home-dir "/var/lib/kuryr" \
      --create-home \
      --system \
      --shell /bin/false \
      -g kuryr \
      kuryr

# Creating kuryr directories
mkdir -p /etc/kuryr
chown kuryr:kuryr /etc/kuryr

# Cloning and installing kuryr-libnetwork
apt-get install python3-pip
cd /var/lib/kuryr
git clone -b master https://git.openstack.org/openstack/kuryr-libnetwork.git
chown -R kuryr:kuryr kuryr-libnetwork
cd kuryr-libnetwork
pip3 install -r requirements.txt
python3 setup.py install

# Generating sample config
su -s /bin/sh -c "./tools/generate_config_file_samples.sh" kuryr
su -s /bin/sh -c "cp etc/kuryr.conf.sample \
      /etc/kuryr/kuryr.conf" kuryr

# Write config
echo '[DEFAULT]
bindir = /usr/local/libexec/kuryr
capability_scope = global
process_external_connectivity = False

[neutron]
www_authenticate_uri = http://controller:5000
auth_url = http://controller:5000
username = kuryr
user_domain_name = default
password = '"$KURYR_PASSWORD"'
project_name = service
project_domain_name = default
auth_type = password' >> /etc/kuryr/kuryr.conf

# Create service
echo '[Unit]
Description = Kuryr-libnetwork - Docker network plugin for Neutron

[Service]
ExecStart = /usr/local/bin/kuryr-server --config-file /etc/kuryr/kuryr.conf
CapabilityBoundingSet = CAP_NET_ADMIN

[Install]
WantedBy = multi-user.target' >> /etc/systemd/system/kuryr-libnetwork.service

# Enable and start service
systemctl enable kuryr-libnetwork
systemctl start kuryr-libnetwork

# Restart docker
systemctl restart docker
