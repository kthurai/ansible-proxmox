# ansible-proxmox

Create Proxmox VMs for a chosen OS from cloud-init templates, from the CLI or Jenkins.

```
build_templates.yml   one-time: downloads cloud images, builds tmpl-<os> Linux templates (SSH to Proxmox)
build_windows_template.yml  Windows 11 template (semi-manual, see below)
create_vm.yml         clones a template, sets CPU/RAM/disk/IP, starts it (Proxmox API)
destroy_vm.yml        stops and deletes a VM
group_vars/all/main.yml         Proxmox host, storage, bridge, cloud-init defaults  <- edit this
group_vars/all/os_catalog.yml   available OSes + template IDs + image URLs
files/snippets/       cloud-init first-boot scripts (e.g. Fedora Workstation desktop)
Jenkinsfile           parameterized create/destroy job
network_scan.yml      scan the home network -> reports/network_inventory.xlsx
deploy_docmost.yml    Docker + Docmost wiki (open-source Confluence alternative) on a VM
scripts/netscan.py    the scanner network_scan.yml runs
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
ansible-playbook build_templates.yml                     # all Linux OSes
ansible-playbook build_templates.yml -e only_os=debian13 # just one
```

## 3. Create a VM from the CLI

```bash
export PVE_TOKEN_SECRET='xxxxxxxx-xxxx-...'
ansible-playbook create_vm.yml -e vm_name=web01 -e vm_os=debian13
ansible-playbook create_vm.yml -e vm_name=db01 -e vm_os=rocky10 \
  -e vm_cores=4 -e vm_memory=8192 -e vm_disk_gb=60 \
  -e vm_ip=192.168.5.80/23 -e vm_gw=192.168.4.1
```

## 4. Jenkins

1. On the Jenkins server: `sudo dnf install -y git python3` (the job builds its own venv).
2. Give the `jenkins` user SSH access to Proxmox (needed for template builds):
   `sudo -u jenkins ssh-keygen -t ed25519 -N "" -f /var/lib/jenkins/.ssh/id_ed25519 && sudo -u jenkins ssh-copy-id root@192.168.5.75`
3. **Manage Jenkins → Credentials → System → Global**, add two *Secret text* credentials:
   - `pve-token-secret`: the Proxmox token secret
   - `vm-ssh-pubkey`: the SSH public key to put on new VMs
4. **New Item → Pipeline**, then under *Pipeline script from SCM* point to the repo (script path `Jenkinsfile`).
5. Run it once (it fails on the first run while Jenkins discovers the parameters), then use **Build with Parameters**.
6. **Destroy** uses a live drop-down of VMs (`VM_TO_DESTROY`), which needs the **Active Choices** plugin
   (*Manage Jenkins → Plugins → Available*). Its script reads the Proxmox token, so approve it once under
   *Manage Jenkins → In-process Script Approval*. Tick **CONFIRM_DESTROY** to actually delete.
   VMs listed in `protected_vms` (group_vars/all/main.yml) and templates are never offered or deleted.

## Available OSes

| vm_os | OS | Notes |
|---|---|---|
| debian13 | Debian 13 | |
| ubuntu2404 / ubuntu2604 | Ubuntu 24.04 / 26.04 LTS | |
| rhel10 | Red Hat Enterprise Linux 10.2 | image must be copied in manually (below) |
| centos10 | CentOS Stream 10 | CentOS Linux is end-of-life |
| rocky10 / alma10 | Rocky / AlmaLinux 10 | |
| fedora44 | Fedora 44 Server (cloud) | |
| fedora44ws | Fedora 44 Workstation (GNOME) | needs VM_PASSWORD; desktop installs on first boot (10-20 min) |
| win11 | Windows 11 | template built by build_windows_template.yml |

### RHEL 10.2

Red Hat images need a (free) account, so they can't be downloaded automatically.

1. Sign up for the free Red Hat Developer subscription, then download
   **Red Hat Enterprise Linux 10.2 KVM Guest Image** (qcow2) from https://access.redhat.com/downloads.
2. Copy it to proxmox1 as `/var/lib/vz/template/cloudimg/rhel10.qcow2`.
3. `ansible-playbook build_templates.yml -e only_os=rhel10`
4. New RHEL VMs get Red Hat's public **UBI** repositories at first boot (no registration) and run
   `dnf update --nobest`. UBI is a subset of RHEL: no kernel updates and some packages missing.
   For the full repositories, register instead: `sudo subscription-manager register --username <login>`.

### Windows 11

1. Put a Windows 11 ISO on an ISO storage (e.g. your `nfs-isos` share).
2. `ansible-playbook build_windows_template.yml -e win_iso='nfs-isos:iso/<file>.iso'`
   creates VM 9611 with UEFI, Secure Boot, TPM 2.0 and the VirtIO driver ISO, and starts it.
3. Install Windows in the Proxmox console; the playbook prints the steps
   (load the `vioscsi` driver, install `virtio-win-guest-tools.exe`, run sysprep).
   Before sysprep, turn off BitLocker, which Windows 11 enables automatically on a VM with a TPM
   (sysprep fails with "BitLocker is on for the OS volume" otherwise):
   `reg add HKLM\SYSTEM\CurrentControlSet\Control\BitLocker /v PreventDeviceEncryption /t REG_DWORD /d 1 /f`
   then `manage-bde -off C:` and wait for *Fully Decrypted*.
4. After sysprep shuts it down: `ansible-playbook build_windows_template.yml -e phase=finalize`.
5. With `files/windows/unattend.xml` (the sysprep step downloads it), clones keep your account, get a
   random computer name and boot straight to the login screen. Each clone needs its own Windows licence.
6. To re-make the template from another VM (e.g. a clone you updated and sysprepped):
   `ansible-playbook build_windows_template.yml -e phase=finalize -e from_vmid=<id>`

## Network inventory (Excel)

Finds every device on the LAN - including smart devices that ignore ping - and
writes an Excel sheet with IP, MAC, hostname, vendor, a device-type guess, mDNS/UPnP
names and models, and first/last-seen dates. New devices are marked **NEW** at the top.

```bash
ansible-playbook network_scan.yml -K                         # first time: installs tools + scans
ansible-playbook network_scan.yml -e scan_setup=false        # afterwards: no sudo needed
ansible-playbook network_scan.yml -e scan_setup=false -e scan_ports=true   # + open ports
```

Run it from a machine on the same network as the devices (the Jenkins server works).
It combines ARP sweeps (arp-scan, nmap), mDNS, UPnP/SSDP, reverse DNS and NetBIOS.
Devices that disappear are kept as *offline* for 90 days. Give devices names and notes
in `files/network/known_devices.yml` (by MAC) - they show up in every report.

### Nightly Jenkins job

1. Run the first-time command above once on the Jenkins server (sets up the tools and lets
   `arp-scan`/`nmap` scan without sudo).
2. **New Item → Pipeline** named `network-scan`, *Pipeline script from SCM*, this repo,
   branch `*/main`, **Script Path `Jenkinsfile.netscan`**.
3. It runs every night around 02:00 (or *Build Now*). Each build attaches
   `network_inventory.xlsx` and shows online/offline/new counts in its description.
   History is kept in `$JENKINS_HOME/network-inventory/`.

## Docmost wiki

[Docmost](https://docmost.com) is an open-source, Confluence-style wiki (spaces, pages,
real-time co-editing, comments; imports from Confluence/Notion).

1. Create a VM (Jenkins `proxmox-vm`): `debian13`, 2 vCPU, 4096 MB, 40 GB.
2. `ansible-playbook deploy_docmost.yml -e docmost_host=<vm-ip>`
3. Open `http://<vm-ip>:3000` and create the first account - it becomes the admin.

Installs Docker, runs Docmost + PostgreSQL + Redis with Docker Compose in `/opt/docmost`,
generates secrets once (kept in `/opt/docmost/.env`), and backs up the database and
uploads nightly to `/opt/docmost/backups` (14 days). Upgrade later with `-e docmost_pull=true`.

## Adding another OS

Add an entry to `group_vars/all/os_catalog.yml` with a unique `template_id`, run
`ansible-playbook build_templates.yml -e only_os=<key>`, and add the key to the
`VM_OS` choices in the Jenkinsfile.
