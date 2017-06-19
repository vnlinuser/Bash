#!/usr/bin/env bash

echo -e "\e[31m
==================================================================================
脚本作用：一键安装Redis-3.2.8
注意事项：修改WEBIP 为你真实WEB 服务器IP
使用方法：
==================================================================================
\e[m"
echo
echo -e "\e[31m
=======================================准备开始安装=================================\e[m"

read -p "Please Enter【y】sure you need installtion Redis? :" SURE

if [ "$SURE" != "y" ] ;then echo "You dont want to installtion Redis? Please check your input..." && exit 0 ;fi

echo -e "\e[31m
====================================================================================\e[m"
echo

set -e

#确保系统没有安装redis:
[[ ! -z "$(ps aux|egrep redis |egrep -v 'redis')" ]] && echo -e "\e[31m Redis was installed,Please checked it...\e[m" && exit 1

#定义WEB_SERVER:
WEB_IP='192.168.137.0/24'

#定义系统版本：
OSVER="$(awk '{print $(NF-1)}' /etc/redhat-release |awk -F '.' '{print $1}')"

#软件下载目录：
SRC='/usr/local/src'

#Redis 的下载地址：
URL='http://download.redis.io/releases/redis-3.2.8.tar.gz'

#Redis 版本：
RDV="$(echo $URL |awk -F '/' '{print $(NF)}' |sed -e 's/.tar.gz//')"

#Redis 密码：
PWD="$(openssl rand -base64 16 > ~/.Redis.pwd)"

#安装必要的组件包
yum install -y gcc gcc-c++ autoconf automake m4 readline-devel

#下载Redis
wget -O ${SRC}/${RDV}.tar.gz ${URL}

#解压Redis:
tar zxf ${SRC}/${RDV}.tar.gz -C ${SRC}/

#移动并重命名redis
mv ${SRC}/${RDV} /usr/local/redis

#进入redis 下的 geohash-int 目录，编译
cd /usr/local/redis/deps/geohash-int && make

#进入redis 下的 hiredis 目录，编译及安装
cd /usr/local/redis/deps/hiredis && make && make install

#进入redis 下的jemalloc，编辑及安装
cd /usr/local/redis/deps/jemalloc && ./autogen.sh && make && make install

#进入redis 下的linenoise，编译
cd /usr/local/redis/deps/linenoise && make

#进入redis下的lua 目录，编译及安装
cd /usr/local/redis/deps/lua && make linux && make install

#进入redis 主目录，编译及安装
cd /usr/local/redis &&  make MALLOC=libc && make install

#添加redis 用户
useradd -s /sbin/nologin redis

#创建redis 配置目录，数据目录及日子文件
mkdir -p /data/redis/{conf,data} && touch /var/log/redis.log

#复制配置文件
cp /usr/local/redis/redis.conf /data/redis/conf/

#修改redis 的配置
sed -i "s@^daemonize no@daemonize yes@" /data/redis/conf/redis.conf
sed -i "s@^bind 127.0.0.1@bind 0.0.0.0@" /data/redis/conf/redis.conf
#sed -i "s@^# requirepass foobared@requirepass $(cat ~/.Redis.pwd)@" /data/redis/conf/redis.conf
sed -i 's/^supervised no/supervised systemd/' /data/redis/conf/redis.conf
sed -i 's@^dir ./@dir /data/redis/@' /data/redis/conf/redis.conf
sed -i 's@^logfile ""@logfile "/var/log/redis.log"@' /data/redis/conf/redis.conf
#sed -i 's@^# maxclients 10000@maxclients 100000@' /data/redis/conf/redis.conf

#修改创建的redis 目录和redis.log 文件所属主和组为redis
chown -R redis.redis /data/redis /var/log/redis.log

#修改必要的内核参数：
echo 'net.core.somaxconn = 1024' >> /etc/sysctl.conf
echo 'vm.overcommit_memory = 1' >> /etc/sysctl.conf

#执行sysctl -p
sysctl -p

echo never > /sys/kernel/mm/transparent_hugepage/enabled

cat << 'eof' >> /etc/rc.d/rc.local
echo never > /sys/kernel/mm/transparent_hugepage/enabled
eof

chmod 700  /etc/rc.d/rc.local

#创建redis 启动脚本文件
if [ ${OSVER} -eq 6 ] ;then
    echo '#!/bin/sh' > /etc/init.d/redis
    echo '#' >> /etc/init.d/redis
    echo '# Simple Redis init.d script conceived to work on Linux systems' >> /etc/init.d/redis
    echo '# as it does use of the /proc filesystem.' >> /etc/init.d/redis
    echo '' >> /etc/init.d/redis
    echo '# chkconfig:   2345 90 10' >> /etc/init.d/redis
    echo '# description:  Redis is a persistent key-value database' >> /etc/init.d/redis
    echo '' >> /etc/init.d/redis
    echo 'REDISPORT=6379' >> /etc/init.d/redis
    echo 'EXEC=/usr/local/bin/redis-server' >> /etc/init.d/redis
    echo 'CLIEXEC=/usr/local/bin/redis-cli' >> /etc/init.d/redis
    echo '' >> /etc/init.d/redis
    echo 'PIDFILE=/var/run/redis_${REDISPORT}.pid' >> /etc/init.d/redis
    echo 'CONF="/data/redis/conf/redis.conf"' >> /etc/init.d/redis
    echo '' >> /etc/init.d/redis
    echo 'case "$1" in' >> /etc/init.d/redis
    echo '    start)' >> /etc/init.d/redis
    echo '        if [ -f $PIDFILE ]' >> /etc/init.d/redis
    echo '        then' >> /etc/init.d/redis
    echo '                echo "$PIDFILE exists, process is already running or crashed"' >> /etc/init.d/redis
    echo '        else' >> /etc/init.d/redis
    echo '                echo "Starting Redis server..."' >> /etc/init.d/redis
    echo '                $EXEC $CONF' >> /etc/init.d/redis
    echo '        fi' >> /etc/init.d/redis
    echo '        ;;' >> /etc/init.d/redis
    echo '    stop)' >> /etc/init.d/redis
    echo '        if [ ! -f $PIDFILE ]' >> /etc/init.d/redis
    echo '        then' >> /etc/init.d/redis
    echo '                echo "$PIDFILE does not exist, process is not running"' >> /etc/init.d/redis
    echo '        else' >> /etc/init.d/redis
    echo '                PID=$(cat $PIDFILE)' >> /etc/init.d/redis
    echo '                echo "Stopping ..."' >> /etc/init.d/redis
    echo '                $CLIEXEC -p $REDISPORT shutdown' >> /etc/init.d/redis
    echo '                while [ -x /proc/${PID} ]' >> /etc/init.d/redis
    echo '                do' >> /etc/init.d/redis
    echo '                    echo "Waiting for Redis to shutdown ..."' >> /etc/init.d/redis
    echo '                    sleep 1' >> /etc/init.d/redis
    echo '                done' >> /etc/init.d/redis
    echo '                echo "Redis stopped"' >> /etc/init.d/redis
    echo '        fi' >> /etc/init.d/redis
    echo '        ;;' >> /etc/init.d/redis
    echo '    *)' >> /etc/init.d/redis
    echo '        echo "Please use start or stop as first argument"' >> /etc/init.d/redis
    echo '        ;;' >> /etc/init.d/redis
    echo 'esac' >> /etc/init.d/redis

    chmod 700 /etc/init.d/redis

    service redis start && chkconfig redis on
else
    echo '[Unit]' > /usr/lib/systemd/system/redis.service
    echo 'Description=Redis persistent key-value database' >> /usr/lib/systemd/system/redis.service
    echo 'After=network.target' >> /usr/lib/systemd/system/redis.service
    echo '' >> /usr/lib/systemd/system/redis.service
    echo '[Service]' >> /usr/lib/systemd/system/redis.service
    echo 'User=redis' >> /usr/lib/systemd/system/redis.service
    echo 'Group=redis' >> /usr/lib/systemd/system/redis.service
    echo 'Type=forking' >> /usr/lib/systemd/system/redis.service
    echo '#PIDFile=/var/run/redis_6379.pid' >> /usr/lib/systemd/system/redis.service
    echo 'ExecStart=/usr/local/bin/redis-server /data/redis/conf/redis.conf' >> /usr/lib/systemd/system/redis.service
    echo 'ExecStop=/usr/local/bin/redis-cli shutdown' >> /usr/lib/systemd/system/redis.service
    echo '#ExecReload=/usr/bin/kill -USR2 $MAINPID' >> /usr/lib/systemd/system/redis.service
    echo 'Restart=always' >> /usr/lib/systemd/system/redis.service
    echo '' >> /usr/lib/systemd/system/redis.service
    echo '[Install]' >> /usr/lib/systemd/system/redis.service
    echo 'WantedBy=multi-user.target' >> /usr/lib/systemd/system/redis.service

    systemctl start redis && systemctl enable redis
fi

#开启防火墙的6379 端口
if [ "${OSVER}" -eq 6 ] ;then
    [[ ! -z "$(service iptables status |egrep not)" ]] && service iptables start
    iptables -I INPUT -p tcp -s $WEB_IP --dport 6379 -j ACCEPT
    service iptables save
else
    [[ -z "$(rpm -qa 'firewalld')" ]] && yum install -y firewalld firewall-config
    [[ -z "$(ps aux|egrep firewalld |egrep -v 'grep')" ]] && systemctl start firewalld
    firewall-cmd --zone=public --permanent --add-rich-rule="rule family='ipv4' port protocol='tcp' port=3306 source address=\"${WEB_IP}\" accept"
    firewall-cmd --reload
fi

#redis systemctl 脚本文件参考贴：https://iyaozhen.com/systemd-service-for-redis.html   https://gist.github.com/geschke/ab6afa91b2d9dfcd5c25