#!/bin/bash

sudo apt-get update
sudo apt-get install nfs-kernel-server cifs-utils nfs-common -y;
mkdir -p /opt/nfs
chown -R nobody:nogroup /opt/nfs
chmod 777 /opt/nfs
echo '/opt/nfs *(rw)' >> /etc/exports
exportfs -a
systemctl restart nfs-kernel-server

sudo apt-get update
sudo apt-get install nfs-kernel-server cifs-utils nfs-common -y;
mkdir /mnt/nfs/
mount $(hostname -I | awk '{print $1}'):/opt/nfs /mnt/nfs/
touch /mnt/nfs/testfile
ls -l /mnt/nfs/
