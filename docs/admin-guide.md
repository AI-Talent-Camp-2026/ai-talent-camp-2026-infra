# Руководство администратора

> **Последнее обновление:** 2026-01-29  
> **Связанные документы:** [architecture.md](architecture.md), [xray-configuration.md](xray-configuration.md), [modules.md](modules.md)

## Обзор

Это руководство для администраторов, управляющих инфраструктурой AI Camp через Terraform.

---

## Содержание

- [Prerequisites](#prerequisites)
- [Настройка Yandex Cloud](#настройка-yandex-cloud)
- [Развертывание инфраструктуры](#развертывание-инфраструктуры)
- [Управление командами](#управление-командами)
- [Конфигурация Xray](#конфигурация-xray)
- [Конфигурация Traefik](#конфигурация-traefik)
- [Мониторинг](#мониторинг)
- [Backup и восстановление](#backup-и-восстановление)

---

## Prerequisites

### Обязательные инструменты

#### Terraform >= 1.0

```bash
# Установка на Linux
wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
unzip terraform_1.6.0_linux_amd64.zip
sudo mv terraform /usr/local/bin/

# Проверка
terraform version
```

#### Yandex Cloud CLI

```bash
# Установка
curl -sSL https://storage.yandexcloud.net/yandexcloud-yc/install.sh | bash

# Перезагрузить shell
exec -l $SHELL

# Проверка
yc version
```

#### SSH клиент

Обычно предустановлен на Linux/macOS. Для Windows используйте WSL или Git Bash.

### Опциональные инструменты

```bash
# jq - для работы с JSON
sudo apt install jq

# yq - для работы с YAML
wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq
```

---

## Настройка Yandex Cloud

### 1. Инициализация CLI

```bash
# Авторизация в Yandex Cloud
yc init

# Выбрать нужный cloud и folder
```

### 2. Создание сервисного аккаунта для Terraform

```bash
# Создать service account
yc iam service-account create --name terraform-sa

# Получить ID service account
SA_ID=$(yc iam service-account get terraform-sa --format json | jq -r .id)

# Назначить роль editor
yc resource-manager folder add-access-binding <folder-id> \
  --role editor \
  --subject serviceAccount:$SA_ID

# Создать authorized key
yc iam key create \
  --service-account-name terraform-sa \
  --output key.json
```

### 3. Настройка credentials для Terraform

**Вариант A: Service Account Key (рекомендуется)**

```bash
export YC_SERVICE_ACCOUNT_KEY_FILE=/path/to/key.json
```

**Вариант B: OAuth Token**

```bash
export YC_TOKEN=$(yc iam create-token)
export YC_CLOUD_ID=$(yc config get cloud-id)
export YC_FOLDER_ID=$(yc config get folder-id)
```

⚠️ **Важно:** OAuth token действителен 12 часов. Обновляйте перед длительными операциями.

---

## Развертывание инфраструктуры

### 1. Клонирование репозитория

```bash
git clone https://gitlab.com/aitalenthub-core/ai-talent-camp-2026-infra.git
cd ai-talent-camp-2026-infra
```

### 2. Настройка переменных

```bash
cd environments/dev
cp terraform.tfvars.example terraform.tfvars
```

Отредактируйте `terraform.tfvars`:

```hcl
# Обязательные параметры
folder_id       = "b1gxxxxxxxxxxxxxxxxxx"
jump_public_key = "ssh-ed25519 AAAA... admin@example.com"

# Сетевые настройки (можно оставить по умолчанию)
public_cidr  = "192.168.1.0/24"
private_cidr = "10.20.0.0/24"

# Начальное развертывание - без команд
teams = {}
```

### 3. Поэтапное развертывание

Рекомендуется развертывать инфраструктуру поэтапно.

#### Phase 1: Базовая инфраструктура (Edge VM)

```bash
cd environments/dev

# Инициализация Terraform
terraform init

# Проверка плана
terraform plan

# Применение
terraform apply
```

**Создается:**
- VPC network
- Public и private subnets
- Security groups
- Edge/NAT VM с Traefik и Xray
- Route table

**Время:** ~5 минут

**Проверка:**
```bash
# Получить публичный IP
terraform output edge_public_ip

# Проверить SSH доступ
ssh jump@<edge-public-ip>

# Проверить Traefik
ssh jump@<edge-public-ip> "docker ps | grep traefik"

# Проверить Xray
ssh jump@<edge-public-ip> "sudo systemctl status xray"
```

#### Phase 2: Тестовая команда

Добавьте одну команду для тестирования:

```hcl
# terraform.tfvars
teams = {
  "01" = {
    user        = "team01"
    public_keys = []  # Ключи генерируются автоматически
  }
}
```

```bash
terraform apply
```

**Создается:**
- Team VM в private subnet
- SSH ключи в `secrets/team-01/`
- Traefik routing для `team01.camp.aitalenthub.ru`

**Проверка:**
```bash
# Проверить VM создана
terraform output team_vms

# Проверить SSH подключение
ssh -F ../../secrets/team-01/ssh-config team01

# На team VM проверить интернет
curl ifconfig.co
```

#### Phase 3: Остальные команды

Добавляйте команды по мере регистрации:

```hcl
teams = {
  "01" = { user = "team01", public_keys = [] }
  "02" = { user = "team02", public_keys = [] }
  "03" = { user = "team03", public_keys = [] }
  # ...
}
```

```bash
terraform apply
```

Terraform создаст только новые VM, не трогая существующие.

### 4. Настройка DNS

После развертывания настройте DNS записи:

```bash
# Получить публичный IP edge
EDGE_IP=$(terraform output -raw edge_public_ip)

echo "Добавьте DNS записи:"
echo "*.camp.aitalenthub.ru     A  $EDGE_IP"
echo "bastion.camp.aitalenthub.ru  A  $EDGE_IP"
```

В вашем DNS провайдере добавьте:

```
*.camp.aitalenthub.ru        A    <edge-public-ip>
bastion.camp.aitalenthub.ru  A    <edge-public-ip>
```

**Проверка DNS:**
```bash
dig team01.camp.aitalenthub.ru
dig bastion.camp.aitalenthub.ru
```

---

## Управление командами

### Добавление новой команды

1. **Обновить terraform.tfvars:**
   ```hcl
   teams = {
     "01" = { user = "team01", public_keys = [] }
     "02" = { user = "team02", public_keys = [] }
     "03" = { user = "team03", public_keys = [] }  # новая
   }
   ```

2. **Применить изменения:**
   ```bash
   terraform apply
   ```

3. **Получить credentials:**
   ```bash
   # Credentials создаются в:
   ls -la ../../secrets/team-03/
   
   # Передать папку команде
   zip -r team-03.zip ../../secrets/team-03/
   ```

4. **Настроить DNS** (если не используется wildcard):
   ```
   team03.camp.aitalenthub.ru  A  <edge-public-ip>
   ```

### Удаление команды

⚠️ **Внимание:** Данные на VM будут потеряны!

1. **Backup данных** (если нужно):
   ```bash
   ssh -F ~/.ssh/ai-camp/ssh-config team03 "tar czf ~/backup.tar.gz ~/workspace"
   scp -F ~/.ssh/ai-camp/ssh-config team03:~/backup.tar.gz ./team03-backup.tar.gz
   ```

2. **Удалить из terraform.tfvars:**
   ```hcl
   teams = {
     "01" = { user = "team01", public_keys = [] }
     "02" = { user = "team02", public_keys = [] }
     # "03" - удалена
   }
   ```

3. **Применить изменения:**
   ```bash
   terraform apply
   ```

### Изменение ресурсов VM

**В terraform.tfvars:**

```hcl
# Для всех team VMs
team_cores      = 8      # было 4
team_memory     = 16     # было 8
team_disk_size  = 100    # было 65
```

⚠️ **Внимание:** Это пересоздаст все team VMs. Сделайте backup!

---

## Конфигурация Xray

Подробнее см. [xray-configuration.md](xray-configuration.md).

### Обновление конфигурации (рекомендованный способ)

```bash
# 1. Отредактировать конфиг
nano ../../secrets/xray-config.json

# 2. Проверить валидность JSON
jq . ../../secrets/xray-config.json

# 3. Применить через Terraform
terraform apply
```

Terraform автоматически:
- Скопирует конфиг на edge VM
- Перезапустит Xray сервис
- Проверит статус

### Изменение proxy сервера

При смене proxy сервера нужно обновить 2 параметра:

**1. В `secrets/xray-config.json`:**
```json
{
  "outbounds": [{
    "tag": "proxy",
    "protocol": "shadowsocks",  // или vless, vmess и т.д.
    "settings": {
      // Настройки нового proxy сервера
    }
  }]
}
```

**2. Добавить IP в routing исключения:**
```json
{
  "routing": {
    "rules": [
      {
        "type": "field",
        "ip": ["<new-proxy-server-ip>"],
        "outboundTag": "direct"
      }
    ]
  }
}
```

**3. Применить:**
```bash
terraform apply
```

**4. Обновить iptables исключения:**
```bash
ssh jump@bastion.camp.aitalenthub.ru
sudo iptables -t mangle -I XRAY 5 -d <new-proxy-server-ip> -j RETURN
sudo netfilter-persistent save
```

---

## Конфигурация Traefik

### Статическая конфигурация

Редко изменяется. Находится в `templates/traefik/traefik.yml`.

```yaml
entryPoints:
  web:
    address: ":80"
  websecure:
    address: ":443"

providers:
  file:
    directory: /etc/traefik/dynamic
    watch: true
```

### Динамическая конфигурация

Генерируется автоматически через `module.config_sync`.

**Расположение:** `secrets/traefik-dynamic.yml`

**Формат:**
```yaml
tcp:
  routers:
    team01:
      entryPoints: ["websecure"]
      rule: "HostSNI(`team01.camp.aitalenthub.ru`)"
      service: "team01"
      tls:
        passthrough: true
  services:
    team01:
      loadBalancer:
        servers:
          - address: "10.20.0.8:443"
```

При добавлении новой команды конфиг обновляется автоматически через `terraform apply`.

---

## Мониторинг

### Проверка статуса компонентов

```bash
# SSH к edge VM
ssh jump@bastion.camp.aitalenthub.ru

# Traefik
docker ps | grep traefik
docker logs traefik --tail 50

# Xray
sudo systemctl status xray
sudo journalctl -u xray -n 50

# System resources
htop
df -h
free -m
```

### Логи

**Locations:**
- Traefik: `docker logs traefik`
- Xray access: `/var/log/xray/access.log`
- Xray error: `/var/log/xray/error.log`
- System: `journalctl -f`

**Полезные команды:**
```bash
# Мониторинг Xray в реальном времени
sudo tail -f /var/log/xray/access.log

# Поиск ошибок
sudo grep -i error /var/log/xray/error.log

# Статистика по routing
sudo grep "outboundTag" /var/log/xray/access.log | \
  awk '{print $NF}' | sort | uniq -c
```

---

## Backup и восстановление

### Backup конфигурации

```bash
# Backup всех secrets
tar czf ai-camp-backup-$(date +%Y%m%d).tar.gz secrets/

# Backup Terraform state
cp environments/dev/terraform.tfstate terraform.tfstate.backup

# Backup конфигов с серверов
ssh jump@bastion.camp.aitalenthub.ru \
  "sudo tar czf /tmp/configs-backup.tar.gz /opt/xray /opt/traefik"
scp jump@bastion.camp.aitalenthub.ru:/tmp/configs-backup.tar.gz .
```

### Backup данных команд

```bash
# Для каждой команды
for team in 01 02 03; do
  ssh -F ~/.ssh/ai-camp/ssh-config team${team} \
    "tar czf ~/team-backup.tar.gz ~/workspace"
  scp -F ~/.ssh/ai-camp/ssh-config \
    team${team}:~/team-backup.tar.gz \
    ./team-${team}-backup-$(date +%Y%m%d).tar.gz
done
```

### Восстановление

```bash
# Восстановить secrets
tar xzf ai-camp-backup-YYYYMMDD.tar.gz

# Восстановить Terraform state (если необходимо)
cp terraform.tfstate.backup environments/dev/terraform.tfstate

# Применить конфигурацию
cd environments/dev
terraform apply
```

---

## Полезные команды

### Terraform

```bash
# Посмотреть текущее состояние
terraform show

# Получить outputs
terraform output

# Посмотреть state для ресурса
terraform state show module.edge.yandex_compute_instance.edge

# Обновить state (если ресурсы изменились вручную)
terraform refresh
```

### Yandex Cloud

```bash
# Список VM
yc compute instance list

# Информация о VM
yc compute instance get <instance-id>

# Список сетей
yc vpc network list

# Список security groups
yc vpc security-group list
```

### Диагностика

```bash
# Проверить connectivity между edge и team VM
ssh jump@bastion.camp.aitalenthub.ru "ping -c 3 10.20.0.8"

# Проверить NAT работает
ssh -F ~/.ssh/ai-camp/ssh-config team01 "curl -s ifconfig.co"

# Проверить TPROXY активность
ssh jump@bastion.camp.aitalenthub.ru \
  "sudo iptables -t mangle -L XRAY -n -v | grep TPROXY"
```

---

## Удаление инфраструктуры

⚠️ **Внимание:** Это удалит **ВСЕ** ресурсы включая данные на VM!

### Полное удаление

```bash
cd environments/dev

# Backup перед удалением
terraform output -json > outputs-backup.json

# Удалить все ресурсы
terraform destroy
```

### Выборочное удаление

```bash
# Удалить конкретную team VM
terraform destroy -target=module.team_vm[\"03\"]

# Удалить credentials команды
rm -rf ../../secrets/team-03/
```

---

## Troubleshooting

Для решения проблем см. [troubleshooting.md](troubleshooting.md).

**Быстрые проверки:**

```bash
# Terraform не может подключиться к Yandex Cloud
echo $YC_SERVICE_ACCOUNT_KEY_FILE
cat $YC_SERVICE_ACCOUNT_KEY_FILE | jq .

# State locked
terraform force-unlock <lock-id>

# Модуль не найден
terraform init -upgrade
```

---

## См. также

- [architecture.md](architecture.md) - архитектура инфраструктуры
- [xray-configuration.md](xray-configuration.md) - конфигурация Xray
- [modules.md](modules.md) - документация Terraform модулей
- [troubleshooting.md](troubleshooting.md) - решение проблем
- [development.md](development.md) - для разработчиков
