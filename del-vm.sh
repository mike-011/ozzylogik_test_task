#!/bin/bash

# сетим переменные
IMGPATH="/tmp/ozzylogik_test_task/images"
CLOUD_INIT_PATH="/tmp/ozzylogik_test_task/seed"

# удаляю виртуалки
virsh destroy ubu1 --graceful --remove-logs
virsh destroy ubu2 --graceful --remove-logs

virsh undefine --remove-all-storage --delete-storage-volume-snapshots ubu1
virsh undefine --remove-all-storage --delete-storage-volume-snapshots ubu2

# удаляю диски, что бы точно
rm -f ${IMGPATH}/ubu1.qcow2

rm -f ${IMGPATH}/ubu2.qcow2

rm -rf ${CLOUD_INIT_PATH}

# удаляю ключи
for ip in {1..254}; do
  ssh-keygen -f '/home/mike/.ssh/known_hosts' -R "192.168.122.$ip"
done

