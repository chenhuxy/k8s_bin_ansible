#!/usr/bin/env bash
#set -ex
echo -e "\033[32m-------------------------------init----------------------------------\033[0m"
###system env
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime
systemctl stop firewalld && systemctl disable firewalld
sed -ri 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
setenforce 0
#sed -ri 's/\*.info;mail.none;authpriv.none;cron.none/\*.info;mail.none;authpriv.none;cron.none;user.none/' /etc/rsyslog.conf
#systemctl restart rsyslog
yum -y install vim-enhanced telnet lrzsz epel-release wget ipvsadm
###docker env
#sudo yum install -y yum-utils device-mapper-persistent-data lvm2
#sudo yum-config-manager --add-repo http://mirrors.aliyun.com/docker-ce/linux/centos/docker-ce.repo
sudo yum makecache fast
sudo yum -y install docker-compose
cd /tmp
sudo yum -y localinstall *.rpm 
cat >/etc/docker/daemon.json <<EOF
{
"registry-mirrors": [
"https://kfwkfulq.mirror.aliyuncs.com",
"https://2lqq34jg.mirror.aliyuncs.com",
"https://pee6w651.mirror.aliyuncs.com",
"https://registry.docker-cn.com",
"http://hub-mirror.c.163.com"
],
"insecure-registries": ["hub.qoros.com"],
"max-concurrent-downloads": 10,
"live-restore": true,
"log-driver": "json-file",
"log-level": "warn",
"log-opts": {
    "max-size": "15m",
    "max-file": "3"
    }
}
EOF
iptables -P INPUT ACCEPT
iptables -P FORWARD ACCEPT
iptables -F && iptables -X
iptables -F -t nat && iptables -X -t nat
iptables -F -t raw && iptables -X -t raw
iptables -F -t mangle && iptables -X -t mangle
#sed -ri 's/--log-driver=journald/--log-driver=json-file/' /etc/sysconfig/docker
systemctl restart docker && systemctl enable docker
###k8s env
modprobe br_netfilter
lsmod | grep br_netfilter
modprobe -- ip_vs
modprobe -- ip_vs_rr
modprobe -- ip_vs_wrr
modprobe -- ip_vs_sh
modprobe -- nf_conntrack_ipv4
lsmod |grep ip_vs
cat <<EOF > /etc/modules-load.d/k8s.conf
br_netfilter
ip_vs
ip_vs_rr
ip_vs_wrr
ip_vs_sh
nf_conntrack_ipv4
EOF
systemctl enable systemd-modules-load
cat <<EOF >  /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
vm.swappiness = 0
EOF
sysctl --system
sed -ri 's$/dev/mapper/centos-swap$#/dev/mapper/centos-swap$' /etc/fstab
swapoff -a
