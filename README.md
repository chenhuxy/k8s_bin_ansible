# k8s_bin_ansible

使用ansible+shell脚本安装kubernetes二进制。

k8s version：v1.15.0，所有安装包已下载，适合内网环境直接安装。

机器列表：

    IP    ROLE
  
    10.58.133.11  haproxy
  
    10.58.133.2   k8s-master-1,etcd01,ansible
  
    10.58.133.3   k8s-master-2,etcd02
  
    10.58.133.4   k8s-master-3,etcd03
   
    10.58.133.5   k8s-node-1 
    
准备环境：centos7.x机器5台，ansible,ansible到其他机器免密登录

    1. yum install ansible -y
    
    2. mv /etc/ansible  /etc/ansible.default

    3. git clone https://github.com/chenhuxy/k8s_bin_ansible.git
    
    4. systemctl start --now ansible
    
    5. 免密登录工具在tool目录下
    

安装步骤：
    
    1. 安装haproxy
        
        yum install haproxy -y
        
    2.  修改haproxy.cfg,添加以下配置
        
        listen k8s-master
        bind 0.0.0.0:6443
        mode tcp
        option tcplog
        option dontlognull
        option dontlog-normal
        balance roundrobin
        server k8s-master-1 10.58.133.2:6443 check inter 5s fall 2 rise 2 weight 1
        server k8s-master-2 10.58.133.3:6443 check inter 5s fall 2 rise 2 weight 1
        server k8s-master-3 10.58.133.4:6443 check inter 5s fall 2 rise 2 weight 1
    
    3.  启动haproxy
        
        systemctl enable --now haproxy
        
    4.  安装etcd
    
        下载release下etcd安装包放至/etc/ansible/roles/k8s-etcd/files下
        
        ansible-playbook k8s-etcd.yaml
        
        至master机器执行 /tmp/01_etcd.sh install
        
        
        
    5.  安装docker

        下载release下docker安装包放至 k8s-init role下
        
        ansible-playbook k8s-init.yaml
        
    6.  安装k8s-master
    
        下载release下kubernetes/calico/pause安装包至k8s-master role下
        
        ansible-playbook k8s-master.yaml
        
        至master机器执行 /tmp/00_init.sh;(报错再执行一遍即可)
        
        /tmp/02_k8s_master_calico.sh install（卸载：uninstall，重装：reinstall）
        
    7.  安装k8s-node
    
        下载release下kubernetes/calico/pause安装包至k8s-node role下
        
        ansible-playbook k8s-node.yaml
        
        至node机器执行 /tmp/00_init.sh;(报错再执行一遍即可)
        
        /tmp/03_k8s_node_calico.sh install（卸载：uninstall，重装：reinstall）
        
    8. 添加环境变量
    
        ansible-playbook k8s-env.yaml
        
    9.  查看集群状态

        kubectl get nodes；kubectl get cs
        
    10. 安装集群插件，coredns/dashboard/ingress

        下载release下coredns/dashboard/ingress-nginx安装包至k8s-addon role下
        
        ansible-playbook k8s-addon.yaml
        
        查看pod，svc：
        
        kubectl get pods,svc -A -o wide

        
        
        
        
    


