#!/usr/bin/env bash

==================================================================================
脚本作用：一键安装Apache-2.4.25
注意事项：需要事先创建好证书,并将证书存放到/etc/pki/tls/目录下
==================================================================================
\e[m"
echo
echo -e "\e[31m
=======================================准备开始安装=================================\e[m"

read -p "Please Enter【y】sure you need installtion Apache? :" SURE

if [ "$SURE" != "y" ] ;then echo "You dont want to installtion Apache? Please check your input..." && exit 0 ;fi

echo -e "\e[31m
====================================================================================\e[m"
echo

set -e

#检测服务器是否有安装WEB 服务
[[ ! -z "$(ps aux|egrep ':80|:443' |egrep -v grep)" ]] && ehco "Web installed,please checking it..." && exet 0

#定义软件下载路径：
SRC='/usr/local/src'

#定义系统版本：
OS_VER="$(awk '{print $(NF-1)}' /etc/redhat-release |awk -F '.' '{print $1}')"

#安装扩展源：
yum install -y epel-release

#安装必要的组件：
yum install -y gcc gcc-c++ vim libxml2-devel openssl openssl-devel telnet perl perl-devel bzip2-devel libpng-devel freetype-devel libmcrypt-devel libjpeg-devel  wget git libtool automake autoconf

#创建下载列表:
cat << 'eof' > ${SRC}/wget-list
http://mirror.downloadvn.com/apache/httpd/httpd-2.4.25.tar.gz
http://mirror.downloadvn.com/apache/apr/apr-1.5.2.tar.gz
http://mirror.downloadvn.com/apache/apr/apr-util-1.5.4.tar.gz
ftp://ftp.csx.cam.ac.uk/pub/software/programming/pcre/pcre-8.39.tar.gz
http://www.bzip.org/1.0.6/bzip2-1.0.6.tar.gz
eof

#获取各个包的版本信息
APAV="$(awk -F '/' '/httpd/{print $(NF)}' /usr/local/src/wget-list |sed -e 's/.tar.gz//')"
ZIPV="$(awk -F '/' '/bzip/{print $(NF)}' /usr/local/src/wget-list |sed -e 's/.tar.gz//')"
ARPV="$(awk -F '/' '/apr-1/{print $(NF)}' /usr/local/src/wget-list |sed -e 's/.tar.gz//')"
ARPU="$(awk -F '/' '/apr-u/{print $(NF)}' /usr/local/src/wget-list |sed -e 's/.tar.gz//')"
PCRV="$(awk -F '/' '/pcre/{print $(NF)}' /usr/local/src/wget-list |sed -e 's/.tar.gz//')"

#下载：
wget -i $SRC/wget-list -P $SRC/

#解压：
for i in $(ls ${SRC}/*.tar.gz) ;do tar zxf ${i} -C ${SRC}/ ;done

#进入APR 目录
cd ${SRC}/${ARPV}

#配置
./configure --prefix=/usr/local/apr

#编译及安装
make && make install

#进入APR-UTIL 解压目录
cd ${SRC}/${ARPU}

#配置编译参数
./configure --prefix=/usr/local/apr-util  --with-apr=/usr/local/apr

#编译安装
make && make install

#进入pcre 解压目录：
cd ${SRC}/${PCRV}

#配置编译参数
./configure --prefix=/usr/local/pcre

# 编译安装
make && make install

#进入apache解压目录：
cd ${SRC}/${APAV}

#配置编译参数：
./configure --prefix=/usr/local/apache2 --with-apr=/usr/local/apr --with-apr-util=/usr/local/apr-util --enable-deflate=shared --enable-expires=shared --enable-rewrite=shared --with-pcreble-deflate=shared --enable-expires=shared --enable-rewrite=shared --with-pcre=/usr/local/pcre --with-z --enable-so

#编译：
make

#编译安装：
make install

#配置apache:
cp /usr/local/apache2/conf/httpd.conf{,.bak}
sed -i 's@^#Include conf/extra/httpd-vhosts.conf@Include conf/extra/httpd-vhosts.conf@' /usr/local/apache2/conf/httpd.conf
sed -i 's@^#LoadModule rewrite_module modules/mod_rewrite.so@LoadModule rewrite_module modules/mod_rewrite.so@' /usr/local/apache2/conf/httpd.conf
#sed -i 's@^#Include conf/extra/httpd-ssl.conf@Include conf/extra/httpd-ssl.conf@' /usr/local/apache2/conf/httpd.conf
sed -i 's@^#LoadModule ssl_module modules/mod_ssl.so@LoadModule ssl_module modules/mod_ssl.so@' /usr/local/apache2/conf/httpd.conf
sed -i 's@^#LoadModule socache_shmcb_module modules/mod_socache_shmcb.so@LoadModule socache_shmcb_module modules/mod_socache_shmcb.so@' /usr/local/apache2/conf/httpd.conf
sed -i 's@^Listen 80$@Listen 80\nListen 443@' /usr/local/apache2/conf/httpd.conf
sed -i 's@^#ServerName www.example.com:80@ServerName localhost:80@' /usr/local/apache2/conf/httpd.conf

#备份主配置：
cp /usr/local/apache2/conf/extra/httpd-vhosts.conf{,.bak}

#创建网站目录：
mkdir -p /usr/local/apache2/{aaa.com,bbb.com}

#配置测试页：
cat << 'eof' > /usr/local/apache2/aaa.com/index.html
<h1> aaa.com!</h1>
eof

cat << 'eof' > /usr/local/apache2/bbb.com/index.html
<h1> bbb.com!</h1>
eof

cat << 'eof' > /usr/local/apache2/htdocs/index.html
<h1> It's work!</h1>
eof

#配置虚拟主机：
cat << 'eof' > /usr/local/apache2/conf/extra/httpd-vhosts.conf
<VirtualHost *:80>
    directoryIndex index.htm index.html index.php
    DocumentRoot /usr/local/apache2/htdocs
    ServerName -
    <Directory "/usr/local/apache2/htdocs">
        Options -Indexes
        AllowOverride All
        Require all granted
    </Directory>

    #强制跳转：
    RewriteEngine on
    #RewriteCond %{HTTP_HOST} ^192.168.137.12 [NC]
    RewriteCond %{SERVER_PORT} !^443$
    RewriteRule ^(.*)?$ https://%{SERVER_NAME}$1 [L,R]
</VirtualHost>

<VirtualHost *:443>
    #不同域名使用不同证书需要到虚拟主机上配置证书，关闭ssl.conf 配置，同时要在主配置文件中加入配置参数： Listen 443
    SSLEngine on
    SSLCertificateFile /etc/pki/tls/certs/server.crt
    SSLCertificateKeyFile /etc/pki/tls/private/server.key
    directoryIndex index.htm index.html index.php
    DocumentRoot /usr/local/apache2/htdocs
    ServerName -
    <Directory "/usr/local/apache2/htdocs">
        Options Indexes
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

<VirtualHost *:443>
    #不同域名使用不同证书需要到虚拟主机上配置证书，关闭ssl.conf 配置，同时要在主配置文件中加入配置参数： Listen 443
    SSLEngine on
    SSLCertificateFile /etc/pki/tls/certs/server.crt
    SSLCertificateKeyFile /etc/pki/tls/private/server.key
    directoryIndex index.htm index.html index.php
    DocumentRoot /usr/local/apache2/aaa.com
    ServerName aaa.com
    <Directory "/usr/local/apache2/aaa.com">
        Options Indexes
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>

<VirtualHost *:443>
    SSLEngine on
    SSLCertificateFile /etc/pki/tls/certs/server.crt
    SSLCertificateKeyFile /etc/pki/tls/private/server.key
    directoryIndex index.htm index.html index.php
    DocumentRoot /usr/local/apache2/bbb.com
    ServerName bbb.com
    <Directory "/usr/local/apache2/bbb.com">
        Options Indexes
        AllowOverride All
        Require all granted
    </Directory>
</VirtualHost>
eof

#检测配置并启动
/usr/local/apache2/bin/apachectl -t && /usr/local/apache2/bin/apachectl

#开启80及443端口：
if [ "${OS_VER=}" -eq 6 ] ;then
    [[ "$(service iptables status)" =~ 'not running' ]] && service iptables start
    iptables -I INPUT -p tcp -m multiport --dport 80,443 -j ACCEPT
    service iptables save
else
    firewall-cmd --add-port={80,443}/tcp --zone=public --permanent
    firewall-cmd --reload
fi

#设置系统环境变量
echo 'PATH=$PATH:/usr/local/apache2/bin' >> /etc/profile