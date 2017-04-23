#!/usr/bin/env bash

#脚本作用：在centos 6 或centos 7上一键安装maraidb-galera-cluster 第一个节点
#注意事项：适用脚本前，请提前配置好各节点的计算机名，同时，只需修改设置节点的IP

set -e
set -x

#设置节点：
NODE01='192.168.137.11'
NODE02='192.168.137.12'
NODE03='192.168.137.13'
#NODE04='192.168.137.21'

#定义系统版本：
OS_VER="$(awk '{print $3}' /etc/redhat-release |sed -e 's/.[0-9]//g')"

#设置hosts解析：
if [[ -z "$(egrep $(echo $HOSTNAME) /etc/hosts)" ]] ;then
    echo "${NODE01} node01.com" >> /etc/hosts
    echo "${NODE02} node02.com" >> /etc/hosts
    echo "${NODE03} node03.com" >> /etc/hosts
fi         

#定义mariadb 管理密码
ROOT_PWSS="$(openssl rand -base64 15)" && echo "ROOT:${ROOT_PWSS}" > ~/.Mariadb.pwd
CLUS_PWSS="dbpassword" && echo "CLUS:${CLUS_PWSS}" >> ~/.Mariadb.pwd

#定义集群复制用户：
CLUS_USER='cluster-user'

#定义数据目录：
DATADIR='/data/mysql/data/'
LOGSDIR='/data/mysql/logs'
TMPSDIR='/data/mysql/tmp'
[ ! -d "/data/mysql" ] && mkdir -p ${DATADIR} ${LOGSDIR} ${TMPSDIR}  

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
yum install -y MariaDB-Galera-server MariaDB-client rsync galera

#授权目录：
chown -R mysql:mysql /data/mysql

#编辑配置文件，配置内容如下：
cp /etc/my.cnf{,.bak}
cat << eof > /etc/my.cnf.d/server.cnf
[server]

[mysqld]

[galera]
#query_cache_size              = 0
#binlog_format                 = ROW
#default_storage_engine        = innodb
#innodb_autoinc_lock_mode      = 2
#wsrep_provider                = /usr/lib64/galera/libgalera_smm.so
#wsrep_cluster_address         = "gcomm://${NODE01},${NODE02},${NODE03}"
#wsrep_cluster_name            = 'cluster-01'
#wsrep_node_address            = "$(hostname -I |awk '{print $1}')"
#wsrep_node_name               = "`hostname`"
#wsrep_sst_method              = rsync
#wsrep_sst_auth                = ${CLUS_USER}:${CLUS_PWSS}

[embedded]

[mariadb]
character-set-server           = utf8
datadir                        = ${DATADIR}
pid-file                       = ${DATADIR}/mysql.pid
tmpdir                         = ${TMPSDIR}  
slow_query_log_file            = ${DATADIR}/slow-log
port                           = 3306
log_error                      = ${LOGSDIR}/mysqld.log
log-bin                        = dbs-binlog
log-bin-index                  = dbs-binlog.index
binlog-ignore-db               = mysql
binlog-ignore-db               = information_schema
binlog-ignore-db               = performance_sche
server_id                      = 11
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
innodb_buffer_pool_size        = 300M
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
replicate-ignore-db            = mysql,information_schema,performance_schema
slow_query_log                 = 1
innodb_flush_method            = O_DIRECT
open_files_limit               = 65535

[mariadb-10.0]
eof

cp /etc/my.cnf.d/mysql-clients.cnf{,.bak}
cat << eof >/etc/my.cnf.d/mysql-clients.cnf
[mysql]
socket                         = /var/lib/mysql/mysql.sock
default-character-set          = utf8
port                           = 3306

[mysql_upgrade]

[mysqladmin]

[mysqlbinlog]

[mysqlcheck]

[mysqldump]
quick
max_allowed_packet             = 16M

[mysqlimport]

[mysqlshow]

[mysqlslap]
eof

#删除默认的mysql 目录：
rm -rf /var/lib/mysql

#初始化maraidb:
mysql_install_db --defaults-file=/etc/my.cnf --user=mysql --datadir=${DATADIR}

#替换启动脚本中的datadir
sed -i "s@^datadir=@datadir=${DATADIR}@" /etc/init.d/mysql

#启动mariadb:
service mysql start

#安全配置
mysqladmin -uroot password ${ROOT_PWSS}

#创建集群用户并授权
mysql -uroot -p${ROOT_PWSS} -e "GRANT ALL PRIVILEGES ON *.* TO \"${CLUS_USER}\"@'%' IDENTIFIED BY \"${CLUS_PWSS}\" WITH GRANT OPTION"
mysql -uroot -p${ROOT_PWSS} -e "FLUSH PRIVILEGES"

#停止mysql:
service mysql stop

#确保停止完成：
sleep 5

#启用galera 配置：
sed -i 's@^#@@g' /etc/my.cnf.d/server.cnf

#开启防火墙的端口：
if [ "${OS_VER}" -eq 6 ] ;then
    [[ "$(service iptables status)" =~ "not running" ]] && service iptables start
    iptables -I INPUT -p tcp -s 192.168.137.0/24 -m multiport --dport 3306,4444,4567 -j ACCEPT
    service iptables save
else
    [[ "$(rpm -ql firewalld)" =~ "not installed" ]] && yum install -y firewalld firewall-config
    [[ "$(systemctl status firewalld)" =~ "dead" ]] && systemctl start firewalld
    firewall-cmd --zone=public --permanent --add-rich-rule='rule family="ipv4" port protocol="tcp" port=3306 source address="192.168.137.0/24" accept'
    firewall-cmd --zone=public --permanent --add-rich-rule='rule family="ipv4" port protocol="tcp" port=4444 source address="192.168.137.0/24" accept'
    firewall-cmd --zone=public --permanent --add-rich-rule='rule family="ipv4" port protocol="tcp" port=4567 source address="192.168.137.0/24" accept'
    firewall-cmd --reload
fi

#以集群的方式启动:
service mysql start --wsrep-new-cluster