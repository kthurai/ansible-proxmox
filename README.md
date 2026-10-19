# ansible-proxmox

Create Proxmox VMs for a chosen OS from cloud-init templates, from the CLI or Jenkins.

```
build_templates.yml   one-time: downloads cloud images, builds tmpl-<os> templates (SSH to Proxmox)
create_vm.yml         clones a template, sets CPU/RAM/disk/IP, starts it (Proxmox API)
destroy_vm.yml        stops and deletes a VM
group_vars/all/main.yml         Proxmox host, storage, bridge, cloud-init defaults  <- edit this
group_vars/all/os_catalog.yml   available OSes + template IDs + image URLs
Jenkinsfile           parameterized create/destroy job
setup-venv.sh         creates .venv + installs Ansible, proxmoxer, collections
requirements.txt      Python packages for the venv
```

## 0. Controller setup (venv)

On the machine that runs Ansible (e.g. the Jenkins server):

```bash
sudo dnf install -y git python3
git clone https://github.com/kthurai/ansible-proxmox.git && cd ansible-proxmox
./setup-venv.sh
source .venv/bin/activate     # do this in every new shell
```

Everything (Ansible, proxmoxer, the community.proxmox collection) lives inside
`.venv/` and `collections/` in this folder - nothing is installed system-wide.

## 1. Proxmox: API user and token (run on proxmox1)

```bash
pveum user add ansible@pve --comment "Ansible automation"
pveum aclmod / -user ansible@pve -role PVEVMAdmin
pveum aclmod /storage -user ansible@pve -role PVEDatastoreUser
pveum aclmod /sdn -user ansible@pve -role PVESDNUser
pveum user token add ansible@pve automation --privsep 0
```

Copy the token **secret** it prints; it's shown only once.

## 2. Build the templates (once)

From any machine with SSH key access to `root@proxmox1`:

```bash
ansible-playbook build_templates.yml                     # all OSes
ansible-playbook build_templates.yml -e only_os=debian13 # just one
```

## 3. Create a VM from the CLI

```bash
export PVE_TOKEN_SECRET='xxxxxxxx-xxxx-...'
ansible-playbook create_vm.yml -e vm_name=web01 -e vm_os=debian13
ansible-playbook create_vm.yml -e vm_name=db01 -e vm_os=rocky10 \
  -e vm_cores=4 -e vm_memory=8192 -e vm_disk_gb=60 \
  -e vm_ip=192.168.4.50/24 -e vm_gw=192.168.4.1
```

## 4. Jenkins

1. On the Jenkins server: `sudo dnf install -y git python3` (the job builds its own venv).
2. Give the `jenkins` user SSH access to Proxmox (needed for template builds):
   `sudo -u jenkins ssh-keygen -t ed25519 -N "" -f /var/lib/jenkins/.ssh/id_ed25519 && sudo -u jenkins ssh-copy-id root@192.168.4.10`
3. **Manage Jenkins → Credentials → System → Global**, add two *Secret text* credentials:
   - `pve-token-secret`: the Proxmox token secret
   - `vm-ssh-pubkey`: the SSH public key to put on new VMs
4. **New Item → Pipeline**, then under *Pipeline script from SCM* point to the repo (script path `Jenkinsfile`).
5. Run it once (it fails on the first run while Jenkins discovers the parameters), then use **Build with Parameters**.

## Adding another OS

Add an entry to `group_vars/all/os_catalog.yml` with a unique `template_id`, run
`ansible-playbook build_templates.yml -e only_os=<key>`, and add the key to the
`VM_OS` choices in the Jenkinsfile.
