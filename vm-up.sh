#!/bin/bash

# Обновление и установка пакетов на хост машине
sudo apt update
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager cloud-image-utils ansible sshpass

# сетим переменные
IMGPATH="/tmp/ozzylogik_test_task/images"
CLOUD_INIT_PATH="/tmp/ozzylogik_test_task/seed"
OZZYUSER="ozzyuser"
OZZYSECRET="ozzypass"

# Создаем пути/директории для образов и cloud-init метаданных, что бы потом легче было почистить
mkdir -p ${IMGPATH} ${CLOUD_INIT_PATH}

# Скачивание образа Ubuntu 24.04 LTS (если ещё не скачан) #ubuntu-22.04.qcow2 
if [ ! -f ${IMGPATH}/ubuntu-24.04.qcow2 ]; then
  echo "Download Ubuntu 24.04 cloud image..."
  wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img -O ${IMGPATH}/ubuntu-24.04.qcow2
fi

# Создание файла конфигурации cloud-init для создания пользователя и пароля
cat <<EOF > ${CLOUD_INIT_PATH}/user-data
#cloud-config
users:
  - name: ${OZZYUSER}
    sudo: ["ALL=(ALL) NOPASSWD:ALL"]
    shell: /bin/bash
    lock_passwd: false
    passwd: $(openssl passwd -6 ${OZZYSECRET})  # Задаем пароль/хеш для пользователя ubuntu
    ssh_pwauth: true  # Разрешить SSH-аутентификацию по паролю
    chpasswd:
      expire: False   # Отключить принудительную смену пароля
ssh_pwauth: true      # Включить аутентификацию по паролю для SSH

package_update: true  # Обновить древо пакетов ВМ
packages:
  - qemu-guest-agent  # Установить QEMU Guest Agent

runcmd:
  - systemctl enable qemu-guest-agent # Включить QEMU Guest Agent для автозапуска
  - systemctl start qemu-guest-agent  # Запустить QEMU Guest Agent
  - growpart /dev/vda 1               # Расширение партиции
  - resize2fs /dev/vda1               # Расширение файловой системы
EOF

# Создание метаданных cloud-init
cloud-localds ${CLOUD_INIT_PATH}/seed.img ${CLOUD_INIT_PATH}/user-data

# Создание виртуальных машин
for i in 1 2; do
  VM_NAME="ubu${i}"
  echo "Creating VM $VM_NAME..."

  # Копирование образа для каждой ВМ
  cp ${IMGPATH}/ubuntu-24.04.qcow2 ${IMGPATH}/${VM_NAME}.qcow2

  # Увеличение размера виртуального диска до 10 ГБ
  qemu-img resize ${IMGPATH}/${VM_NAME}.qcow2 10G

  # Создаем виртуальные машины QEMU
  virt-install \
    --name ${VM_NAME} \
    --ram 2048 \
    --vcpus 2 \
    --disk path=${IMGPATH}/${VM_NAME}.qcow2 \
    --disk path=${CLOUD_INIT_PATH}/seed.img,device=cdrom \
    --os-variant ubuntu24.04 \
    --network bridge=virbr0,model=virtio \
    --graphics none \
    --console pty,target_type=serial \
    --import \
    --noautoconsole
done

echo "All VMs created!"

# Проверка состояния виртуальных машин
virsh list --all

# Удаляю шаблон образа
# rm -f ${IMGPATH}/ubuntu-24.04.qcow2

# Ожидание завершения настройки машин
sleep 60

# Создание Ansible inventory-файла
cat <<EOF > ./ansible/inventory
# Задаю глобальные переменные для Ансиюл
[all:vars]
ansible_connection=ssh
ansible_user=${OZZYUSER}
ansible_ssh_pass=${OZZYSECRET}
ansible_port=22
#не строго проверять ключи, для демонстрашки подходит
ansible_ssh_common_args="-o StrictHostKeyChecking=no"

# создаю две групы хостов
# беру ip с созданных виртуалок, через агента внутри и убираю ip 127.*
# и кладу их в группу хостов
[ubu1]
$(virsh domifaddr ubu1 --source agent | grep ipv4 | awk '{print $4}' | grep -v '^127\.' | cut -d'/' -f1)

[ubu2]
$(virsh domifaddr ubu2 --source agent | grep ipv4 | awk '{print $4}' | grep -v '^127\.' | cut -d'/' -f1)
EOF

# test ansible
ansible all -m ping -i ./ansible/inventory