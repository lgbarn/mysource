#!/usr/bin/env bash
# This bootstraps Puppet on CentOS 6.x
# It has been tested on CentOS 6.4 64bit

set -e

REPO_URL="http://yum.puppetlabs.com/el/6/products/i386/puppetlabs-release-6-7.noarch.rpm"

if [ "$EUID" -ne "0" ]; then
echo "This script must be run as root." >&2
  exit 1
fi

if which puppet > /dev/null 2>&1; then
echo "Puppet is already installed."
  exit 0
fi

if which wget > /dev/null 2>&1; then
  echo "Wget already installed"
else
  echo "Installing Wget"
  yum -y install wget > /dev/null
  echo "Wget installed"
fi

  
# Install puppet labs repo
echo "Configuring PuppetLabs repo..."
repo_path=$(mktemp)
wget --output-document="${repo_path}" "${REPO_URL}" 2>/dev/null
rpm -i "${repo_path}" >/dev/null

# Install Puppet...
echo "Installing puppet"
yum install -y puppet > /dev/null

echo "Puppet installed!"

touch /etc/role

#rm -rf /etc/puppet
#mkdir /etc/puppet
#cd /etc/puppet
#git clone https://github.com/lgbarn/puppet.git .
rsync -au --delete /vagrant/puppet /etc
puppet apply -v --modulepath=/etc/puppet/modules /etc/puppet/manifests/site.pp
