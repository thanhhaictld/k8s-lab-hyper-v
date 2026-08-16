for ip in 192.168.50.11 192.168.50.12 192.168.50.13 \
          192.168.50.21 192.168.50.22 192.168.50.23; do
  ssh -i ~/.ssh/kubespray_lab ansible@$ip \
    'echo "Checking connectivity to $ip" && \
     echo "-----------------------------" && \
     echo "Checking hostname..." && \
     echo "Checking sudo privileges..." && \
     sudo -l && \
     echo "-----------------------------" && \
     hostname && \
     echo "-----------------------------" && \
     echo "Checking OS version..." && \
     cat /etc/os-release && \
     echo "-----------------------------" && \
     echo "Checking disk space..." && \
     df -h && \
     echo "-----------------------------" && \
     echo "Checking memory usage..." && \
     free -h && \
     echo "-----------------------------" && \
     echo "Checking CPU info..." && \
     lscpu'
done