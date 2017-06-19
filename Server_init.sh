#!/usr/bin/env bash

echo -e "\e[31m
==================================================================================
脚本作用：一键配置服务器的基础环境，暂只支持centos 7
注意事项：服务器名称设置方式
==================================================================================
\e[m"

set -e

#定义系统版本：
OS_VER="$(awk '{print $(NF-1)}' /etc/redhat-release |awk -F '.' '{print $1}')"

#升级系统补丁包：
yum update -y

#关闭系统selinux
sed -i 's#SELINUX=enforcing#SELINUX=disabled#' /etc/selinux/config

#关闭登录DNS 寻址
sed -i 's@#UseDNS yes@UseDNS no@' /etc/ssh/sshd_config

#关闭远程登录询问：
sed -i 's@#   StrictHostKeyChecking ask@StrictHostKeyChecking no@' /etc/ssh/ssh_config

#配置PS1 控制台颜色：
echo "PS1='\[\e[35;1m\][\u@\h \w \t]\\$\[\e[m\]'" >> /etc/profile

#安装必要的工具包：
yum install -y vim telnet wget ntp lrzsz iotop lsof gunzip sysstat net-tools tree

#设置本地时区：
yes |cp /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

#配置同步网络时间：
echo "*/5 * * * *   root   /usr/sbin/ntpdate  time.windows.com" >> /etc/crontab

#配置防火墙策略：
if [ "${OS_VER}" -eq 6 ] ;then
    #防火墙策略
    [[ "$(service iptables status)" =~ 'not running' ]] && service iptables start
    iptables -I INPUT -p udp -j DROP
    iptables -I INPUT -P icpm -j DROP
    service iptables save

    #设置系统打开文件最大数：
    echo "*   soft  nofile  65536" >> /etc/security/limits.conf
    echo "*   hard  nofile  65536" >> /etc/security/limits.conf
    sed -i 's/1024/65535/' /etc/security/limits.d/90-nproc.conf
else
    #防火墙：
    [[ -z "$(rpm -qa 'firewalld')" ]] && yum install -y firewalld firewall-config
    [[ -z "$(ps aux|egrep firewalld |egrep -v 'grep')" ]] && systemctl start firewalld
    #封ICMP 协议
    firewall-cmd --permanent --add-rich-rule='rule protocol value=icmp drop'
    #封UDP 协议
    firewall-cmd --permanent --add-rich-rule='rule protocol value=udp drop'
    firewall-cmd --reload

    #设置系统打开文件最大数：
    echo "*   soft  nofile  65536" >> /etc/security/limits.conf
    echo "*   hard  nofile  65536" >> /etc/security/limits.conf
    sed -i 's/4096/65535/g' /etc/security/limits.d/20-nproc.conf
fi

#设置服务器名称（名称为:地区-类型-编号  HKJH-WEB-20170605)
read -p "Please enter the server name: " NAME
hostnamectl set-hostname $NAME

#重启系统：
reboot