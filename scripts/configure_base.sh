#!/bin/bash

set -o errexit
set -o nounset
set -o pipefail
set -x

# update all packages
yum update -y

# install basic tooling
yum -y install epel-release
yum -y install git vim tmux socat at jq unzip htop ipvsadm docker

# disable kdump service
#systemctl disable kdump.service

# Set SELinux in enforcing mode
setenforce 1
sed -i 's/^SELINUX=permissive$/SELINUX=enforcing/' /etc/selinux/config
