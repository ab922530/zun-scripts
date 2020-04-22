source ./config.sh

# source admin variables
. admin-openrc

# create openstack user for kuryr, add as admin
openstack user create --domain default --password $KURYR_PASSWORD kuryr
openstack role add --project service --user kuryr admin
