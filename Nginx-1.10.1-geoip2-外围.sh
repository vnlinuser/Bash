#!/usr/bin/env bash

echo -e "\e[31m
==================================================================================
脚本作用：一键安装nginx 代理服务器）
注意事项：修改NGINX URL 地址及UPSTREAM 后端服务器地址，以便安装理想版本
==================================================================================
\e[m"

read -p "Would you want to install Nginx-1.10.1 for proxy? " A
[[ "${A}" != "Y" ]] && echo "Plaese enter 【Y】 to install.."

set -e

#检测服务器是否有80或者443 端口：
[[ ! -z "$(ss -lntp |egrep ':80|:443')" ]] && echo -e "\e[31mServer was installed WEB service,please checking it...\e[m" && exit 0

#定义软件下载路径：
SRC='/usr/local/src'

#定义系统版本：
OS_VER="$(awk '{print $(NF-1)}' /etc/redhat-release |awk -F '.' '{print $1}')"

#安装扩展源：
yum install -y epel-release

#安装必要的组件：
yum install -y gcc gcc-c++ pcre zlib pcre-devel openssl-devel xml2 libxslt-devel gunzip libxslt libxml2 gd gd-devel geoip geoip-devel wget git m4 autoconf automake gettext libtool

#添加系统用户nginx，不允许登录系统
useradd -s /sbin/nologin nginx

#创建数据缓存和log 存放目录，并授权目录的所属主和组为nginx：
mkdir -p /data/nginx/{tmp,logs} && chown -R nginx.nginx /data/nginx/

#从github 克隆所需的模块：
git clone https://github.com/FRiCKLE/ngx_cache_purge.git ${SRC}/ngx_cache_purge
git clone https://github.com/yaoweibin/nginx_upstream_check_module.git ${SRC}/nginx_upstream_check_module
git clone https://github.com/zorgnax/libtap.git ${SRC}/libtap
git clone https://github.com/maxmind/libmaxminddb.git ${SRC}/libmaxminddb
git clone https://github.com/leev/ngx_http_geoip2_module ${SRC}/ngx_http_geoip2_module

#GEOIP2 所支持的数据文件
wget -O ${SRC}/GeoLite2-Country.mmdb.gz http://geolite.maxmind.com/download/geoip/database/GeoLite2-Country.mmdb.gz
wget -O ${SRC}/GeoLite2-City.mmdb.gz http://geolite.maxmind.com/download/geoip/database/GeoLite2-City.mmdb.gz

#解压数据文件
gunzip -q ${SRC}/GeoLite2-Country.mmdb.gz -d ${SRC}/ && echo $?
gunzip -q ${SRC}/GeoLite2-City.mmdb.gz -d ${SRC}/ && echo $?

#复制libtap 到 libmaxminddb
ln -s ${SRC}/libtap ${SRC}/libmaxminddb/
ln -s ${SRC}/libtap/* ${SRC}/libmaxminddb/t/libtap/

#从官方下载nginx
#wget -O /usr/local/src/nginx-1.10.1.tar.gz http://nginx.org/download/nginx-1.10.1.tar.gz
#echo "http://nginx.org/download/nginx-1.10.1.tar.gz" > ${SRC}/wget-list
NGURL='http://nginx.org/download/nginx-1.10.1.tar.gz'

#定义NGINX 的版本
#NGX_VER="$(awk -F '/' '/nginx/{print $(NF)}' ${SRC}/wget-list |sed -e 's/.tar.gz//')"
NGX_VER="$(echo ${URL##*/} |cut -f1-3 -d '.')"

#下载NGINX：
#wget -i ${SRC}/wget-list -P ${SRC}/
wget -O ${SRC}/${NGX_VER}.tar.gz $NGURL

#解压nginx
tar zxf ${SRC}/${NGX_VER}.tar.gz -C ${SRC}/

#进入libmaxminddb 目录
cd ${SRC}/libmaxminddb/
./bootstrap
./configure
make && make install

#指定libmaxminddb.so.0 模块路径
echo '/usr/local/lib/' >> /etc/ld.so.conf && ldconfig

#进入解压目录
cd ${SRC}/${NGX_VER}

#配置编译参数
./configure  --prefix=/usr/local/nginx --user=nginx --group=nginx --with-poll_module --with-http_ssl_module --with-http_v2_module --with-http_realip_module --with-http_addition_module --with-http_xslt_module --with-http_image_filter_module --with-http_geoip_module=dynamic --with-http_gunzip_module --with-http_gzip_static_module --with-http_stub_status_module --with-http_auth_request_module --with-http_sub_module --with-http_dav_module  --http-client-body-temp-path=/data/nginx/tmp/body --http-proxy-temp-path=/data/nginx/tmp/proxy --with-stream=dynamic --with-stream_ssl_module --with-pcre --add-module=${SRC}/nginx_upstream_check_module  --add-module=${SRC}/ngx_cache_purge --add-dynamic-module=${SRC}/ngx_http_geoip2_module
#编译
make

#安装
make install

#备份nginx 主配置文件：
mv /usr/local/nginx/conf/nginx.conf{,.$(date +%F)_bak}

#重新配置nginx 文件
cat << 'eof' > /usr/local/nginx/conf/nginx.conf
#启动进程,通常设置成和cpu的数量相等
worker_processes  1;

#一个nginx进程打开的最多文件描述符数目，理论值应该是最多打开文件数（系统的值ulimit -n）与nginx进程数相除
#但是nginx分配请求并不均匀，所以建议与ulimit -n的值保持一致。
worker_rlimit_nofile 65535;

#动态加载模块
load_module modules/ngx_stream_module.so;
load_module modules/ngx_http_geoip_module.so;
load_module modules/ngx_http_geoip2_module.so;

#工作模式及连接数上限
events {
    #优化同一时刻只有一个请求而避免多个睡眠进程被唤醒的设置，on为防止被同时唤醒，默认为off，因此nginx刚安装完以后要进行适当的优化。
    accept_mutex on;

    #打开同时接受多个新网络连接请求的功能。
    multi_accept on;

    #参考事件模型，use [ kqueue | rtsig | epoll | /dev/poll | select | poll ];
    #epoll模型是Linux 2.6以上版本内核中的高性能网络I/O模型，如果跑在FreeBSD上面，就用kqueue模型。
    use   epoll;
    #单个进程最大连接数（最大连接数=连接数*进程数）
    worker_connections  10240;
}

#全局错误日志定义类型，[ debug | info | notice | warn | error | crit ]
error_log /usr/local/nginx/logs/error.log info;

#进程文件
pid /usr/local/nginx/logs/nginx.pid;

#全局配置：
http {
    #文件扩展名与文件类型映射表
    include mime.types;
    #默认文件类型
    default_type  application/octet-stream;

    #默认编码
    charset utf-8;

    #sendfile 指令指定 nginx 是否调用 sendfile 函数（zero copy 方式）来输出文件，对于普通应用，
    #必须设为 on,如果用来进行下载等应用磁盘IO重负载应用，可设置为 off，以平衡磁盘与网络I/O处理速度，降低系统的uptime.
    sendfile on;
    #Nginxg工作进程每次调用sendfile()传输的数据最大不能超出这个值，默认值为0表示无限制，可以设置在http/server/location模块中。
    sendfile_max_chunk 512k;

    #防止网络阻塞
    tcp_nopush on;
    tcp_nodelay on;

    #关闭服务器版本信息：
    server_tokens off;

    #连接超时时间
    keepalive_timeout  65;

    #日志格式配置
    log_format  main  '$remote_addr - $remote_user [$time_local] "$request_method $scheme://$host$request_uri $server_protocol" '
                '"$upstream_addr" "$upstream_cache_status"'
                '$status $body_bytes_sent "$http_referer" '
                '"$http_user_agent" "$http_x_forwarded_for" $request_time $upstream_response_time $geoip2_data_city_names $geoip2_data_country_code';

    #访问日志：
    access_log /usr/local/nginx/logs/access.log main;

    #限制同一个IP在同一时间内的请求次数：
    #增加limit_conn_zone；$binary_remote_addr:二进制远程地址；zone=addr:10m :定义zone 的名字为addr
    #并为这个zone分配10M内存，用来存储会话（二进制远程地址），1m内存可以保存16000会话
    #增加limit_rq_zone,针对客户端；rate=1r/s:在一秒内只允许同一个IP一次请求，否则返回自定义的状态 444(默认为503)
    limit_req_zone $binary_remote_addr zone=perip:10m rate=10r/s;
    limit_req_status 444;

    #设置请求头和请求体(各自)的超时时间
    client_header_timeout 3m;
    client_body_timeout 3m;
    #设定请求缓冲
    client_header_buffer_size 4k;
    large_client_header_buffers 8 4k;
    #上传文件大小限制，如果请求大于指定的值，客户端将收到一个"Request Entity Too Large" (413)错误。
    client_max_body_size 10m;
    #缓冲区代理缓冲用户端请求的最大字节数
    client_body_buffer_size 256k;
    client_body_temp_path /data/nginx/tmp 1 2;

    #启用超时重连接：
    reset_timedout_connection on;

    #指定客户端的响应超时时间。这个设置不会用于整个转发器，而是在两次客户端读取操作之间。
    #如果在这段时间内，客户端没有读取任何数据，nginx就会关闭连接
    send_timeout 3m;

    #连接分配一个内存池，初始大小默认为256字节
    connection_pool_size 256;

    #为每个请求分配的内存池，内存池用于小配额内存块
    #如果一个块大于内存池或者大于分页大小，那么它将被分配到内存池之外，
    #如果位于内存池中较小的分配量没有足够的内存，那么将分配一个相同内存池大小的新块
    request_pool_size 4k;
    output_buffers 4 32k;
    postpone_output 1460;

    #启用gzip 功能
    gzip on;
    #最小压缩的页面，如果页面过于小，可能会越压越大，这里规定大于1K的页面才启用压缩
    gzip_min_length 1k;
    #设置系统获取几个单位的缓存用于存储gzip的压缩结果数据流；4 16k代表以16k为单位，安装原始数据大小以16k为单位的4倍申请内存
    gzip_buffers 4 16k;
    #压缩级别，1压缩比最小处理速度最快，9压缩比最大但处理最慢，同时也最消耗CPU,一般设置为3就可以了
    gzip_comp_level 5;
    #识别http的协议版本(1.0/1.1)
    gzip_http_version 1.1;
    #匹配mime类型进行压缩，无论是否指定,”text/html”类型总是会被压缩的
    gzip_types text/plain application/x-javascript text/css text/htm application/xml;
    #和http头有关系，加个vary头，给代理服务器用的，有的浏览器支持压缩，有的不支持，
    #所以避免浪费不支持的也压缩，所以根据客户端的HTTP头来判断，是否需要压缩
    gzip_vary on;
    #nginx 做前端代理时启用该选项，表示无论后端服务器的headers头返回什么信息，都无条件启用压缩
    #gzip_proxied any;

    #开缓存的同时也指定了缓存最大数目，以及缓存的时间。
    #我们可以设置一个相对高的最大时间，这样我们可以在它们不活动超过20秒后清除掉。
    open_file_cache max=100000 inactive=20s;
    #在open_file_cache中指定检测正确信息的间隔时间
    open_file_cache_valid 30s;
    #定义了open_file_cache中指令参数不活动时间期间里最小的文件数。
    open_file_cache_min_uses 2;
    #定了当搜索一个文件时是否缓存错误信息，也包括再次给配置中添加文件。
    #我们也包括了服务器模块，这些是在不同文件中定义的。
    #如果你的服务器模块不在这些位置，你就得修改这一行来指定正确的位置。
    open_file_cache_errors on;

    #设置用于保存各种key（比如当前连接数）的共享内存的参数。
    #5m就是5兆字节，这个值应该被设置的足够大以存储（32K*5）32byte状态或者（16K*5）64byte状态
    limit_conn_zone $binary_remote_addr zone=addr:5m;
    #为给定的key设置最大连接数。这里key是addr，我们设置的值是100，也就是说我们允许每一个IP地址最多同时打开有100个连接。
    limit_conn addr 20;

    #FastCGI相关参数是为了改善网站的性能：减少资源占用，提高访问速度。下面参数看字面意思都能理解。
    #fastcgi_connect_timeout 300;
    #fastcgi_send_timeout 300;
    #fastcgi_read_timeout 300;
    #fastcgi_buffer_size 64k;
    #fastcgi_buffers 4 64k;
    #fastcgi_busy_buffers_size 128k;
    #fastcgi_temp_file_write_size 128k;
    #fastcgi_cache_path /dev/shm/cache levels=1:2 keys_zone=fastcgi:250m inactive=1d max_size=1G;
    #fastcgi_temp_path  /dev/shm/tmp;
    #fastcgi_cache_key "$scheme$request_method$host$request_uri";
    #fastcgi_cache_use_stale error timeout invalid_header http_500;
    ##忽略一切nocache申明，避免不缓存伪静态等
    #fastcgi_ignore_headers Cache-Control Expires Set-Cookie;
    #fastcgi_intercept_errors on;

    #proxy_intercept_errors off;
    proxy_redirect off;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    #后端的Web服务器可以通过X-Forwarded-For获取用户真实IP
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    #nginx跟后端服务器连接超时时间(代理连接超时)
    proxy_connect_timeout      240;
    #后端服务器数据回传时间(代理发送超时)
    proxy_send_timeout         240;
    #连接成功后，后端服务器响应时间(代理接收超时)
    proxy_read_timeout         240;
    #设置代理服务器（nginx）保存用户头信息的缓冲区大小
    proxy_buffer_size        128k;
    #proxy_buffers缓冲区，网页平均在256k以下的设置
    proxy_buffers           16 256k;
    #高负荷下缓冲大小（proxy_buffers*2）
    proxy_busy_buffers_size 512k;
    #设定缓存文件夹大小，大于这个值，将从upstream服务器传
    proxy_temp_file_write_size 1024m;
    #proxy_ignore_client_abort  on;
    proxy_headers_hash_max_size 1024;
    proxy_headers_hash_bucket_size 128;
    proxy_next_upstream error timeout invalid_header http_500 http_503 http_404 http_502 http_504;
    #proxy_set_header Destination $fixed_destination;
    proxy_set_header Web-Server-Type nginx;
    #反向代理临时文件存放目录：
    proxy_temp_path /dev/shm/;
    #反向代理缓存文件存放目录：
    proxy_cache_path /dev/shm/cache levels=1:2 keys_zone=cache_one:500m inactive=1d max_size=30g;

    #GEOIP2 国家：
    geoip2 /usr/local/src/GeoLite2-Country.mmdb {
        $geoip2_data_continent_code default=AS continent code;
        $geoip2_data_continent_names  continent names en;
        $geoip2_data_country_code default=CN country iso_code;
        $geoip2_data_country_name country names en;
    }
    fastcgi_param CONTINENT_CODE $geoip2_data_continent_code;
    fastcgi_param CONTINENT_NAMES $geoip2_data_continent_names;
    fastcgi_param COUNTRY_CODE $geoip2_data_country_code;
    fastcgi_param COUNTRY_NAME $geoip2_data_country_name;

    #GEOIP2 城市：
    geoip2 /usr/local/src/GeoLite2-City.mmdb {
        $geoip2_data_subdivisions_names subdivisions names en;
        $geoip2_data_city_names default=Xiamen city names en;
    }
    fastcgi_param SUBDIVISIONS_NAMES $geoip2_data_subdivisions_names;
    fastcgi_param CITY_NAMES    $geoip2_data_city_names;

    include /usr/local/nginx/conf.d/*.conf;
}

##TCP 代理配置模板：
#stream {
#    #代理PG
#    upstream postgresql {
#        server 192.168.11.7:1921 weight=1 max_fails=3 fail_timeout=10s;
#    }
#
#    server {
#        listen 1921;
#        proxy_connect_timeout 1m;
#        proxy_pass postgresql;
#    }
#}
eof

#创建加载配置目录：
mkdir /usr/local/nginx/conf.d

#创建一个默认的虚拟主机配置：
cat << 'eof' > /usr/local/nginx/conf.d/proxy.conf
#负载均衡
upstream  tomcat-game {
    server 192.168.11.7:80 max_fails=1 fail_timeout=10s  weight=1;
}

server {
    #监听端口
    listen 80;

    #域名配置：
    server_name _;
    index index.htm index.html index.jsp;

    #禁止直接使用IP地址访问
    if ($host ~* "\d+\.\d+\.\d+\.\d+"){
        return 444;
    }

    #定义访问日志的保存路径
    access_log /data/nginx/logs/proxy_access.log main;

    #设置字符集
    charset utf-8;

    #关闭目录浏览功能
    autoindex off;

    #增加头部信息
    #add_header X-Via $server_addr;

    #增加查看缓存状态：
    add_header X-Cache $upstream_cache_status;

    location / {
        #下面这项配置不要忘记，否则用https 代理后端tomcat 会出现静态文件（样式）显示问题
        #proxy_set_header X-Forwarded-Proto  $scheme;
        proxy_redirect off;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        #proxy_set_header X-Forwarded-For $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_pass http://tomcat-game;

        #单个IP同一时间内的请求限制；zone=perip:对应上面配置的zone;burst=5:允许超过频率限制的请求数不多于5个;
        #nodelay 不等待客户端响应(不进入响应队列)，直接返回错误状态
        limit_req zone=perip burst=5 nodelay;
    }

    location ~ /purge(/.*){
        #auth_basic "purge";
        #auth_basic_user_file /usr/local/nginx/.htpasswd;
        allow 14.161.3.181;
        deny all;
        proxy_cache_purge cache_one  $host$1$is_args$args;
    }

    #缓存设置
    location ~ .*\.(htm|html|css|gif|jpg|jpeg|png|bmp|ico|swf|flv)$ {
        proxy_next_upstream http_500 http_502 http_503 http_504 error timeout invalid_header;
        proxy_cache cache_one;
        proxy_cache_valid 200 304 15m;
        proxy_cache_valid 301 302 10m;
        proxy_cache_valid any 1m;
        proxy_cache_key $host$uri$is_args$args;
        add_header Ten-webcache '$upstream_cache_status from $host';
        if ( !-e $request_filename ) {
            proxy_pass http://tomcat-game;
        }
        #expires 30m;
    }

    location ~ /ngx_status {
        #启用虚拟朱nginx 状态配置
        stub_status on;
        #验证配置
        auth_basic  "status";
        #查看nginx 状态的用户密码文件
        auth_basic_user_file /usr/local/nginx/conf/.htpasswd;
        #关闭访问日志
        access_log   off;
        #允许访问的IP
        allow 127.0.0.1;
        allow 14.161.3.181;
        #拒绝所有
        deny all;
    }
    error_page   500 502 503 504  /50x.html;
    location = /50x.html {
        root   html;
    }
}
eof

#配置默认的Nginx主机模版
cat << 'eof' > /usr/local/nginx/conf.d/default.conf.close
server {
    #监听端口
    listen 80;

    #域名配置：
    server_name _;
    index index.htm index.html index.jsp;
    #禁止随意解析
    #if ($host !~ ".*yunbofun.com") {
    #    return 444;
    #}

    #禁止直接使用IP地址访问
    if ($host ~* "\d+\.\d+\.\d+\.\d+"){
        return 444;
    }

    #定义访问日志的保存路径
    access_log /data/nginx/logs/default_access.log main;

    #设置字符集
    charset utf-8;

    #关闭目录浏览功能
    autoindex off;

    #增加头部信息
    #add_header X-Via $server_addr;

    #增加查看缓存状态：
    add_header X-Cache $upstream_cache_status;
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
eof

#配置SSL 虚拟主机模板
cat << 'eof' > /usr/local/nginx/conf.d/ssl.conf.close
server {
    listen       443 ssl;
    server_name  localhost;

    ssl_certificate      cert.pem;
    ssl_certificate_key  cert.key;

    ssl_session_cache    shared:SSL:1m;
    ssl_session_timeout  5m;

    ssl_ciphers  HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers  on;

    location / {
        root   html;
        index  index.html index.htm;
    }
}
eof

#创建nginx 启动脚本
if [ "${OS_VER}" -ne 6 ] ;then
    echo '[Unit]' > /usr/lib/systemd/system/nginx.service
    echo ' ' >> /usr/lib/systemd/system/nginx.service
    echo 'Description=Nginx' >> /usr/lib/systemd/system/nginx.service
    echo 'After=syslog.target network.target' >> /usr/lib/systemd/system/nginx.service
    echo ' ' >> /usr/lib/systemd/system/nginx.service
    echo '[Service]' >> /usr/lib/systemd/system/nginx.service
    echo 'Type=forking' >> /usr/lib/systemd/system/nginx.service
    echo 'ExecStart=/usr/local/nginx/sbin/nginx' >> /usr/lib/systemd/system/nginx.service
    echo 'ExecReload=/usr/local/nginx/sbin/nginx -s reload' >> /usr/lib/systemd/system/nginx.service
    echo 'ExecStop=/usr/local/nginx/sbin/nginx -s quit' >> /usr/lib/systemd/system/nginx.service
    echo ' ' >> /usr/lib/systemd/system/nginx.service
    echo '[Install]' >> /usr/lib/systemd/system/nginx.service
    echo 'WantedBy=multi-user.target' >> /usr/lib/systemd/system/nginx.service
fi

#启动nginx:
[[ "${OS_VER}" -eq 6 ]] && /usr/local/nginx/sbin/nginx || systemctl start nginx

#开启防火墙的80 端口
if [ "${OS_VER}" -eq 6 ] ;then
    [[ "$(service iptables status)" =~ 'not running' ]] && service iptables start
    iptables -I INPUT -p tcp --dport 80 -j ACCEPT
    service iptables save
else
    [[ -z "$(rpm -qa 'firewalld')" ]] && yum install -y firewalld firewall-config
    [[ -z "$(ps aux|egrep firewalld |egrep -v 'grep')" ]] && systemctl start firewalld
    #封ICMP 协议
    firewall-cmd --permanent --add-rich-rule='rule protocol value=icmp drop'
    #封UDP 协议
    firewall-cmd --permanent --add-rich-rule='rule protocol value=udp drop'
    firewall-cmd --zone=public --permanent --add-rich-rule='rule family="ipv4" port protocol="tcp" port=80 accept'
    firewall-cmd --reload
fi

#设置nginx 环境变量：
echo 'PATH=$PATH:/usr/local/nginx/sbin' >> /etc/profile

#做nginx 日志切割：
[[ -z "$(rpm -qa logrotate)" ]] && yum install -y logrotate
cat << 'eof' > /etc/logrotate.d/nginx
#日志文件，可以是一组 ，用空格隔开
/data/nginx/logs/proxy_access.log /usr/local/nginx/logs/*.log {
    #daily：日志文件将按天轮循。其它可用值为‘weekly’，‘monthly’或者‘yearly’
    daily
    #一次将存储15个归档日志。对于第16个归档，时间最久的归档将被删除
    rotate 15
    #在日志轮循期间，任何错误将被忽略，例如“文件无法找到”之类的错误。
    missingok
    #如果日志文件为空，轮循不会进行。
    notifempty
    #使用日期作为命名格式
    dateext
    #在轮循任务完成后，已轮循的归档将使用gzip进行压缩。
    compress
    #总是与compress选项一起用，delaycompress选项指示logrotate不要将最近的归档压缩，压缩将在下一次轮循周期进行。
    #这在你或任何软件仍然需要读取最新归档时很有用
    delaycompress
    #指定的权限创建全新的日志文件，同时logrotate也会重命名原始日志文件
    create 600 nginx nginx
    #只为整个日志组运行一次的脚本
    sharedscripts
    #在截断转储以后需要执行的命令
    postrotate
        if [ -f /usr/local/nginx/logs/nginx.pid ]; then
            kill -USR1 `cat /usr/local/nginx/logs/nginx.pid`
        fi
    endscript
}
eof

#参考文档:http://www.ha97.com/5194.html
