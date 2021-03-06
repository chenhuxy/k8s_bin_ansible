#!/usr/bin/env bash
#set -ex
etcd01=10.58.133.2
etcd02=10.58.133.3
etcd03=10.58.133.4
ip=`ip a |egrep '(eth[0-9]|ens[0-9]{2,})' |awk '/inet/ {print $2}' |cut -d/ -f1`
name=etcd01

install () {
echo -e "\033[32m-------------------------------install ssl tool----------------------------------\033[0m"
cd /usr/local/bin
[ -f cfssl ] || wget -O cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
[ -f cfssljson ] || wget -O cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
[ -f cfssl-certinfo ] || wget -O cfssl-certinfo https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
chmod +x cfssl cfssljson cfssl-certinfo
mkdir /opt/etcd/{bin,cfg,ssl,data,package} -p
cd /opt/etcd/cfg
echo -e "\033[32m--------------------------------generate ca pem------------------------------------\033[0m"
cat >ca-config.json <<EOF
{
    "signing": {
        "default": {
            "expiry": "87600h"
        },
        "profiles": {
            "server": {
                "expiry": "87600h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            },
            "client": {
                "expiry": "87600h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "client auth"
                ]
            },
            "peer": {
                "expiry": "87600h",
                "usages": [
                    "signing",
                    "key encipherment",
                    "server auth",
                    "client auth"
                ]
            }
        }
    }
}
EOF
cat >ca-csr.json <<EOF
{
    "CN": "etcd",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
	"ca": {
       "expiry": "87600h"
    }
}
EOF
cfssl gencert -initca ca-csr.json | cfssljson -bare ca
echo -e "\033[32m--------------------------------generate client pem---------------------------------\033[0m"
cat >client.json <<EOF
{
    "CN": "client",
    "key": {
        "algo": "ecdsa",
        "size": 256
    }
}
EOF
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=client client.json  | cfssljson -bare client -
echo -e "\033[32m--------------------------------generate server && peer pem-------------------------\033[0m"
cat >etcd.json <<EOF
{
    "CN": "etcd",
    "hosts": [
        "127.0.0.1",
        "$etcd01",
        "$etcd02",
        "$etcd03"
    ],
    "key": {
        "algo": "ecdsa",
        "size": 256
    },
    "names": [
        {
            "C": "CN",
            "L": "SH",
            "ST": "SH"
        }
    ]
}
EOF
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=server etcd.json | cfssljson -bare server
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=peer etcd.json | cfssljson -bare peer
cp -f *.pem /opt/etcd/ssl
echo -e "\033[32m--------------------------------install etcd---------------------------------------\033[0m"
###################### online install ########################
#cd /opt/etcd/package
#wget https://github.com/etcd-io/etcd/releases/download/v3.3.17/etcd-v3.3.17-linux-amd64.tar.gz
#tar zxvf etcd-v3.3.17-linux-amd64.tar.gz
#mv etcd-v3.3.17-linux-amd64/etcd* /opt/etcd/bin/
###################### offline install ########################
cd /tmp
tar zxvf etcd-v3.3.17-linux-amd64.tar.gz
mv etcd-v3.3.17-linux-amd64/etcd* /opt/etcd/bin/
cat >/usr/lib/systemd/system/etcd.service <<EOF
[Unit]
Description=Etcd Server
After=network.target
After=network-online.target
Wants=network-online.target
Documentation=https://github.com/coreos

[Service]
Type=notify
WorkingDirectory=/opt/etcd/data
ExecStart=/opt/etcd/bin/etcd \
--data-dir=/opt/etcd/data \
--name=$name \
--cert-file=/opt/etcd/ssl/server.pem \
--key-file=/opt/etcd/ssl/server-key.pem \
--trusted-ca-file=/opt/etcd/ssl/ca.pem \
--peer-cert-file=/opt/etcd/ssl/peer.pem \
--peer-key-file=/opt/etcd/ssl/peer-key.pem \
--peer-trusted-ca-file=/opt/etcd/ssl/ca.pem \
--listen-peer-urls=https://$ip:2380 \
--initial-advertise-peer-urls=https://$ip:2380 \
--listen-client-urls=https://$ip:2379,http://127.0.0.1:2379 \
--advertise-client-urls=https://$ip:2379 \
--initial-cluster-token=etcd-cluster-0 \
--initial-cluster=etcd01=https://$etcd01:2380,etcd02=https://$etcd02:2380,etcd03=https://$etcd03:2380 \
--initial-cluster-state=new \
--heartbeat-interval=250 \
--election-timeout=2000
Restart=on-failure
RestartSec=5
LimitNOFILE=65536

[Install]
WantedBy=multi-user.target
EOF
scp -r $etcd01:/opt/etcd/ssl /opt/etcd/
systemctl daemon-reload
systemctl enable etcd
systemctl start etcd
systemctl status etcd
}
uninstall () {
[ -f /usr/lib/systemd/system/etcd.service ] && systemctl disable etcd
[ -f /usr/lib/systemd/system/etcd.service ] && systemctl stop etcd
rm -f /usr/lib/systemd/system/etcd.service
rm -rf /opt/etcd
}
case "$1" in
    install)
      install
      ;;
    uninstall)
      uninstall
      ;;
    reinstall)
      uninstall
      install
      ;;
     *)
      echo "Usage: $0 {install|uninstall}"
esac
