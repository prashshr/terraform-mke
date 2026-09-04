#!/bin/bash

sudo rpm -i /home/ec2-user/offline-files/containerd.io-1.6.30-2.2.rc.2.1.el8.x86_64.rpm
sudo rpm -i /home/ec2-user/offline-files/docker-ee-cli-23.0.10-3.el8.x86_64.rpm
sudo rpm -i /home/ec2-user/offline-files/docker-ee-23.0.10-3.el8.x86_64.rpm /home/ec2-user/offline-files/docker-ee-rootless-extras-23.0.10-3.el8.x86_64.rpm
sudo rpm -qa | grep -iE ‘containerd|docker’
sudo systemctl enable docker
sudo systemctl restart docker
