#!/bin/bash

# Installing MCR
sudo rm /etc/yum.repos.d/docker*.repo
export DOCKERURL="https://repos.mirantis.com"
sudo -E sh -c 'echo "$DOCKERURL/rhel" > /etc/yum/vars/dockerurl'
sudo sh -c 'echo "7" > /etc/yum/vars/dockerosversion'
sudo yum install -y yum-utils
sudo yum-config-manager --enable rhel-7-server-rhui-extras-rpms 2>/dev/null || \
  sudo yum-config-manager --enable rhel-7-server-extras-rpms 2>/dev/null || true
sudo -E yum-config-manager \
    --add-repo \
    "$DOCKERURL/centos/docker-ee.repo"
sudo yum list docker-ee --showduplicates | sort -r
# sudo yum -y upgrade docker-ee-23.0.13 docker-ee-cli-23.0.13 docker-ee-rootless-extras-23.0.13 containerd.io
sudo yum -y install docker-ee-19.03.5 docker-ee-cli-19.03.5 containerd.io

# Reload and restart the daemon
sudo systemctl enable docker
sudo systemctl restart docker

# Install NFS client packages to mount PVCs with NFS storage class
sudo yum install nfs-utils rpcbind cifs-utils vim jq -y
