#!/bin/bash
source_dir="rpool/data/"
target_dir="backup/hn02/"
source_host=hn02
source_port=22

echo ""
echo ---------------------------
echo ""

synchronize_snapshot_for_vm () {
        ssh -n $source_host -p $source_port cat $vm_conf_file | grep local-zfs | cut -d ":" -f 3 | cut -d "," -f 1 | sort -u | while read vm_filesystem
        do
                echo ""
                echo "`date +%Y_%m_%d_%H_%M_%S` - $vm_filesystem - Analizing disc"

                if [ `zfs get -H -o value receive_resume_token ${target_dir}${vm_filesystem} 2>/dev/null | grep -v '^-$' | wc -l` -eq 1 ]
                then
                        echo "Detected interrupted receive for ${target_dir}${vm_filesystem}. Manual action required."
                        # TODO: auto resume / auto heal
                        continue
                fi

                last_local_snapshot_path=`zfs list -t snapshot -r ${target_dir}${vm_filesystem} -o name -s creation 2>/dev/null | tail -n 1`

                if [ `echo $last_local_snapshot_path | grep ${target_dir}${vm_filesystem} | wc -l` -eq 1 ]
                then
                        last_local_snapshot_id=`echo $last_local_snapshot_path | cut -d "@" -f 2`
                        echo Initializing incremental backup for ${vm_filesystem}. Last detected snapshot on backup server is ${last_local_snapshot_id}.

                        if [ `ssh -n $source_host -p $source_port zfs list -t snapshot -r ${source_dir}${vm_filesystem} -o name -s creation 2>/dev/null | cut -d "@" -f 2 | grep "__backup_" | tail -n 1 | grep "^${last_local_snapshot_id}\$" | wc -l` -eq 1 ]
                        then
                                echo "Backup for vm `echo $vm_conf_file | awk -F "/" '{print $(NF)}' | cut -d "." -f 1` already synchronized."
                        elif [ `ssh -n $source_host -p $source_port zfs list -t snapshot -r ${source_dir}${vm_filesystem} -o name -s creation 2>/dev/null | cut -d "@" -f 2 | grep "__backup_" | grep "^${last_local_snapshot_id}\$" | wc -l` -eq 0 ]
                        then
                                echo "Backup missmatch snapshot id version. Snapshot id=\"${last_local_snapshot_id}\" not found on source server for vm `echo $vm_conf_file | awk -F "/" '{print $(NF)}' | cut -d "." -f 1`."
                        else
                                snapshot_match=0
                                previous_remote_snapshot_id="x"

                                ssh -n $source_host -p $source_port zfs list -t snapshot -r ${source_dir}${vm_filesystem} -o name -s creation 2>/dev/null | grep "__backup_" | cut -d "@" -f 2 | while read remote_snapshot_id
                                do
                                        if [ "$snapshot_match" -eq 1 ]
                                        then
                                                echo "`date +%Y_%m_%d_%H_%M_%S` - ssh -n $source_host -p $source_port zfs send -I ${source_dir}${vm_filesystem}@${previous_remote_snapshot_id} ${source_dir}${vm_filesystem}@${remote_snapshot_id} | zfs recv -F ${target_dir}${vm_filesystem}"
                                                ssh -n $source_host -p $source_port zfs send -I ${source_dir}${vm_filesystem}@${previous_remote_snapshot_id} ${source_dir}${vm_filesystem}@${remote_snapshot_id} | zfs recv -F ${target_dir}${vm_filesystem}
                                        fi

                                        previous_remote_snapshot_id=$remote_snapshot_id

                                        if [ "$remote_snapshot_id" = "$last_local_snapshot_id" ]
                                        then
                                                snapshot_match=1
                                        fi
                                done
                        fi
                else
                        if [ `ssh -n $source_host -p $source_port zfs list -t snapshot -r ${source_dir}${vm_filesystem} -o name -s creation 2>/dev/null | cut -d "@" -f 2 | grep "__backup_" | tail -n 1 | wc -l` -eq 1 ]
                        then
                                last_remote_snapshot_id=`ssh -n $source_host -p $source_port zfs list -t snapshot -r ${source_dir}${vm_filesystem} -o name -s creation 2>/dev/null | cut -d "@" -f 2 | grep "__backup_" | tail -n 1`
                                echo "`date +%Y_%m_%d_%H_%M_%S` - ssh -n $source_host -p $source_port zfs send ${source_dir}${vm_filesystem}@${last_remote_snapshot_id} | zfs recv ${target_dir}${vm_filesystem}"
                                ssh -n $source_host -p $source_port zfs send ${source_dir}${vm_filesystem}@${last_remote_snapshot_id} | zfs recv ${target_dir}${vm_filesystem}
                                date
                        fi
                fi

                last_source_snapshot_id=`ssh -n $source_host -p $source_port zfs list -t snapshot -r ${source_dir}${vm_filesystem} -o name -s creation 2>/dev/null | cut -d "@" -f 2 | grep "__backup_" | tail -n 1`
                last_target_snapshot_id=`zfs list -t snapshot -r ${target_dir}${vm_filesystem} -o name -s creation 2>/dev/null | cut -d "@" -f 2 | grep "__backup_" | tail -n 1`

                if [ `echo "$last_source_snapshot_id" | wc -l` -eq 1 ] && [ "$last_source_snapshot_id" = "$last_target_snapshot_id" ]
                then
                        ssh -n $source_host -p $source_port zfs list -t snapshot -r ${source_dir}${vm_filesystem} -o name -s creation 2>/dev/null | grep "__backup_" | head -n -7 | while read old_snapshot
                        do
                                echo ssh -n $source_host -p $source_port zfs destroy $old_snapshot
                                ssh -n $source_host -p $source_port zfs destroy $old_snapshot
                        done
                else
                        echo "Skip old snapshot cleanup for ${vm_filesystem}. Latest snapshot not synchronized."
                fi

                echo "`date +%Y_%m_%d_%H_%M_%S` - $vm_filesystem - Backup finished"
        done
}

ssh -n $source_host -p $source_port find /etc/pve/qemu-server/ -type f -name '*.conf' | egrep "150|152|157" | while read vm_conf_file
do
        synchronize_snapshot_for_vm
done

ssh -n $source_host -p $source_port find /etc/pve/lxc/ -type f -name '*.conf' | egrep "150|152|157" | while read vm_conf_file
do
        synchronize_snapshot_for_vm
done
