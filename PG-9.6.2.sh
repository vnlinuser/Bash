#!/usr/bin/env bash

echo -e "\e[31m
==================================================================================
脚本作用：一键安装POSTGRESQL
注意事项：脚本命名install_pg.sh,修改WEB 服务器IP，PG URL
使用方法：sh /usr/local/sbin/install_pg.sh && . /etc/profile
==================================================================================
\e[m"
echo
echo -e "\e[31m
=======================================准备开始安装=================================\e[m"

read -p "Please Enter【y】sure you need installtion postgresql database? :" SURE

if [ "$SURE" != "y" ] ;then echo "You dont want to installtion postgresql database? Please check your input..." && exit 0 ;fi

echo -e "\e[31m
====================================================================================\e[m"
echo

set -e

#检测postgres 是否有被安装：
[[ ! -z "$(ps aux|grep postgres |egrep -v grep)" ]] && echo "Database Postgresql was installed,Please checking it ..." && exit 0

#定义服务器版本
OS_VER="$(awk '{print $(NF-1)}' /etc/redhat-release |cut -f1 -d '.')"

#定义WEB 服务器IP：
WEBSVR='192.168.137.11/32'

#定义下载目录：
SRC='/usr/local/src'

#定义安装目录：
DST='/usr/local/postgresql'

#定义软件下载的URL：
URL='https://ftp.postgresql.org/pub/source/v9.6.2/postgresql-9.6.2.tar.gz'

#创建下载列表：
#echo "${URL}" > ${SRC}/wget-list

#获取PG 版本号
#PG_VER="$(awk -F '/' '{print $(NF)}'  ${SRC}/wget-list |sed -e 's/.tar.gz//')"
PG_VER="$(echo $URL |awk -F '/' '{print $NF}' |cut -f1-3 -d '.')"

#定义安装组件函数
INSTALL() {
    yum install -y epel-release
    yum install -y gcc gcc-c++ perl-ExtUtils-Embed  perl-ExtUtils-MakeMaker perl-ExtUtils-MakeMaker-Coverage readline readline-devel pam pam-devel libxml2 libxml2-devel libxml2-python libxml2-static  libxslt libxslt-devel tcl tcl-devel python-devel openssl-devel
}

#调试脚本用
#userdel -r postgres && rm -rf ${SRC}/${PG_VER}* && rm -rf /data/postgresql

#下载源码包：
wget -O ${SRC}/${PG_VER}.tar.gz ${URL}

#解压到下载目录：
tar -zxf ${SRC}/${PG_VER}.tar.gz -C ${SRC}/

#进入解压目录：
cd ${SRC}/${PG_VER}

#添加postgresql 运行用户：
useradd -s /bin/bash postgres

#定义PG 的管理员密码：
su - postgres -c "echo `openssl rand -base64 14` > /home/postgres/.PGPWD.txt"
chmod 600 /home/postgres/.PGPWD.txt

#执行INSTALL 函数
INSTALL

#配置编译参数：
./configure --prefix=${DST} --enable-debug --with-pgport=1921 --with-tcl --with-perl --with-python --with-pam --with-openssl --with-libxml --with-libxslt --with-blocksize=16 --with-wal-blocksize=16

#编译
gmake world

#安装：
gmake install-world

#设置系统环境变量：
echo "PATH=\$PATH:${DST}/bin" >> /etc/profile

#创建PG 数据目录并将目录所属主和组都修改为 postgres：
mkdir -p /data/postgresql && chown -R postgres:postgres /data/postgresql

#初始化PG：
su - postgres -c "initdb -D /data/postgresql -U postgres -E UTF8 --locale=C --pwfile=/home/postgres/.PGPWD.txt"

#设置监听IP（默认为 127.0。0.1）
su - postgres -c "sed -i \"s@^#listen_addresses = 'localhost'@listen_addresses = '*'@\" /data/postgresql/postgresql.conf"
su - postgres -c "sed -i 's@^max_connections = 100@max_connections = 500@' /data/postgresql/postgresql.conf"
su - postgres -c "echo \"host    all             all             ${WEBSVR}                 md5\" >> /data/postgresql/pg_hba.conf"

#启动PG
su - postgres -c "pg_ctl -D /data/postgresql -l logfile start"

#开启防火墙：
if [ "${OS_VER}" -eq 6 ] ;then
    [[ "$(service iptables status)" =~ 'not running' ]] && service iptables start
    iptables -I INPUT -p tcp -s ${WEBSVR} --dport 1921 -j ACCEPT
    service iptables save
else
    firewall-cmd --zone=public --permanent --add-rich-rule="rule family='ipv4' port protocol='tcp' port=1921 source address=\"${WEBSVR}\" accept"
    firewall-cmd --reload
fi

#清除解压目录和脚本文件：
rm -rf ${SRC}/{wget-list,${PG_VER}} /usr/local/sbin/install*.sh