#!/bin/bash
local_dir="rpool/data/"
current_date=`date +%Y_%m_%d_%H_%M_%S`
#echo $current_date
find /etc/pve/qemu-server/ -type f -name '*.conf' | while read vm_conf_file
do
        cat $vm_conf_file | grep local-zfs | cut -d ":" -f 3 | cut -d "," -f 1 | sort -u | while read vm_filesystem
        do
                echo $current_date - create snapshot - zfs snapshot ${local_dir}${vm_filesystem}@__backup_${current_date}
                zfs snapshot ${local_dir}${vm_filesystem}@__backup_${current_date}
        done
done


find /etc/pve/lxc/ -type f -name '*.conf' | while read ct_conf_file
do
        cat $ct_conf_file | grep local-zfs | cut -d ":" -f 3 | cut -d "," -f 1 | sort -u | while read ct_filesystem
        do
                echo $current_date - create snapshot - zfs snapshot ${local_dir}${ct_filesystem}@__backup_${current_date}
                zfs snapshot ${local_dir}${ct_filesystem}@__backup_${current_date}
        done
done
