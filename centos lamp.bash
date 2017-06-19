#!/usr/bin/env bash

. /etc/profile

#脚本作用：在centos 6 或 7 上一键部署lamp 环境
#注意事项：修改各个包的下载URL 即可
#脚本版本：v20170425-1201

set -e
set -x

#定义系统版本：
OS_VER="$(awk '{print $(NF-1)}' /etc/redhat-release |awk -F '.' '{print $1}')"

GLIBC_V="$(ldd --version |awk '/GNU/{print $4}')"

#定义软件下载目录
SRC="/usr/local/src"

#定义mysql root 密码
PASS="$(openssl rand -base64 14)" && echo ${PASS} > ~/.Mariadb.pass

#定义mysql 数据目录：
DATA_DIR='/data/mysql'
BASE_DIR='/usr/local/mysql'

#安装必要的包
yum install -y epel-release 

yum install -y gcc gcc-c++ vim libxml2-devel openssl openssl-devel telnet perl perl-devel apr apr-util apr-devel  bzip2-devel libpng-devel freetype-devel libmcrypt-devel libjpeg-devel apr-util-devel wget git libtool automake autoconf

#创建下载地址列表
if [[ "${GLIBC_V}" < 2.14 ]] ;then
    echo "https://cdn.mysql.com//Downloads/MySQL-5.6/mysql-5.6.35-linux-glibc2.5-x86_64.tar.gz" > $SRC/wget-list
else
    echo "http://sgp1.mirrors.digitalocean.com/mariadb//mariadb-10.1.22/bintar-linux-glibc_214-x86_64/mariadb-10.1.22-linux-glibc_214-x86_64.tar.gz" > $SRC/wget-list
fi

echo "http://cn2.php.net/distributions/php-5.6.30.tar.gz" >> $SRC/wget-list
echo "http://mirrors.cnnic.cn/apache/httpd/httpd-2.4.25.tar.gz" >> $SRC/wget-list
echo "http://www.bzip.org/1.0.6/bzip2-1.0.6.tar.gz" >> $SRC/wget-list
echo "http://mirrors.tuna.tsinghua.edu.cn/apache//apr/apr-1.5.2.tar.gz" >> $SRC/wget-list
echo "http://mirrors.tuna.tsinghua.edu.cn/apache//apr/apr-util-1.5.4.tar.gz" >> $SRC/wget-list
echo "https://ftp.pcre.org/pub/pcre/pcre-8.40.tar.gz" >> $SRC/wget-list

#下载：
wget -i $SRC/wget-list -P $SRC/ && [[ "$(echo $?)" -ne 0 ]] && exit 4
git clone https://github.com/shivaas/mod_evasive.git ${SRC}/mod_evasive
git clone https://github.com/SpiderLabs/ModSecurity.git ${SRC}/ModSecurity

#过滤出版本 
[[ "${OS_VER}" -eq 6 ]] && MSQV="$(awk -F '/' '/mysql/{print $(NF)}' /usr/local/src/wget-list |sed -e 's/.tar.gz//')" || MSQV="$(awk -F '/' '/mariadb/{print $(NF)}' /usr/local/src/wget-list |sed -e 's/.tar.gz//')"
PHPV="$(awk -F '/' '/php/{print $(NF)}' /usr/local/src/wget-list |sed -e 's/.tar.gz//')"
APAV="$(awk -F '/' '/httpd/{print $(NF)}' /usr/local/src/wget-list |sed -e 's/.tar.gz//')"
ZIPV="$(awk -F '/' '/bzip/{print $(NF)}' /usr/local/src/wget-list |sed -e 's/.tar.gz//')"
ARPV="$(awk -F '/' '/apr-1/{print $(NF)}' /usr/local/src/wget-list |sed -e 's/.tar.gz//')"
ARPU="$(awk -F '/' '/apr-u/{print $(NF)}' /usr/local/src/wget-list |sed -e 's/.tar.gz//')"
PCRV="$(awk -F '/' '/pcre/{print $(NF)}' /usr/local/src/wget-list |sed -e 's/.tar.gz//')"

#解压：
for i in $(ls ${SRC}/*.tar.gz) ;do tar zxf ${i} -C ${SRC}/ ;done

#添加Mysql 用户
useradd -s /sbin/nologin mysql 

#创建mysql 数据目录
[ ! -d "${DATA_DIR}" ] && mkdir -p ${DATA_DIR}

#重命名解压出来的mariadb 目录
 mv ${SRC}/${MSQV}  ${BASE_DIR}

#修改mysql 数据目录和解压目录为mysql
chown -R mysql:mysql ${DATA_DIR} ${BASE_DIR}

#进入mysql 目录
cd ${BASE_DIR}

#初始化mysql:
./scripts/mysql_install_db --datadir=${DATA_DIR} --basedir=${BASE_DIR} --user=mysql --skip-name-resolve

#复制mysql 配置文件
[ "${OS_VER}" -eq 6 ] && yes |cp support-files/my-default.cnf /etc/my.cnf || yes |cp support-files/my-large.cnf /etc/my.cnf

sed -i "s@^# basedir = .....@basedir = ${BASE_DIR}@" /etc/my.cnf
sed -i "s@^# datadir = .....@datadir = ${DATA_DIR}@" /etc/my.cnf
sed -i 's@^# port = .....@port = 3306@' /etc/my.cnf
sed -i 's@^# server_id = .....@server_id = 1@' /etc/my.cnf
sed -i 's@^# socket = .....@socket = /tmp/mysql.sock@' /etc/my.cnf
sed -i 's@^# innodb_buffer_pool_size = 128M@innodb_buffer_pool_size = 128M@' /etc/my.cnf

#创建mariadb 启动脚本文件
if [ "${OS_VER}" -eq 6 ] ;then
    cp ${BASE_DIR}/support-files/mysql.server /etc/init.d/mysqld
    chown -R mysql:mysql /etc/init.d/mysqld
    sed -i "s@^basedir=@basedir=${BASE_DIR}@" /etc/init.d/mysqld
	sed -i "s@^datadir=@datadir=${DATA_DIR}@" /etc/init.d/mysqld
else 
    echo  "[Unit]" > /etc/systemd/system/mysqld.service
    echo  "Description=MySQL Community Server" >> /etc/systemd/system/mysqld.service
    echo  "After=network.target" >> /etc/systemd/system/mysqld.service
    echo  "After=syslog.target" >> /etc/systemd/system/mysqld.service
    
    echo  "[Service]" >> /etc/systemd/system/mysqld.service
    echo  "PIDFile=${DATA_DIR}/mariadb.pid" >> /etc/systemd/system/mysqld.service
    echo  "ExecStart=${BASE_DIR}/bin/mysqld_safe --datadir=/data/mysql --user=mysql" >> /etc/systemd/system/mysqld.service
    echo  "ExecReload=/bin/kill -s HUP \$MAINPID" >> /etc/systemd/system/mysqld.service
    echo  "ExecStop=/bin/kill -s QUIT \$MAINPID" >> /etc/systemd/system/mysqld.service
    echo  "TimeoutSec=600" >> /etc/systemd/system/mysqld.service
    echo  "Restart=always" >> /etc/systemd/system/mysqld.service
    echo  "PrivateTmp=false" >> /etc/systemd/system/mysqld.service
    
    echo  "[Install]" >> /etc/systemd/system/mysqld.service
    echo  "WantedBy=multi-user.target" >> /etc/systemd/system/mysqld.service
fi

#启动mysql 服务
[ "${OS_VER}" -eq 6 ] && service mysqld start || systemctl start mysqld

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

#安装DDOS 防护模块：
/usr/local/apache2/bin/apxs -i -a -c /usr/local/src/mod_evasive/mod_evasive24.c


#配置解析PHP：
#sed -i 's@DirectoryIndex index.html@DirectoryIndex index.html index.php@' /usr/local/apache2/conf/httpd.conf
#sed -i "390i  AddType application/x-httpd-php .php" /usr/local/apache2/conf/httpd.conf
echo "IncludeOptional conf.d/*.conf" >> /usr/local/apache2/conf/httpd.conf
mkdir  /usr/local/apache2/conf.d/
cat << 'eof' > /usr/local/apache2/conf.d/php.conf
<FilesMatch \.php$\>
    SetHandler application/x-httpd-php
</FilesMatch>
AddType text/html .php
DirectoryIndex index.php
eof
sed -i "s@^#ServerName www.example.com:80@ServerName 80@" /usr/local/apache2/conf/httpd.conf

#设置PHP 的测试页面
mv /usr/local/apache2/htdocs/index.html{,.bak}
cat << 'eof' > /usr/local/apache2/htdocs/index.php
<?php
        echo phpinfo();
?>
eof

#创建启动脚本文件：
if [ "${OS_VER}" != 6 ] ;then
    echo "[Unit]" > /etc/systemd/system/httpd.service
    echo "Description=Apache" >> /etc/systemd/system/httpd.service
    echo "After=syslog.target network.target" >> /etc/systemd/system/httpd.service
    
    echo "[Service]" >> /etc/systemd/system/httpd.service
    echo "Type=forking" >> /etc/systemd/system/httpd.service
    echo "ExecStart=/usr/local/apache2/bin/apachectl" >> /etc/systemd/system/httpd.service
    echo "ExecReload=/usr/local/apache2/bin/apachectl -k restart" >> /etc/systemd/system/httpd.service
    echo "ExecStop=/usr/local/apache2/bin/apachectl -k stop" >> /etc/systemd/system/httpd.service
    
    echo "[Install]" >> /etc/systemd/system/httpd.service
    echo "WantedBy=multi-user.target" >> /etc/systemd/system/httpd.service                                             
fi

#进入php 解压目录：
cd ${SRC}/${PHPV}

#配置编译参数：
./configure  --prefix=/usr/local/php  --with-apxs2=/usr/local/apache2/bin/apxs  --with-config-file-path=/usr/local/php/etc --with-mysql=/usr/local/mysql  --with-libxml-dir  --with-gd --with-jpeg-dir  --with-png-dir --with-freetype-dir  --with-iconv-dir --with-zlib-dir  --with-bz2  --with-openssl  --with-mcrypt  --enable-soap  --enable-gd-native-ttf  --enable-mbstring --enable-sockets  --enable-exif  --disable-ipv6 --enable-bcmath --with-mysql-sock=/tmp/mysql.sock --with-mysqli --enable-mysqlnd --with-gettext

#编译：
make

#安装：
make install

#复制php.ini 配置文件
cp ${SRC}/${PHPV}/php.ini-production /usr/local/php/etc/php.ini

#设置MySQL 密码：
/usr/local/mysql/bin/mysqladmin -uroot password "$PASS"

#启动apache服务
[ "${OS_VER}" -eq 6 ] && /usr/local/apache2/bin/apachectl || systemctl start httpd

#开启防火墙的80 端口
if [ "${OS_VER}" -eq 6 ] ;then
    [[ "$(service iptables status)" =~ 'not running' ]] && service iptables start
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT
    service iptables save
else
    [[ -z "$(rpm -qa 'firewalld')" ]] && yum install -y firewalld firewall-config
    [[ -z "$(ps aux|egrep firewalld |egrep -v 'grep')" ]] && systemctl start firewalld
    firewall-cmd --zone=public --permanent --add-rich-rule='rule family="ipv4" port protocol="tcp" port=80 accept'
    firewall-cmd --reload
fi

#设置环境变量：
echo "PATH=\$PATH:/usr/local/apache2/bin:/usr/local/php/bin:/usr/local/php/sbin:/usr/local/mysql/bin" >> /etc/profile