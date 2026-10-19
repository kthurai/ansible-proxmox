pipeline {
  agent any

  parameters {
    choice(name: 'ACTION', choices: ['create', 'destroy'], description: 'What to do')
    choice(name: 'VM_OS', choices: ['debian13', 'ubuntu2404', 'ubuntu2604', 'rhel10', 'centos10', 'rocky10', 'alma10', 'fedora44', 'fedora44ws', 'win11'], description: 'OS template (create only)')
    string(name: 'VM_NAME', defaultValue: '', description: 'VM name, e.g. web01')
    string(name: 'VM_CORES', defaultValue: '2')
    string(name: 'VM_MEMORY', defaultValue: '2048', description: 'MiB')
    string(name: 'VM_DISK_GB', defaultValue: '20')
    string(name: 'VM_IP', defaultValue: 'dhcp', description: "'dhcp' or CIDR, e.g. 192.168.5.80/23")
    string(name: 'VM_GW', defaultValue: '', description: 'Gateway (static IP only)')
    password(name: 'VM_PASSWORD', defaultValue: '', description: "Password for the VM user (required for fedora44ws; optional otherwise)")
  }

  environment {
    PVE_TOKEN_SECRET = credentials('pve-token-secret')   // Secret text
    VM_SSH_PUBKEY    = credentials('vm-ssh-pubkey')      // Secret text
    ANSIBLE_FORCE_COLOR = 'true'
  }

  options {
    disableConcurrentBuilds()   // avoids two builds grabbing the same next VMID
    timestamps()
  }

  stages {
    stage('Setup Ansible') {
      steps {
        script {
          // Name the build after what it does, e.g. "#11 create rhel10  |  web01"
          def what = params.ACTION == 'create' ? "create ${params.VM_OS}" : 'destroy'
          currentBuild.displayName = "#${env.BUILD_NUMBER} ${what}  |  ${params.VM_NAME ?: '(no name)'}"
          if (params.ACTION == 'create') {
            currentBuild.description = "${params.VM_CORES} vCPU  |  ${params.VM_MEMORY} MB  |  ${params.VM_DISK_GB} GB  |  IP ${params.VM_IP}"
          }
        }
        sh 'rm -f vm_result.txt && ./setup-venv.sh'
      }
    }

    stage('Create VM') {
      when { expression { params.ACTION == 'create' } }
      steps {
        sh '''
          . .venv/bin/activate
          ansible-playbook create_vm.yml \
            -e vm_name="$VM_NAME" -e vm_os="$VM_OS" \
            -e vm_cores="$VM_CORES" -e vm_memory="$VM_MEMORY" -e vm_disk_gb="$VM_DISK_GB" \
            -e vm_ip="$VM_IP" -e vm_gw="$VM_GW"
        '''
        script {
          // Show the real VMID / IP / size (after OS minimums) under the build
          if (fileExists('vm_result.txt')) {
            def r = [:]
            for (line in readFile('vm_result.txt').trim().split('\n')) {
              def kv = line.split('=', 2)
              r[kv[0]] = kv.size() > 1 ? kv[1] : ''
            }
            currentBuild.description = "VMID ${r.vmid}  |  IP ${r.ip ?: 'pending'}  |  " +
              "${params.VM_CORES} vCPU  |  ${r.memory} MB  |  ${r.disk_gb} GB"
          }
        }
      }
    }

    stage('Destroy VM') {
      when { expression { params.ACTION == 'destroy' } }
      steps {
        input message: "Really destroy ${params.VM_NAME}?", ok: 'Destroy'
        sh '''
          . .venv/bin/activate
          ansible-playbook destroy_vm.yml -e vm_name="$VM_NAME"
        '''
        script { currentBuild.description = 'VM deleted' }
      }
    }
  }
}
