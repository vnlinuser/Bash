#!/usr/bin/env bash

#脚本作用：在centos 6 或centos 7上一键安装maraidb-galera-cluster 第一个节点
#注意事项：适用脚本前，请提前配置好各节点的计算机名，同时，只需修改设置节点的IP

set -e
set -x

#定义节点：
NODE01='192.168.137.11'
NODE02='192.168.137.12'
NODE03='192.168.137.23'

#定义系统版本：
OS_VER="$(awk '{print $3}' /etc/redhat-release |sed -e 's/.[0-9]//g')"

#设置hosts解析：
if [[ -z "$(egrep $(echo $HOSTNAME) /etc/hosts)" ]] ;then
    echo "${NODE01} node01.com" >> /etc/hosts
    echo "${NODE02} node02.com" >> /etc/hosts
    echo "${NODE03} node03.com" >> /etc/hosts
fi  	

#删除系统mysql 相关：
yum erase mysql-server mysql mysql-devel mysql-libs -y
rm -rf /var/lib/mysql

#添加mariadb 系统默源
if [ "${OS_VER}" -eq 6 ] ;then
    echo '[mariadb-10.0]' > /etc/yum.repos.d/maraidb.repo
    echo 'name = Maraidb-10.0' >> /etc/yum.repos.d/maraidb.repo
    echo 'baseurl = http://yum.mariadb.org/10.0/centos6-amd64/' >> /etc/yum.repos.d/maraidb.repo
    echo 'gpgkey-https=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB' >> /etc/yum.repos.d/maraidb.repo
    echo 'gpgcheck = 1' >> /etc/yum.repos.d/maraidb.repo
else
    echo '[mariadb-10.0]' > /etc/yum.repos.d/maraidb.repo
    echo 'name = Maraidb-10.0' >> /etc/yum.repos.d/maraidb.repo
    echo 'baseurl = http://yum.mariadb.org/10.0/centos7-amd64/' >> /etc/yum.repos.d/maraidb.repo
    echo 'gpgkey-https=https://yum.mariadb.org/RPM-GPG-KEY-MariaDB' >> /etc/yum.repos.d/maraidb.repo
    echo 'gpgcheck = 1' >> /etc/yum.repos.d/maraidb.repo
fi

#导入官方提供的key:
rpm --import http://yum.mariadb.org/RPM-GPG-KEY-MariaDB

# 安装mariadb 集群相关组件
yum install -y galera

# 将仲裁节点加入集群：
$(which garbd) -a gcomm://${NODE01}:4567,${NODE02}:4567 -g cluster-01 -l /tmp/1.out -d




