#!/usr/bin/env bash

echo -e "\e[31m
==================================================================================
脚本作用：一键安装MySQL-5.6 或者 MariaDB-10.1
注意事项：修改WEB_HOST 为你真实WEB 服务器IP
==================================================================================
\e[m"
echo
echo -e "\e[31m
=======================================准备开始安装=================================\e[m"

read -p "Please Enter【y】sure you need installtion MySQL or MariaDB? :" SURE

if [ "$SURE" != "y" ] ;then echo "You dont want to installtion MySQL or MariaDB? Please check your input..." && exit 0 ;fi

echo -e "\e[31m
====================================================================================\e[m"
echo

set -e

#确保系统没有安装MySQL 或者 Mariadb
[ ! -z "$(ps aux|grep mysql|egrep -v grep)" -o ! -z "$(ss -lntp |egrep 3306)" ] && echo "MySQL or MariaDB was installed,please checked it ..." && exit 1

#设置$1
[[ -z "${1}" ]] && echo "Please enter your webserver ip address,it's access this database server ..." && exit 2

#定义系统版本：
OS_VER="$(awk '{print $(NF-1)}' /etc/redhat-release |awk -F '.' '{print $1}')"

#定义mysql 数据目录所属用户：
USER='mysql'

#定义数据存储目录：
DATADIR='/data/mysql'

#定义mariadb 解压后存放的目录
BASEDIR='/usr/local/mysql'

#定义管理员密码：
PASSWD="$(openssl rand -base64 14)"
echo "${PASSWD}" > /root/.Mariadb_PWD.txt

#定义程序主机
#WEB_HOST='$1'

#安装必要的组建：
yum install -y wget gcc gcc-c++ vim telnet ntp libaio libaio-devel

#设置时区
#yes |cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

#在线同步下时间
#ntpdate time.windows.com

#定义mariadb 下载地址
if [ ${OS_VER} -eq 6 ] ;then
    DBURL='https://cdn.mysql.com//Downloads/MySQL-5.6/mysql-5.6.35-linux-glibc2.5-x86_64.tar.gz'
else
    DBURL='http://kartolo.sby.datautama.net.id/mariadb//mariadb-10.1.22/bintar-linux-glibc_214-x86_64/mariadb-10.1.22-linux-glibc_214-x86_64.tar.gz'
fi

#根据URL 定义版本：
#DBVERSION="$(echo ${DBURL} |awk -F '/' '{print $NF}' |sed -e 's/.tar.gz//')"
#DBVERSION="$(echo ${DBURL##*/} |cut -f1-3 -d '.')"
DBVERSION="$(echo ${DBURL##*/} |sed -e 's/.tar.gz//')"

#下载mariadb
wget -O /usr/local/src/${DBVERSION}.tar.gz  ${DBURL}

#解压mariadb
tar zxf /usr/local/src/${DBVERSION}.tar.gz -C /usr/local/src/

#移动解压目并重命名
mv /usr/local/src/${DBVERSION} ${BASEDIR}

#添加用户名：
useradd -s /sbin/nologin ${USER}

#创建数据目录
[[ ! -d ${DATADIR} ]] && mkdir -p ${DATADIR} || exit 1

#修改数据目录所属主和组为mysql
chown -R ${USER}:${USER} ${DATADIR}

#进入mariadb 目录
cd ${BASEDIR}

#初始化mairadb
./scripts/mysql_install_db --basedir=${BASEDIR} --datadir=${DATADIR} --user=${USER} --skip-name-resolve  --defaults-file=/etc/my.cnf

#覆盖系统默认的my.cnf 文件
cp /etc/my.cnf{,.bak}
cat << eof > /etc/my.cnf
[mysql]
socket                         = /tmp/mysql.sock
default-character-set          = utf8mb4
port                           = 3306

[mysqld]
character-set-server           = utf8mb4
datadir                        = ${DATADIR}
pid-file                       = ${DATADIR}/mysql.pid
#tmpdir                        = ${TMPSDIR}
slow_query_log_file            = ${DATADIR}/slow-log
bind                           = 0.0.0.0
port                           = 3306
socket                         = /tmp/mysql.sock
log_error                      = ${DATADIR}/mysqld.log
log-bin                        = dbs-binlog
log-bin-index                  = dbs-binlog.index
binlog-ignore-db               = mysql
binlog-ignore-db               = information_schema
binlog-ignore-db               = performance_sche
server_id                      = 1
max_relay_log_size             = 0
read_rnd_buffer_size           = 16M
read_buffer_size               = 6M
sort_buffer_size               = 6M
slave_net_timeout              = 5
table_definition_cache         = 4096
table_open_cache               = 4096
thread_cache_size              = 64
thread_stack                   = 192K
query_cache_limit              = 4M
query_cache_min_res_unit       = 2k
query_cache_type               = 1
join_buffer_size               = 2M
tmp_table_size                 = 256M
interactive_timeout            = 100
max_connections                = 4500
max_connect_errors             = 3000
max_allowed_packet             = 64M
wait_timeout                   = 100
key_buffer_size                = 256M
myisam_sort_buffer_size        = 128M
myisam_repair_threads          = 1
bulk_insert_buffer_size        = 64M
innodb_buffer_pool_size        = 1024M
innodb_log_files_in_group      = 3
innodb_log_file_size           = 512M
innodb_file_per_table          = 1
innodb_file_format             = Barracuda
innodb_lock_wait_timeout       = 15
innodb_flush_log_at_trx_commit = 2
innodb_thread_concurrency      = 24
innodb_log_buffer_size         = 16M
innodb_max_dirty_pages_pct     = 90
innodb_strict_mode             = 1
innodb_read_only               = 0
expire_logs_days               = 7
relay_log_space_limit          = 128m
server_id                      = 109
sync_binlog                    = 1
replicate-ignore-db            = mysql
replicate-ignore-db            = information_schema
replicate-ignore-db            = performance_schema
slow_query_log                 = 1
innodb_flush_method            = O_DIRECT
open_files_limit               = 65535

[mysqldump]
quick
max_allowed_packet             = 16M
eof

#创建MySQL or MariaDB 的启动脚本文件
if [ "${OS_VER}" -eq 6 ] ;then
    cp ${BASEDIR}/support-files/mysql.server /etc/init.d/mysqld
    chown -R mysql:mysql /etc/init.d/mysqld
    sed -i "s@^basedir=@basedir=${BASEDIR}@" /etc/init.d/mysqld
    sed -i "s@^datadir=@datadir=${DATADIR}@" /etc/init.d/mysqld
else
    echo  "[Unit]" > /usr/lib/systemd/system/mysqld.service
    echo  "Description=MySQL Community Server" >> /etc/systemd/system/mysqld.service
    echo  "After=network.target" >> /etc/systemd/system/mysqld.service
    echo  "After=syslog.target" >> /etc/systemd/system/mysqld.service
    echo  ""
    echo  "[Service]" >> /etc/systemd/system/mysqld.service
    echo  "PIDFile=${DATADIR}/mariadb.pid" >> /etc/systemd/system/mysqld.service
    echo  "ExecStart=${BASEDIR}/bin/mysqld_safe --datadir=${DATADIR} --user=mysql" >> /etc/systemd/system/mysqld.service
    echo  "ExecReload=/bin/kill -s HUP \$MAINPID" >> /etc/systemd/system/mysqld.service
    echo  "ExecStop=/bin/kill -s QUIT \$MAINPID" >> /etc/systemd/system/mysqld.service
    echo  "TimeoutSec=600" >> /etc/systemd/system/mysqld.service
    echo  "Restart=always" >> /etc/systemd/system/mysqld.service
    echo  "PrivateTmp=false" >> /etc/systemd/system/mysqld.service
    echo  ""
    echo  "[Install]" >> /etc/systemd/system/mysqld.service
    echo  "WantedBy=multi-user.target" >> /etc/systemd/system/mysqld.service
fi

#启动MySQL or MariaDB 服务
[[ "${OS_VER}" -eq 6 ]] && service mysqld start || systemctl start mysqld

#暂停5秒
sleep 5

#创建管理员密码：
/usr/local/mysql/bin/mysqladmin -uroot password "${PASSWD}"

#开启防火墙的80 端口
if [ "${OS_VER}" -eq 6 ] ;then
    [[ -z "(ps aux|egrep iptables |egrep -v 'grep')" ]] && service iptables start
    iptables -I INPUT -p tcp -s $1 --dport 3306 -j ACCEPT
    service iptables save
else
    [[ -z "$(rpm -qa 'firewalld')" ]] && yum install -y firewalld firewall-config
    [[ -z "$(ps aux|egrep firewalld |egrep -v 'grep')" ]] && systemctl start firewalld
    firewall-cmd --zone=public --permanent --add-rich-rule="rule family='ipv4' port protocol='tcp' port=3306 sourcec address=\"$1\" accept"
    firewall-cmd --reload
fi

#设置环境变量
echo "PATH=\${PATH}:/usr/local/mysql/bin/" >> /etc/profile