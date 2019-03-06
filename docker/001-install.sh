#!/usr/bin/env bash

set -e
set -u

[ -f "$(rpm -qa docker)" ] && yum install -y docker

systemctl enable docker && systemctl start docker

# 查找容器：
docker search nginx

# 拉去镜像
docker pull nginx

# 查看本地所有镜像
docker images -all

# 查看本地所有运行（包含停止、退出）的容器
docker ps -a

# 查看容器日志：
docker logs $(docker ps -a |awk '/nginx/{print $1}')

# 删除本地运行中的容器（使用 -f 参数)
docker rm $(docker ps -a |awk '/nginx/{print $1}')

# 删除本地容器镜像
docker rmi $(docker images -a |awk '/nginx/{print $3}')

# 运行容器
docker run --name nginx -d -p 80:80 -v /usr/local/nginx/conf/nginx.conf:/etc/nginx/nginx.conf -v /var/log/nginx:/var/log/nginx -v /usr/local/nginx/html:/usr/share/nginx/html --restart always nginx

# 重启容器
docker restart $(docker ps -a |awk '/nginx/{print $1}')

