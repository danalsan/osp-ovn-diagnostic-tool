#!/bin/bash

# Copyright 2022 Red Hat, Inc.
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

# Complete stackrc file path.
: ${STACKRC_FILE:=~/stackrc}

: ${STACK_NAME:=overcloud}
: ${OOO_WORKDIR:=$HOME/overcloud-deploy}

SCRIPT_DIR=$(dirname $0)

# Generate the ansible.cfg file
function generate_ansible_config_file() {

    cat > $SCRIPT_DIR/ansible.cfg <<-EOF
[defaults]
forks=50
callback_whitelist = profile_tasks
host_key_checking = False
gathering = smart
fact_caching = jsonfile
fact_caching_connection = ./ansible_facts_cache
fact_caching_timeout = 0
log_path = $SCRIPT_DIR/ovn-diagnostic-ansible.log
#roles_path = roles:...
[ssh_connection]
control_path = %(directory)s/%%h-%%r
ssh_args = -o ControlMaster=auto -o ControlPersist=270s -o ServerAliveInterval=30 -o GSSAPIAuthentication=no
retries = 3
EOF

}


# Generate the inventory file for ansible diagnostic playbooks.
function get_ansible_inventory_file() {
    local work_dir=$1
    local inventory_file=$work_dir/inventory.yaml

    if [ ! -f $inventory_file ]; then
        inventory_file="$OOO_WORKDIR/$STACK_NAME/config-download/$STACK_NAME/tripleo-ansible-inventory.yaml"
	if [ ! -f $inventory_file ]; then
            source $STACKRC_FILE
            inventory_file=$work_dir/inventory.yaml
            /usr/bin/tripleo-ansible-inventory --stack $STACK_NAME --static-yaml-inventory "$inventory_file"
	fi
    fi

    echo $inventory_file
}


function main() {
    inventory_file=$(get_ansible_inventory_file $SCRIPT_DIR)

    pushd $SCRIPT_DIR
    [ -d results ] || mkdir results
    ansible-playbook -i $inventory_file -e working_dir="$SCRIPT_DIR" diagnostics_play.yml 
    jq -s add results/*_results.json > results.json
    popd
}

main
