Usage

Added host information to /etc/hosts

example:
```
# MANAGED_HOSTS_BEGIN
10.99.239.90 slurm-ctrl
10.99.239.80 slurm-c01
10.99.239.153 slurm-c02
10.99.239.19 slurm-c03
# MANAGED_HOSTS_END
```

Run: (Default user: ubuntu)
```
./one_key_bootstrap.sh
```

If the OS default use change to another name, please modified "inventory/group_vars/all.yml"
```
ansible_user: "ubuntu"
ansible_ssh_private_key_file: "{{ lookup('env','HOME') + '/.ssh/id_ed25519' }}"

deploy_user: "ubuntu"
controller_pubkey_path: "{{ lookup('env','HOME') + '/.ssh/id_ed25519.pub' }}"

sudo_nopasswd: true
disable_password_auth: false

```


