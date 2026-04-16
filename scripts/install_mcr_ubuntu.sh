#!/bin/bash

sudo apt-get update
sudo apt-get -y install \
  apt-transport-https \
  ca-certificates \
  curl \
  software-properties-common
DOCKER_EE_URL="https://repos.mirantis.com"
DOCKER_EE_VERSION=23.0
curl -fsSL "${DOCKER_EE_URL}/ubuntu/gpg" | sudo apt-key add -
sudo apt-key fingerprint 6D085F96
sudo add-apt-repository \
  "deb [arch=$(dpkg --print-architecture)] $DOCKER_EE_URL/ubuntu \
  $(lsb_release -cs) \
  stable-$DOCKER_EE_VERSION"
sudo apt-get update
sudo apt-get install docker-ee docker-ee-cli docker-ee-rootless-extras containerd.io -y
sudo systemctl restart docker
