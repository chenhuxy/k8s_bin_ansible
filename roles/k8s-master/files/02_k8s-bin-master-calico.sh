#!/usr/bin/env bash
#set -ex
etcd01=10.58.133.2
etcd02=10.58.133.3
etcd03=10.58.133.4
etcd_sslDir=/opt/etcd/ssl
apiserver01=10.58.133.2
apiserver02=10.58.133.3
apiserver03=10.58.133.4
vip=10.58.133.11
haproxy=$vip:6443
KUBE_APISERVER="https://$haproxy"
cfgDir=/opt/kubernetes/cfg
sslDir=/opt/kubernetes/ssl
binDir=/opt/kubernetes/bin
serviceDir=/usr/lib/systemd/system
ip=`ip a |egrep '(eth[0-9]|ens[0-9]{2,})' |awk '/inet/ {print $2}' |cut -d/ -f1`
KUBERNETES_CLUSTER_CIDR=10.0.0.0/24  #集群serviceIP网段，不建议修改
KUBERNETES_IP=10.0.0.1               #集群kubernetesServiceIP，不建议修改
KUBERNETES_DNS_IP=10.0.0.2           #集群dnsServcieIP，不建议修改

init(){
mkdir -p /opt/kubernetes/{bin,cfg,ssl,package}
}

ssl-tool(){
[ -d $etcd_sslDir ] || mkdir -p $etcd_sslDir
echo -e "\033[32;1m-------------------------------------------------------------------------install ssl tool-------------------------------------------------------------------\033[0m"
cd /usr/local/bin
[ -f cfssl ] || wget -O cfssl https://pkg.cfssl.org/R1.2/cfssl_linux-amd64
[ -f cfssljson ] || wget -O cfssljson https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64
[ -f cfssl-certinfo ] || wget -O cfssl-certinfo https://pkg.cfssl.org/R1.2/cfssl-certinfo_linux-amd64
chmod +x cfssl cfssljson cfssl-certinfo
}

ca-pem(){
echo -e "\033[32;1m-------------------------------------------------------------------------generate ca pem--------------------------------------------------------------------\033[0m"
cd $cfgDir
cat > ca-config.json << EOF
{
  "signing": {
    "default": {
      "expiry": "87600h"
    },
    "profiles": {
      "kubernetes": {
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
cat >  ca-csr.json << EOF
{
    "CN": "kubernetes",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "Beijing",
            "ST": "Beijing",
            "O": "k8s",
            "OU": "System"
        }
    ],
    "ca": {
       "expiry": "87600h"
    }
}
EOF
#  "ca": {"expiry": "87600h"} 不加默认5年

cfssl gencert -initca ca-csr.json | cfssljson -bare ca
}

kube-apiserver-pem(){
echo -e "\033[32;1m---------------------------------------------------------------------------generate kube-apiserver pem--------------------------------------------------------------\033[0m"
cd $cfgDir
cat >  server-csr.json << EOF
{
    "CN": "kubernetes",
    "hosts": [
      "$KUBERNETES_IP",
      "127.0.0.1",
      "$apiserver01",
      "$apiserver02",
      "$apiserver03",
      "$vip",
      "kubernetes",
      "kubernetes.default",
      "kubernetes.default.svc",
      "kubernetes.default.svc.cluster",
      "kubernetes.default.svc.cluster.local"
    ],
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "names": [
        {
            "C": "CN",
            "L": "BeiJing",
            "ST": "BeiJing",
            "O": "k8s",
            "OU": "System"
        }
    ]
}
EOF
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes server-csr.json | cfssljson -bare server
}

kubectl-admin-pem(){
echo -e "\033[32;1m--------------------------------------------------------------------------generate kubectl admin pem--------------------------------------------------------------------\033[0m"
cd $cfgDir
cat > admin-csr.json <<EOF
{
  "CN": "admin",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "ST": "BeiJing",
      "L": "BeiJing",
      "O": "system:masters",
      "OU": "System"
    }
  ]
}
EOF
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare admin
}

kube-controller-manager-pem(){
echo -e "\033[32;1m-------------------------------------------------------------------------generate kube-controller-manager pem---------------------------------------------------------------\033[0m"
cd $cfgDir
cat > kube-controller-manager-csr.json <<EOF
{
    "CN": "system:kube-controller-manager",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "hosts": [
      "127.0.0.1",
      "$apiserver01",
      "$apiserver02",
      "$apiserver03",
    ],
    "names": [
      {
        "C": "CN",
        "ST": "BeiJing",
        "L": "BeiJing",
        "O": "system:kube-controller-manager",
        "OU": "System"
      }
    ]
}
EOF
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare kube-controller-manager
}

kube-scheduler-pem(){
echo -e "\033[32;1m-------------------------------------------------------------------------generate kube-scheduler pem---------------------------------------------------------------\033[0m"
cd $cfgDir
cat > kube-controller-manager-csr.json <<EOF
{
    "CN": "system:kube-scheduler",
    "key": {
        "algo": "rsa",
        "size": 2048
    },
    "hosts": [
      "127.0.0.1",
      "$apiserver01",
      "$apiserver02",
      "$apiserver03",
    ],
    "names": [
      {
        "C": "CN",
        "ST": "BeiJing",
        "L": "BeiJing",
        "O": "system:kube-scheduler",
        "OU": "System"
      }
    ] 
}
EOF
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes admin-csr.json | cfssljson -bare kube-scheduler
}

kube-proxy-pem(){
echo -e "\033[32;1m------------------------------------------------------------------------------generate kube-proxy pem---------------------------------------------------------------\033[0m"
cd $cfgDir
cat >  kube-proxy-csr.json << EOF
{
  "CN": "system:kube-proxy",
  "hosts": [],
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "C": "CN",
      "L": "BeiJing",
      "ST": "BeiJing",
      "O": "k8s",
      "OU": "System"
    }
  ]
}
EOF
cfssl gencert -ca=ca.pem -ca-key=ca-key.pem -config=ca-config.json -profile=kubernetes kube-proxy-csr.json | cfssljson -bare kube-proxy
mv -f *.pem $sslDir/
}

package-master(){
echo -e "\033[32;1m-----------------------------------------------------------------------------download kubernetes package----------------------------------------------------------------\033[0m"
###################### online install ########################
#cd /opt/kubernetes/package
#wget https://dl.k8s.io/v1.11.10/kubernetes-server-linux-amd64.tar.gz
#tar zxvf kubernetes-server-linux-amd64.tar.gz
#cd kubernetes/server/bin
#cp kube-apiserver kube-scheduler kube-controller-manager kubectl $binDir
###################### offline install ########################
cd /tmp
tar zxvf kubernetes-server-linux-amd64.tar.gz
cd kubernetes/server/bin
/usr/bin/cp -f kube-apiserver kube-scheduler kube-controller-manager kubectl kube-proxy kubelet $binDir/
cat >  $cfgDir/token.csv <<EOF
674c457d4dcf2eefe4920d7dbb6b0ddc,kubelet-bootstrap,10001,"system:kubelet-bootstrap"
EOF
scp $apiserver01:$cfgDir/token.csv $cfgDir/
scp $apiserver01:$sslDir/ca*.pem $sslDir/
}

package-node(){
echo -e "\033[32;1m-----------------------------------------------------------------------------download kubernetes package----------------------------------------------------------------\033[0m"
###################### online install ########################
#cd /opt/kubernetes/package
#wget https://dl.k8s.io/v1.11.10/kubernetes-server-linux-amd64.tar.gz
#tar zxvf kubernetes-server-linux-amd64.tar.gz
#cd kubernetes/server/bin
#cp kube-apiserver kube-scheduler kube-controller-manager kubectl $binDir
###################### offline install ########################
cd /tmp
tar zxvf kubernetes-server-linux-amd64.tar.gz
cd kubernetes/server/bin
/usr/bin/cp -f kube-proxy kubelet $binDir/
}

kube-apiserver(){
echo -e "\033[32;1m-------------------------------------------------------------------------------install kube-apiserver------------------------------------------------------------------\033[0m"
scp $apiserver01:$sslDir/server*.pem $sslDir/
cd $cfgDir
cat >  kube-apiserver  << EOF 
KUBE_APISERVER_OPTS="--logtostderr=true \
--v=4 \
--etcd-servers=https://$etcd01:2379,https://$etcd02:2379,https://$etcd03:2379 \
--bind-address=$ip \
--secure-port=6443 \
--port=0 \
--advertise-address=$ip \
--allow-privileged=true \
--service-cluster-ip-range=$KUBERNETES_CLUSTER_CIDR \
--enable-admission-plugins=NamespaceLifecycle,LimitRanger,ServiceAccount,ResourceQuota,NodeRestriction \
--authorization-mode=RBAC,Node \
--enable-bootstrap-token-auth \
--token-auth-file=$cfgDir/token.csv \
--service-node-port-range=30000-50000 \
--tls-cert-file=$sslDir/server.pem  \
--tls-private-key-file=$sslDir/server-key.pem \
--client-ca-file=$sslDir/ca.pem \
--service-account-key-file=$sslDir/ca-key.pem \
--etcd-cafile=$etcd_sslDir/ca.pem \
--etcd-certfile=$etcd_sslDir/server.pem \
--etcd-keyfile=$etcd_sslDir/server-key.pem"
EOF
cd $serviceDir
cat >  kube-apiserver.service << EOF 
[Unit]
Description=Kubernetes API Server
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-$cfgDir/kube-apiserver
ExecStart=$binDir/kube-apiserver \$KUBE_APISERVER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable kube-apiserver
systemctl start kube-apiserver
}

kubectl-kubeconfig(){
echo -e "\033[32;1m---------------------------------------------------------------------------generate kubectl kubeconfig---------------------------------------------------------------------\033[0m"
scp $apiserver01:$sslDir/admin*.pem $sslDir/
cd $sslDir
# 设置集群参数
$binDir/kubectl config set-cluster kubernetes \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=$cfgDir/kubectl.kubeconfig
#设置客户端认证参数
$binDir/kubectl config set-credentials admin \
  --client-certificate=admin.pem \
  --client-key=admin-key.pem \
  --embed-certs=true \
  --kubeconfig=$cfgDir/kubectl.kubeconfig
# 设置上下文参数
$binDir/kubectl config set-context kubernetes \
  --cluster=kubernetes \
  --user=admin \
  --kubeconfig=$cfgDir/kubectl.kubeconfig
# 设置默认上下文
$binDir/kubectl config use-context kubernetes --kubeconfig=$cfgDir/kubectl.kubeconfig
mkdir -p ~/.kube
scp $apiserver01:$cfgDir/kubectl.kubeconfig ~/.kube/config
}

kube-scheduler-kubeconfig(){
echo -e "\033[32;1m-------------------------------------------------------------------------generate kube-scheduler kubeconfig---------------------------------------------------------------------\033[0m"
scp $apiserver01:$sslDir/kube-scheduler*.pem $sslDir/
cd $sslDir
$binDir/kubectl config set-cluster kubernetes \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=$cfgDir/kube-scheduler.kubeconfig
$binDir/kubectl config set-credentials system:kube-scheduler \
  --client-certificate=kube-scheduler.pem \
  --client-key=kube-scheduler-key.pem \
  --embed-certs=true \
  --kubeconfig=$cfgDir/kube-scheduler.kubeconfig
$binDir/kubectl config set-context system:kube-scheduler \
  --cluster=kubernetes \
  --user=system:kube-scheduler \
  --kubeconfig=$cfgDir/kube-scheduler.kubeconfig
$binDir/kubectl config use-context system:kube-scheduler --kubeconfig=$cfgDir/kube-scheduler.kubeconfig
scp $apiserver01:$cfgDir/kube-scheduler.kubeconfig $cfgDir/
}

kube-controller-manager-kubeconfig(){
echo -e "\033[32;1m-------------------------------------------------------------------generate kube-controller-manager kubeconfig---------------------------------------------------------------------\033[0m"
scp $apiserver01:$sslDir/kube-controller-manager*.pem $sslDir/
cd $sslDir
$binDir/kubectl config set-cluster kubernetes \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=$cfgDir/kube-controller-manager.kubeconfig
$binDir/kubectl config set-credentials system:kube-controller-manager \
  --client-certificate=kube-controller-manager.pem \
  --client-key=kube-controller-manager-key.pem \
  --embed-certs=true \
  --kubeconfig=$cfgDir/kube-controller-manager.kubeconfig
$binDir/kubectl config set-context system:kube-controller-manager \
  --cluster=kubernetes \
  --user=system:kube-controller-manager \
  --kubeconfig=$cfgDir/kube-controller-manager.kubeconfig
$binDir/kubectl config use-context system:kube-controller-manager --kubeconfig=$cfgDir/kube-controller-manager.kubeconfig
scp $apiserver01:$cfgDir/kube-controller-manager.kubeconfig $cfgDir/
}

kube-scheduler(){
echo -e "\033[32;1m------------------------------------------------------------------------install kube-scheduler---------------------------------------------------------------------------------------\033[0m"
cd $cfgDir
cat > kube-scheduler << EOF 
KUBE_SCHEDULER_OPTS="--logtostderr=true \
--v=4 \
--kubeconfig=$cfgDir/kube-scheduler.kubeconfig \
--leader-elect \
--tls-cert-file=$sslDir/kube-scheduler.pem \
--tls-private-key-file=$sslDir/kube-scheduler-key.pem \
--authentication-kubeconfig=$cfgDir/kube-scheduler.kubeconfig"
EOF
cd $serviceDir
cat >  kube-scheduler.service  << EOF 
[Unit]
Description=Kubernetes Scheduler
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-$cfgDir/kube-scheduler
ExecStart=$binDir/kube-scheduler \$KUBE_SCHEDULER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable kube-scheduler 
systemctl start kube-scheduler
}

autosign(){
echo -e "\033[32;1m--------------------------------------------------------configure kube-contorller-manager auto sign csr for kubelet-------------------------------------------------------------------------\033[0m"
cd $cfgDir
cat > autosign.yaml <<EOF
kind: ClusterRole
apiVersion: rbac.authorization.k8s.io/v1
metadata:
  name: system:certificates.k8s.io:certificatesigningrequests:selfnodeserver
rules:
- apiGroups: ["certificates.k8s.io"]
  resources: ["certificatesigningrequests/selfnodeserver"]
  verbs: ["create"]
EOF
sleep 10
# 允许 system:kubelet-bootstrap 组用户创建 CSR 请求
$binDir/kubectl get clusterrolebinding |grep kubelet-bootstrap || $binDir/kubectl create clusterrolebinding kubelet-bootstrap \
  --clusterrole=system:node-bootstrapper --user=kubelet-bootstrap
$binDir/kubectl get clusterrolebinding |grep kubelet-nodes || $binDir/kubectl create clusterrolebinding kubelet-nodes \
  --clusterrole=system:node --group=system:nodes
# 自动批准 system:kubelet-bootstrap 组用户 TLS bootstrapping 首次申请证书的 CSR 请求
$binDir/kubectl get clusterrolebinding |grep node-client-auto-approve-csr || $binDir/kubectl create clusterrolebinding node-client-auto-approve-csr \
  --clusterrole=system:certificates.k8s.io:certificatesigningrequests:nodeclient --group=system:kubelet-bootstrap
# 自动批准 system:nodes 组用户更新 kubelet 自身与 apiserver 通讯证书的 CSR 请求
$binDir/kubectl get clusterrolebinding |grep node-client-auto-renew-crt || $binDir/kubectl create clusterrolebinding node-client-auto-renew-crt \
  --clusterrole=system:certificates.k8s.io:certificatesigningrequests:selfnodeclient --group=system:nodes
# 自动批准 system:nodes 组用户更新 kubelet 10250 api 端口证书的 CSR 请求
$binDir/kubectl get clusterrole |grep system:certificates.k8s.io:certificatesigningrequests:selfnodeserver || $binDir/kubectl apply \
  -f $cfgDir/autosign.yaml
$binDir/kubectl get clusterrolebinding |grep node-server-auto-renew-crt || $binDir/kubectl create clusterrolebinding node-server-auto-renew-crt \
  --clusterrole=system:certificates.k8s.io:certificatesigningrequests:selfnodeserver --group=system:nodes
}

kube-controller-manager(){
echo -e "\033[32;1m-----------------------------------------------------------------install kube-controller-manager-----------------------------------------------------------------------------------------------\033[0m"
cd $cfgDir
cat >  kube-controller-manager << EOF 
KUBE_CONTROLLER_MANAGER_OPTS="--logtostderr=true \
--v=4 \
--kubeconfig=$cfgDir/kube-controller-manager.kubeconfig \
--leader-elect=true \
--service-cluster-ip-range=$KUBERNETES_CLUSTER_CIDR \
--cluster-name=kubernetes \
--cluster-signing-cert-file=$sslDir/ca.pem \
--cluster-signing-key-file=$sslDir/ca-key.pem  \
--root-ca-file=$sslDir/ca.pem \
--service-account-private-key-file=$sslDir/ca-key.pem \
--experimental-cluster-signing-duration=87600h0m0s \
--feature-gates=RotateKubeletServerCertificate=true,RotateKubeletClientCertificate=true \
--tls-cert-file=$sslDir/kube-controller-manager.pem \
--tls-private-key-file=$sslDir/kube-controller-manager-key.pem \
--authentication-kubeconfig=$cfgDir/kube-controller-manager.kubeconfig"
EOF
cd $serviceDir
cat >  kube-controller-manager.service << EOF 
[Unit]
Description=Kubernetes Controller Manager
Documentation=https://github.com/kubernetes/kubernetes

[Service]
EnvironmentFile=-$cfgDir/kube-controller-manager
ExecStart=$binDir/kube-controller-manager \$KUBE_CONTROLLER_MANAGER_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable kube-controller-manager
systemctl start kube-controller-manager
sleep 10
$binDir/kubectl get cs
}

bootstrap-kubeconfig(){
echo -e "\033[32;1m--------------------------------------------------------------generate bootsrap kubeconfig-----------------------------------------------------------------------------------------------------\033[0m"
BOOTSTRAP_TOKEN=`cat $cfgDir/token.csv |cut -d, -f1`
cd $sslDir
$binDir/kubectl config set-cluster kubernetes \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=$cfgDir/bootstrap.kubeconfig
$binDir/kubectl config set-credentials kubelet-bootstrap \
  --token=${BOOTSTRAP_TOKEN} \
  --kubeconfig=$cfgDir/bootstrap.kubeconfig
$binDir/kubectl config set-context default \
  --cluster=kubernetes \
  --user=kubelet-bootstrap \
  --kubeconfig=$cfgDir/bootstrap.kubeconfig
$binDir/kubectl config use-context default --kubeconfig=$cfgDir/bootstrap.kubeconfig
}

kube-proxy-kubeconfig(){
echo -e "\033[32;1m-------------------------------------------------------------generate kube-proxy kubeconfig-----------------------------------------------------------------------------------------------------\033[0m"
cd $sslDir
$binDir/kubectl config set-cluster kubernetes \
  --certificate-authority=ca.pem \
  --embed-certs=true \
  --server=${KUBE_APISERVER} \
  --kubeconfig=$cfgDir/kube-proxy.kubeconfig
$binDir/kubectl config set-credentials kube-proxy \
  --client-certificate=kube-proxy.pem \
  --client-key=kube-proxy-key.pem \
  --embed-certs=true \
  --kubeconfig=$cfgDir/kube-proxy.kubeconfig
$binDir/kubectl config set-context default \
  --cluster=kubernetes \
  --user=kube-proxy \
  --kubeconfig=$cfgDir/kube-proxy.kubeconfig
$binDir/kubectl config use-context default --kubeconfig=$cfgDir/kube-proxy.kubeconfig
}

### ---------------------------------------------------master 分割线 --------------------------------------------------------------------------------------- ###

kubelet-master(){
echo -e "\033[32;1m---------------------------------------------------------------------install kubelet-------------------------------------------------------------------------------------------------------------\033[0m"
scp $apiserver01:$cfgDir/bootstrap.kubeconfig $cfgDir/
###########online##############
#cd /opt/kubernetes/package/kubernetes/server/bin
#cp -f kubelet kube-proxy $binDir
###########offline##############
cd /tmp
docker load -i pause-amd64.tar
cd $cfgDir
cat >  kubelet.config  << EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
port: 10250
readOnlyPort: 10255
cgroupDriver: cgroupfs
clusterDNS: ["$KUBERNETES_DNS_IP"]
clusterDomain: cluster.local.
failSwapOn: false
feature-gates:
  RotateKubeletClientCertificate: true
  RotateKubeletServerCertificate: true
rotate-certificates: true
rotate-server-certificates: true
authentication:
  anonymous:
    enabled: true 
  webhook:
    enabled: false
EOF
# docker info 查看cgroup-driver信息，默认cgroupfs
cat >  kubelet << EOF
KUBELET_OPTS="--logtostderr=true \
--v=4 \
--kubeconfig=$cfgDir/kubelet.kubeconfig \
--bootstrap-kubeconfig=$cfgDir/bootstrap.kubeconfig \
--config=$cfgDir/kubelet.config \
--cert-dir=$sslDir \
--node-labels=node-role.kubernetes.io/master= \
--register-with-taints=node-role.kubernetes.io/master=:NoSchedule \
--pod-infra-container-image=registry.cn-hangzhou.aliyuncs.com/google-containers/pause-amd64:3.0 \
--network-plugin=cni"
EOF
cd $serviceDir
cat > kubelet.service   << EOF
[Unit]
Description=Kubernetes Kubelet
After=docker.service
Requires=docker.service

[Service]
EnvironmentFile=$cfgDir/kubelet
ExecStart=$binDir/kubelet \$KUBELET_OPTS
Restart=on-failure
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet
}

kubelet-node(){
echo -e "\033[32;1m---------------------------------------------------------------------install kubelet-------------------------------------------------------------------------------------------------------------\033[0m"
scp $apiserver01:$cfgDir/bootstrap.kubeconfig $cfgDir/
###########online##############
#cd /opt/kubernetes/package/kubernetes/server/bin
#cp -f kubelet kube-proxy $binDir
###########offline##############
cd /tmp
docker load -i pause-amd64.tar
cd $cfgDir
cat >  kubelet.config  << EOF
kind: KubeletConfiguration
apiVersion: kubelet.config.k8s.io/v1beta1
port: 10250
readOnlyPort: 10255
cgroupDriver: cgroupfs
clusterDNS: ["$KUBERNETES_DNS_IP"]
clusterDomain: cluster.local.
failSwapOn: false
feature-gates:
  RotateKubeletClientCertificate: true
  RotateKubeletServerCertificate: true
rotate-certificates: true
rotate-server-certificates: true
authentication:
  anonymous:
    enabled: true 
  webhook:
    enabled: false
EOF
# docker info 查看cgroup-driver信息，默认cgroupfs
cat >  kubelet << EOF
KUBELET_OPTS="--logtostderr=true \
--v=4 \
--kubeconfig=$cfgDir/kubelet.kubeconfig \
--bootstrap-kubeconfig=$cfgDir/bootstrap.kubeconfig \
--config=$cfgDir/kubelet.config \
--cert-dir=$sslDir \
--pod-infra-container-image=registry.cn-hangzhou.aliyuncs.com/google-containers/pause-amd64:3.0 \
--network-plugin=cni"
EOF
cd $serviceDir
cat > kubelet.service   << EOF
[Unit]
Description=Kubernetes Kubelet
After=docker.service
Requires=docker.service

[Service]
EnvironmentFile=$cfgDir/kubelet
ExecStart=$binDir/kubelet \$KUBELET_OPTS
Restart=on-failure
KillMode=process

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable kubelet
systemctl start kubelet
}

kube-proxy(){
echo -e "\033[32;1m------------------------------------------------------------------------------install kube-proxy----------------------------------------------------------------------------------------------------\033[0m"
scp $apiserver01:$cfgDir/kube-proxy.kubeconfig $cfgDir/
cd $cfgDir
cat >  kube-proxy  << EOF
KUBE_PROXY_OPTS="--logtostderr=true \
--v=4 \
--cluster-cidr=$KUBERNETES_CLUSTER_CIDR \
--kubeconfig=$cfgDir/kube-proxy.kubeconfig \
--proxy-mode=ipvs \
--metrics-bind-address=0.0.0.0"
EOF
cd $serviceDir
cat >  kube-proxy.service << EOF 
[Unit]
Description=Kubernetes Proxy
After=network.target

[Service]
EnvironmentFile=-$cfgDir/kube-proxy
ExecStart=$binDir/kube-proxy \$KUBE_PROXY_OPTS
Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable kube-proxy
systemctl start kube-proxy
}

calico-image(){
echo -e "\033[32;1m-------------------------------------------------------------------------------pull calico images---------------------------------------------------------------------------------------------------------\033[0m"
#docker pull calico/kube-controllers:v3.1.7
#docker tag calico/kube-controllers:v3.1.7 quay.io/calico/kube-controllers:v3.1.7
#docker pull calico/node:v3.1.7
#docker tag calico/node:v3.1.7 quay.io/calico/node:v3.1.7
#docker pull calico/cni:v3.1.7
#docker tag calico/cni:v3.1.7 quay.io/calico/cni:v3.1.7
cd /tmp
docker load -i calico_kube-controllers.tar
docker load -i calico_node.tar
docker load -i calico_cni.tar
}

calico-master(){
echo -e "\033[32;1m-------------------------------------------------------------------------------install calico cni---------------------------------------------------------------------------------------------------------\033[0m"
[ -d $etcd_sslDir ] || mkdir -p $etcd_sslDir
scp $etcd01:$etcd_sslDir/* $etcd_sslDir/
#cniDir=/opt/kubernetes/cni
cniDir=/tmp
[ -d $cniDir ] || mkdir -p $cniDir
#wget https://docs.projectcalico.org/v3.1/getting-started/kubernetes/installation/rbac.yaml -O $cniDir/rbac.yaml
$binDir/kubectl apply -f $cniDir/rbac.yaml
#wget https://docs.projectcalico.org/v3.1/getting-started/kubernetes/installation/hosted/calico.yaml -O $cniDir/calico.yaml
ETCD_ENDPOINTS="https://$etcd01:2379,https://$etcd02:2379,https://$etcd03:2379"
sed -i "s#.*etcd_endpoints:.*#  etcd_endpoints: \"${ETCD_ENDPOINTS}\"#g" $cniDir/calico.yaml
sed -i "s#__ETCD_ENDPOINTS__#${ETCD_ENDPOINTS}#g" $cniDir/calico.yaml
ETCD_CERT=`cat $etcd_sslDir/server.pem | base64 | tr -d '\n'`
ETCD_KEY=`cat $etcd_sslDir/server-key.pem | base64 | tr -d '\n'`
ETCD_CA=`cat $etcd_sslDir/ca.pem | base64 | tr -d '\n'`
sed -i "s#.*etcd-cert:.*#  etcd-cert: ${ETCD_CERT}#g" $cniDir/calico.yaml
sed -i "s#.*etcd-key:.*#  etcd-key: ${ETCD_KEY}#g" $cniDir/calico.yaml
sed -i "s#.*etcd-ca:.*#  etcd-ca: ${ETCD_CA}#g" $cniDir/calico.yaml

sed -i 's#.*etcd_ca:.*#  etcd_ca: "/calico-secrets/etcd-ca"#g' $cniDir/calico.yaml
sed -i 's#.*etcd_cert:.*#  etcd_cert: "/calico-secrets/etcd-cert"#g' $cniDir/calico.yaml
sed -i 's#.*etcd_key:.*#  etcd_key: "/calico-secrets/etcd-key"#g' $cniDir/calico.yaml

sed -i "s#__ETCD_KEY_FILE__#$etcd_sslDir/server-key.pem#g" $cniDir/calico.yaml
sed -i "s#__ETCD_CERT_FILE__#$etcd_sslDir/server.pem#g" $cniDir/calico.yaml
sed -i "s#__ETCD_CA_CERT_FILE__#$etcd_sslDir/ca.pem#g" $cniDir/calico.yaml
sed -i "s#__KUBECONFIG_FILEPATH__#/etc/cni/net.d/calico-kubeconfig#g" $cniDir/calico.yaml

#sed -i '/CALICO_IPV4POOL_IPIP/{n;s/Always/off/g}' $cniDir/calico.yaml
#sed -i '/CALICO_IPV4POOL_CIDR/{n;s/192.168.0.0/10.10.0.0/g}' $cniDir/calico.yaml

$binDir/kubectl apply -f $cniDir/calico.yaml
sleep 30
#sed -ri "s#https://\[10.0.0.1\]:443#$KUBE_APISERVER#" /etc/cni/net.d/calico-kubeconfig
sed -ri "s#https://\[$KUBERNETES_IP\]:443#$KUBE_APISERVER#" /etc/cni/net.d/calico-kubeconfig
systemctl restart kubelet

}

calico-node(){
echo -e "\033[32;1m-------------------------------------------------------------------------------install calico cni---------------------------------------------------------------------------------------------------------\033[0m"
[ -d $etcd_sslDir ] || mkdir -p $etcd_sslDir
scp $etcd01:$etcd_sslDir/* $etcd_sslDir/
sleep 30
#sed -ri "s#https://\[10.0.0.1\]:443#$KUBE_APISERVER#" /etc/cni/net.d/calico-kubeconfig
sed -ri "s#https://\[$KUBERNETES_IP\]:443#$KUBE_APISERVER#" /etc/cni/net.d/calico-kubeconfig
systemctl restart kubelet

}

uninstall(){
    [ -f /usr/lib/systemd/system/kubelet.service ] && systemctl disable kubelet
    [ -f /usr/lib/systemd/system/kubelet.service ] && systemctl stop kubelet
    rm -f /usr/lib/systemd/system/kubelet.service
    [ -f /usr/lib/systemd/system/kube-proxy.service ] && systemctl disable kube-proxy
    [ -f /usr/lib/systemd/system/kube-proxy.service ] && systemctl stop kube-proxy
    rm -f /usr/lib/systemd/system/kube-proxy.service
    rm -f $cfgDir/*.kubeconfig
    ### ------------------------------------------------------------------------------------------------------------------------------------------------- ###
    [ -f /usr/lib/systemd/system/kube-apiserver.service ] && systemctl disable kube-apiserver
    [ -f /usr/lib/systemd/system/kube-apiserver.service ] && systemctl stop kube-apiserver
    rm -f /usr/lib/systemd/system/kube-apiserver.service
    [ -f /usr/lib/systemd/system/kube-scheduler.service ] && systemctl disable kube-scheduler
    [ -f /usr/lib/systemd/system/kube-scheduler.service ] && systemctl stop kube-scheduler
    rm -f /usr/lib/systemd/system/kube-scheduler.service
    [ -f /usr/lib/systemd/system/kube-controller-manager.service ] && systemctl disable kube-controller-manager
    [ -f /usr/lib/systemd/system/kube-controller-manager.service ] && systemctl stop kube-controller-manager
    rm -f /usr/lib/systemd/system/kube-controller-manager.service
    rm -rf /opt/kubernetes
    rm -rf ~/.kube
    rm -rf /etc/cni/net.d
    for i in `docker ps -a |awk '/k8s/ {print $1}'`;do docker rm -f $i;done
}
case "$1" in
    install)
	init
     	ssl-tool
 	ca-pem
	kube-apiserver-pem
	kubectl-admin-pem
	kube-controller-manager-pem
	kube-scheduler-pem
	kube-proxy-pem
	package-master
	kube-apiserver
	kubectl-kubeconfig
	kube-scheduler-kubeconfig
	kube-controller-manager-kubeconfig
	kube-scheduler
	autosign
	kube-controller-manager
	bootstrap-kubeconfig
	kube-proxy-kubeconfig
	kubelet-master
	kube-proxy
	calico-image
      	calico-master
      	;;
    uninstall)
      	uninstall
      	;;
    reinstall)
      	uninstall
	init
     	ssl-tool
 	ca-pem
	kube-apiserver-pem
	kubectl-admin-pem
	kube-controller-manager-pem
	kube-scheduler-pem
	kube-proxy-pem
	package-master
	kube-apiserver
	kubectl-kubeconfig
	kube-scheduler-kubeconfig
	kube-controller-manager-kubeconfig
	kube-scheduler
	autosign
	kube-controller-manager
	bootstrap-kubeconfig
	kube-proxy-kubeconfig
	kubelet-master
	kube-proxy
	calico-image
      	calico-master
      	;;
    *)
      	echo "Usage: $0 {install|uninstall|reinstall}"
esac
