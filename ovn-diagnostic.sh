#!/bin/bash

# Copyright 2018 Red Hat, Inc.
# All Rights Reserved.
#
#    Licensed under the Apache License, Version 2.0 (the "License"); you may
#    not use this file except in compliance with the License. You may obtain
#    a copy of the License at
#
#         http://www.apache.org/licenses/LICENSE-2.0
#
#    Unless required by applicable law or agreed to in writing, software
#    distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
#    WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
#    License for the specific language governing permissions and limitations
#    under the License.

# With LANG set to everything else than C completely undercipherable errors
# like "file not found" and decoding errors will start to appear during scripts
# or even ansible modules
LANG=C

# Complete stackrc file path.
: ${STACKRC_FILE:=~/stackrc}

# Complete overcloudrc file path.
: ${OVERCLOUDRC_FILE:=~/overcloudrc}

# user on the nodes in the undercloud
: ${UNDERCLOUD_NODE_USER:=heat-admin}

: ${OPT_WORKDIR:=$PWD}
: ${STACK_NAME:=overcloud}
: ${OOO_WORKDIR:=$HOME/overcloud-deploy}

# Generate the ansible.cfg file
generate_ansible_config_file() {

    cat > ansible.cfg <<-EOF
[defaults]
forks=50
become=True
callback_whitelist = profile_tasks
host_key_checking = False
gathering = smart
fact_caching = jsonfile
fact_caching_connection = ./ansible_facts_cache
fact_caching_timeout = 0
log_path = $HOME/ovn-diagnostic-ansible.log
#roles_path = roles:...
[ssh_connection]
control_path = %(directory)s/%%h-%%r
ssh_args = -o ControlMaster=auto -o ControlPersist=270s -o ServerAliveInterval=30 -o GSSAPIAuthentication=no
retries = 3
EOF


# Generate the inventory file for ansible diagnostic playbooks.
generate_ansible_inventory_file() {
    local inventory_file

    echo "Generating the inventory file for ansible-playbook"
    echo "[ovn-dbs]"  > hosts_to_diagnose
    ovn_central=True

    if [ -f /usr/bin/tripleo-ansible-inventory ]; then
        source $STACKRC_FILE
        inventory_file=$(mktemp --tmpdir ansible-inventory-XXXXXXXX.yaml)
        /usr/bin/tripleo-ansible-inventory --stack $STACK_NAME --static-yaml-inventory "$inventory_file"
    else
        local inventory_file="$OOO_WORKDIR/$STACK_NAME/config-download/$STACK_NAME/tripleo-ansible-inventory.yaml"
    fi

    # We want to run ovn_dbs where neutron_api is running
    OVN_DBS=$(get_group_hosts "$inventory_file" neutron_api)
    for node_name in $OVN_DBS; do
        node_ip=$(get_host_ip "$inventory_file" $node_name)
        node="$node_name ansible_host=$node_ip"
        if [ "$ovn_central" == "True" ]; then
            ovn_central=False
            node="$node_name ansible_host=$node_ip ovn_central=true"
        fi
        echo $node ansible_ssh_user=$UNDERCLOUD_NODE_USER ansible_become=true >> hosts_to_diagnose
    done

    echo "" >> hosts_to_diagnose
    echo "[ovn-controllers]" >> hosts_to_diagnose

    OVN_CONTROLLERS=$(get_group_hosts "$inventory_file" ovn_controller)
    for node_name in $OVN_CONTROLLERS; do
        node_ip=$(get_host_ip "$inventory_file" $node_name)
        echo $node_name ansible_host=$node_ip
        ansible_ssh_user=$UNDERCLOUD_NODE_USER ansible_become=true ovn_controller=true >> hosts_to_diagnose
    done

    echo "" >> hosts_to_diagnose

    cat >> hosts_to_diagnose << EOF
[overcloud:children]
ovn-controllers
ovn-dbs
EOF
    add_group_vars() {

    cat >> hosts_to_diagnose << EOF
[$1:vars]
remote_user=$UNDERCLOUD_NODE_USER
overcloudrc=$OVERCLOUDRC_FILE
EOF
    }

    add_group_vars overcloud
    add_group_vars overcloud-controllers


    echo "***************************************"
    cat hosts_to_diagnose
    echo "***************************************"
    echo "Generated the inventory file - hosts_to_diagnose"
    echo "Please review the file before running the next command - setup-mtu-t1"
}

