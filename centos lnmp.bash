#!/usr/bin/env bash

#脚本作用：
#注意事项：
#脚本版本：

set -e
set -x

#定义系统版本：
OS_VER="$(awk '{print $(NF-1)}' /etc/redhat-release |awk -F '.' '{print $1}')"

#安装扩展源：
yum install -y epel-release

#定义软件下载目录
SRC='/usr/local/src'

#定义mysql root 密码
PASS="$(openssl rand -base64 14)" && echo ${PASS} > ~/.Mariadb.pass

#定义mysql 数据目录：
DATA_DIR='/data/mysql'
BASE_DIR='/usr/local/mysql'

#安装必要的包
yum install -y wget vim telnet iotop gcc gcc-c++ autoconf automake bzip2-devel git openssl openssl-devel libtool geoip-devel gd-devel systemd-devel libxml2-devel curl-devel libmcrypt-devel

#创建下载地址列表
if [ "${OS_VER}" -eq 6 ] ;then
    echo "https://cdn.mysql.com//Downloads/MySQL-5.6/mysql-5.6.35-linux-glibc2.5-x86_64.tar.gz" > $SRC/wget-list
else
    echo "http://sgp1.mirrors.digitalocean.com/mariadb//mariadb-10.1.22/bintar-linux-glibc_214-x86_64/mariadb-10.1.22-linux-glibc_214-x86_64.tar.gz" > $SRC/wget-list
fi
echo "http://cn2.php.net/distributions/php-5.6.30.tar.gz" >> $SRC/wget-list
echo "https://nginx.org/download/nginx-1.10.3.tar.gz" >> ${SRC}/wget-list
echo "https://ftp.pcre.org/pub/pcre/pcre-8.40.tar.gz" >> $SRC/wget-list


#下载软件包：
wget -i ${SRC}/wget-list -P ${SRC}/

##进入下载目录：
cd ${SRC}

##克隆nginx 一些组件
git clone https://github.com/FRiCKLE/ngx_cache_purge.git
git clone https://github.com/yaoweibin/nginx_upstream_check_module.git
git clone https://github.com/gperftools/gperftools.git
git clone git://git.sv.gnu.org/libunwind.git


#进入libunwind 目录：
cd ${SRC}/libunwind

#执行下面的命令生成configure 文件
./autogen.sh

#配置编译参数：
./configure

#编译及安装：
make && make install

#进入gperftools 目录：
cd ${SRC}/gperftools

#执行下面的命令生成configure
./autogen.sh

#配置编译参数：
./configure

#编译及安装：
make && make install

#过滤出版本
[[ "${OS_VER}" -eq 6 ]] && MSQV="$(awk -F '/' '/mysql/{print $(NF)}' ${SRC}/wget-list |sed -e 's/.tar.gz//')" || MSQV="$(awk -F '/' '/mariadb/{print $(NF)}' ${SRC}/wget-list |sed -e 's/.tar.gz//')"
PHPV="$(awk -F '/' '/php/{print $(NF)}' ${SRC}/wget-list |sed -e 's/.tar.gz//')"
NGXV="$(awk -F '/' '/nginx/{print $(NF)}' ${SRC}/wget-list |sed -e 's/.tar.gz//')"
PCRV="$(awk -F '/' '/pcre/{print $(NF)}' ${SRC}/wget-list |sed -e 's/.tar.gz//')"

#解压：
for i in $(ls ${SRC}/*.tar.gz) ;do
    tar zxf ${i} -C ${SRC}/
done

#添加Mysql 用户
useradd -s /sbin/nologin mysql

#创建mysql 数据目录
mkdir -p ${DATA_DIR}  /data/nginx/logs

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
    echo  "ExecReload=/bin/kill -s HUP $MAINPID" >> /etc/systemd/system/mysqld.service
    echo  "ExecStop=/bin/kill -s QUIT $MAINPID" >> /etc/systemd/system/mysqld.service
    echo  "TimeoutSec=600" >> /etc/systemd/system/mysqld.service
    echo  "Restart=always" >> /etc/systemd/system/mysqld.service
    echo  "PrivateTmp=false" >> /etc/systemd/system/mysqld.service
    
    echo  "[Install]" >> /etc/systemd/system/mysqld.service
    echo  "WantedBy=multi-user.target" >> /etc/systemd/system/mysqld.service
fi

#启动mysql 服务
[ "${OS_VER}" -eq 6 ] && service mysqld start || systemctl start mysqld

#进入Nginx 解压目录：
cd ${SRC}/${NGXV}

#配置编译参数：
./configure --prefix=/usr/local/nginx --with-select_module --with-http_ssl_module --with-http_realip_module --with-http_addition_module  --with-http_image_filter_module --with-http_geoip_module  --with-http_sub_module --with-http_dav_module --with-http_flv_module --with-http_mp4_module --with-http_gzip_static_module  --with-http_auth_request_module  --with-http_random_index_module --with-stream --with-stream_ssl_module --with-google_perftools_module --with-pcre=${SRC}/${PCRV} --add-module=${SRC}/nginx_upstream_check_module  --add-module=${SRC}/ngx_cache_purge

#编译：
make

#编译安装：
make install

#创建启动脚本文件：
if [ "${OS_VER}" -ne 6 ] ;then
    echo "[Unit]" > /etc/systemd/system/nginx.service
    echo "Description=Nginx" >> /etc/systemd/system/nginx.service
    echo "After=syslog.target network.target" >> /etc/systemd/system/nginx.service
    
    echo "[Service]" >> /etc/systemd/system/nginx.service
    echo "Type=forking" >> /etc/systemd/system/nginx.service
    echo "ExecStart=/usr/local/nginx/sbin/nginx" >> /etc/systemd/system/nginx.service
    echo "ExecReload=/usr/local/nginx/sbin/nginx -s reload" >> /etc/systemd/system/nginx.service
    echo "ExecStop=/usr/local/nginx/sbin/nginx -s quit" >> /etc/systemd/system/nginx.service
    
    echo "[Install]" >> /etc/systemd/system/nginx.service
    echo "WantedBy=multi-user.target" >> /etc/systemd/system/nginx.service
fi

#备份原有配置文件：
mv /usr/local/nginx/conf/nginx.conf{,.bak}

#修改配置文件
cat << 'eof' > /usr/local/nginx/conf/nginx.conf
worker_processes  1;
events {
    worker_connections  1024;
}
http {
    include       mime.types;
    default_type  application/octet-stream;
    sendfile        on;
    keepalive_timeout  65;
    server {
        listen       80;
        server_name  localhost;
        location / {
            root   html;
            index  index.html index.htm index.php;
        }
        error_page   500 502 503 504  /50x.html;
        location = /50x.html {
            root   html;
        }
        location ~ \.php$ {
            root           html;
            fastcgi_pass   127.0.0.1:9000;
            fastcgi_index  index.php;
            fastcgi_param  SCRIPT_FILENAME  $document_root$fastcgi_script_name;
            include        fastcgi_params;
        }
    }
}
eof

#创建php 的测试页面
cat << 'eof' > /usr/local/nginx/html/index.php
<?php
        echo phpinfo();
?>
eof

#将默认的页面重命名
mv /usr/local/nginx/html/index.html /usr/local/nginx/html/index.html.bak

#做软连接，确保Nginx 能调用到 google perftools
ln -s /usr/local/lib/libprofiler.so.0 /usr/lib64/
ln -s /usr/local/lib/libunwind.so.8 /usr/lib64/

#启动nginx:
[[ "${OS_VER}" -eq 6 ]] && /usr/local/nginx/sbin/nginx || systemctl start nginx

#进入php 解压目录：
cd ${SRC}/${PHPV}

#添加普通用户php-fpm
useradd -s /sbin/nologin php-fpm

#配置编译参数：
./configure --prefix=/usr/local/php --enable-fpm --with-fpm-user=php-fpm  --with-fpm-group=php-fpm --enable-debug --with-config-file-path=/usr/local/php/etc --with-libxml-dir  --with-zlib-dir --enable-bcmath --with-curl --enable-dba --with-pcre-dir --enable-ftp --with-jpeg-dir --with-png-dir --with-freetype-dir  --enable-gd-native-ttf  --with-gettext --enable-mbstring  --with-mcrypt  -with-openssl  --with-mysqli --enable-soap --with-iconv-dir --with-gd --enable-mysqlnd --with-pear --enable-sockets --enable-exif  --disable-ipv6

#编译：
make

#安装：
make install

#复制php 和php-fpm 主配置文件
cp php.ini-production /usr/local/php/etc/php.ini
cp /usr/local/php/etc/php-fpm.conf.default /usr/local/php/etc/php-fpm.conf

#创建php-fpm 启动脚本
#cp sapi/fpm/php-fpm.service /etc/systemd/system/
if [ ${OS_VER} -eq 6 ] ;then
    cp sapi/fpm/init.d.php-fpm.in /etc/init.d/php-fpm 
    sed -i 's#^prefix=@prefix@#prefix=/usr/local/php#' /etc/init.d/php-fpm 
    sed -i 's#^exec_prefix=@exec_prefix@#exec_prefix=/usr/local/php#' /etc/init.d/php-fpm 
    sed -i 's#^php_fpm_BIN=@sbindir@/php-fpm#php_fpm_BIN=/usr/local/php/sbin/php-fpm#' /etc/init.d/php-fpm 
    sed -i 's#^php_fpm_CONF=@sysconfdir@/php-fpm.conf#php_fpm_CONF=/usr/local/php/etc/php-fpm.conf#' /etc/init.d/php-fpm 
    sed -i 's#^php_fpm_PID=@localstatedir@/run/php-fpm.pid#php_fpm_PID=/usr/local/php/var/run/php-fpm.pid#' /etc/init.d/php-fpm 
    chmod 755  /etc/init.d/php-fpm 
else
    echo "[Unit]" > /etc/systemd/system/php-fpm.service

    echo "Description=The PHP FastCGI Process Manager" >> /etc/systemd/system/php-fpm.service
    echo "After=syslog.target network.target" >> /etc/systemd/system/php-fpm.service
    
    echo "[Service]" >> /etc/systemd/system/php-fpm.service
    echo "Type=simple" >> /etc/systemd/system/php-fpm.service
    echo "PIDFile=/usr/local/php/php-fpm.pid" >> /etc/systemd/system/php-fpm.service
    echo "ExecStart=/usr/local/php/sbin/php-fpm --nodaemonize --fpm-config /usr/local/php/etc/php-fpm.conf" >> /etc/systemd/system/php-fpm.service
    echo "ExecReload=/bin/kill -USR2 $MAINPID" >> /etc/systemd/system/php-fpm.service
    
    echo "[Install]" >> /etc/systemd/system/php-fpm.service
    echo "WantedBy=multi-user.target" >> /etc/systemd/system/php-fpm.service
fi

#启动php-fpm
[[ "${OS_VER}" -eq 6 ]] && service php-fpm start || systemctl start php-fpm

#设置mariadb 密码：
/usr/local/mysql/bin/mysqladmin -uroot password ${PASS}

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
echo "PATH=$PATH:/usr/local/nginx/sbin:/usr/local/php/bin:/usr/local/php/sbin:/usr/local/mysql/bin" >> /etc/profile