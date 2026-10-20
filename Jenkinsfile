pipeline {
  agent any

  parameters {
    choice(name: 'ACTION', choices: ['create', 'destroy'], description: 'What to do')
    choice(name: 'VM_OS', choices: ['debian13', 'ubuntu2404', 'ubuntu2604', 'rhel10', 'centos10', 'rocky10', 'alma10', 'fedora44', 'fedora44ws', 'win11'], description: 'OS template (create only)')
    string(name: 'VM_NAME', defaultValue: '', description: 'create only: name for the new VM, e.g. web01')
    string(name: 'VM_CORES', defaultValue: '2')
    string(name: 'VM_MEMORY', defaultValue: '2048', description: 'MiB')
    string(name: 'VM_DISK_GB', defaultValue: '20')
    string(name: 'VM_IP', defaultValue: 'dhcp', description: "'dhcp' or CIDR, e.g. 192.168.5.80/23")
    string(name: 'VM_GW', defaultValue: '', description: 'Gateway (static IP only)')
    password(name: 'VM_PASSWORD', defaultValue: '', description: "Password for the VM user (required for fedora44ws; optional otherwise)")
    reactiveChoice(
      name: 'VM_TO_DESTROY',
      description: 'destroy only: pick the VM (live list from Proxmox; templates and protected VMs are hidden)',
      choiceType: 'PT_SINGLE_SELECT',
      filterable: true,
      filterLength: 1,
      referencedParameters: 'ACTION',
      script: groovyScript(
        script: [classpath: [], oldScript: '', sandbox: false, script: '''// Lists the VMs on Proxmox when ACTION = destroy (Active Choices plugin).
// Keep these three values in step with group_vars/all/main.yml.
def PVE_URL   = "https://192.168.5.75:8006/api2/json/cluster/resources?type=vm"
def TOKEN_ID  = "ansible@pve!automation"
def PROTECTED = ["Fedora43-srv-01"]

if (ACTION != "destroy") { return ["(set ACTION to destroy to list VMs)"] }
def cred = com.cloudbees.plugins.credentials.SystemCredentialsProvider.getInstance()
             .getCredentials().find { it.id == "pve-token-secret" }
if (cred == null) { return ["(Jenkins credential pve-token-secret not found)"] }
def proc = ["curl", "-sk", "--max-time", "10",
            "-H", "Authorization: PVEAPIToken=" + TOKEN_ID + "=" + cred.secret.plainText,
            PVE_URL].execute()
def out = proc.text
proc.waitFor()
def vms = new groovy.json.JsonSlurper().parseText(out).data
            .findAll { !it.template && !(it.name in PROTECTED) }
            .sort { it.name.toLowerCase() }
if (!vms) { return ["(no VMs to destroy)"] }
return vms.collect { it.name + " (" + it.vmid + ") - " + it.status }
'''],
        fallbackScript: [classpath: [], oldScript: '', sandbox: false,
                         script: 'return ["(could not load VMs - check Manage Jenkins > In-process Script Approval)"]']
      )
    )
    booleanParam(name: 'CONFIRM_DESTROY', defaultValue: false, description: 'Tick to confirm deleting the VM picked in VM_TO_DESTROY. Unticked = nothing is deleted.')
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
          def who = params.ACTION == 'destroy' ? (params.VM_TO_DESTROY ?: '').split(' - ')[0] : params.VM_NAME
          currentBuild.displayName = "#${env.BUILD_NUMBER} ${what}  |  ${who ?: '(no name)'}"
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
        script {
          // Safety checks instead of an input prompt.
          def pick = params.VM_TO_DESTROY ?: ''
          if (!pick.contains('(') || !pick.contains(')')) {
            currentBuild.description = 'Not destroyed: no VM picked'
            error('Refusing to destroy: pick a VM in VM_TO_DESTROY.')
          }
          if (!params.CONFIRM_DESTROY) {
            currentBuild.description = 'Not destroyed: CONFIRM_DESTROY was not ticked'
            error("Refusing to destroy ${pick}: tick CONFIRM_DESTROY to confirm.")
          }
          env.DESTROY_VMID = pick.substring(pick.indexOf('(') + 1, pick.indexOf(')')).trim()
          if (!(env.DESTROY_VMID ==~ /\d+/)) {
            currentBuild.description = 'Not destroyed: no VM picked'
            error("Refusing to destroy: '${pick}' is not a VM.")
          }
        }
        sh '''
          . .venv/bin/activate
          ansible-playbook destroy_vm.yml -e vm_id="$DESTROY_VMID"
        '''
        script { currentBuild.description = 'VM deleted' }
      }
    }
  }
}
