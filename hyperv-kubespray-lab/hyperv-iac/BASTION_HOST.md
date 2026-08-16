# Install python3.12

```bash
sudo apt update

sudo apt install software-properties-common && sudo apt-add-repository ppa:ansible/ansible

sudo apt install python3.12-venv

```

# Install kube spray

```bash
git clone https://github.com/kubernetes-sigs/kubespray.git
cd kubespray
git checkout release-2.17
```

## Install pip an virtual environment
```
pip install -r requirements.txt
python3 -m venv venv
source venv/bin/activate
```

## Test ping

```bash
ansible all \
  -i ./inventory/mycluster/inventory.ini \
  -m ping \
  --private-key ~/.ssh/kubespray_lab
```
