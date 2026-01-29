# Руководство администратора

> **Последнее обновление:** 2026-01-29  
> **Связанные документы:** [architecture.md](architecture.md), [xray-configuration.md](xray-configuration.md), [modules.md](modules.md)

## Обзор

Это руководство для администраторов, управляющих инфраструктурой AI Talent Camp через Terraform.

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
  --output secrets/key.json
```

---

## Развертывание инфраструктуры

### 1. Клонирование репозитория

```bash
git clone https://github.com/AI-Talent-Camp-2026/ai-talent-camp-2026-infra.git
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

### Добавление кастомных доменов

Когда команда запрашивает использование собственного домена (например, `app.mydomain.com`), нужно добавить его в Traefik конфигурацию.

**Шаг 1: Получить запрос**

Команда должна создать issue с информацией:
- Номер команды (например, team01)
- Кастомный домен (например, app.mydomain.com)
- Тип: HTTP и/или HTTPS

**Шаг 2: Обновить динамическую конфигурацию**

Отредактируйте `secrets/traefik-dynamic.yml` на edge VM или пересоздайте через Terraform:

**Для HTTPS (TLS Passthrough):**
```yaml
tcp:
  routers:
    team01-router:
      entryPoints:
        - websecure
      # Добавить кастомный домен через ||
      rule: "HostSNI(`team01.camp.aitalenthub.com`) || HostSNI(`app.mydomain.com`)"
      service: team01-service
      tls:
        passthrough: true
```

**Для HTTP:**
```yaml
http:
  routers:
    team01-http:
      entryPoints:
        - web
      # Добавить кастомный домен через ||
      rule: "Host(`team01.camp.aitalenthub.com`) || Host(`app.mydomain.com`)"
      service: team01-http-service
```

**Шаг 3: Применить изменения**

```bash
# SSH на edge VM
ssh jump@bastion.camp.aitalenthub.com

# Перезапустить Traefik (конфиг перечитается автоматически)
docker restart traefik

# Или просто подождать (~30 секунд), Traefik перечитает конфиг сам
```

**Шаг 4: Проверка**

```bash
# Проверить логи Traefik
docker logs traefik | grep -i "app.mydomain.com"

# Должно быть:
# Configuration loaded successfully with new router
```

**Шаг 5: Уведомить команду**

Сообщите команде, что домен добавлен. Команда должна:
1. Настроить DNS (CNAME или A-запись)
2. Обновить Nginx на своей VM
3. Получить SSL сертификат

**Альтернативный способ (через Terraform):**

Если требуется постоянное решение, можно добавить поддержку кастомных доменов в переменные Terraform:

```hcl
# В terraform.tfvars
teams = {
  "01" = { 
    user = "team01"
    public_keys = []
    custom_domains = ["app.mydomain.com", "www.mydomain.com"]
  }
}
```

Затем обновить `templates/traefik/dynamic.yml.tpl` для использования этих доменов.

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

## Управление прозрачным проксированием

### Проверка NAT и TPROXY

#### Проверка исходящего трафика

```bash
# Проверить внешний IP (должен быть IP edge VM)
curl ifconfig.co

# Проверить доступ к интернету
curl -I https://google.com

# Проверить DNS
nslookup google.com
```

#### Проверка маршрутов

```bash
# Посмотреть таблицу маршрутизации
ip route

# Должен быть маршрут через edge VM:
# default via 10.0.1.x dev eth0
```

#### Проверка TPROXY (прозрачное проксирование)

TPROXY автоматически перехватывает трафик и маршрутизирует через VLESS proxy:

```bash
# Проверить, что AI API идут через proxy
curl -v https://api.openai.com/v1/models

# Проверить YouTube (тоже через proxy)
curl -I https://www.youtube.com

# Обычные сайты идут напрямую
curl -I https://google.com
```

**Важно:** Весь трафик из private subnet автоматически перехватывается на edge VM и маршрутизируется по правилам Xray.

#### Что идёт через VLESS proxy

- AI APIs (OpenAI, Anthropic, Google AI, Groq, Mistral и др.)
- Соцсети (YouTube, Instagram, TikTok, LinkedIn, Telegram, Notion)
- Остальной трафик идёт напрямую (direct)

### Управление Traefik routing

#### Как работает маршрутизация

```
Internet → Edge VM (Traefik) → Team VM
                  │
                  ├─ team01.camp.aitalenthub.ru → Team01 VM:80/443
                  ├─ team02.camp.aitalenthub.ru → Team02 VM:80/443
                  └─ ...
```

#### TLS Passthrough

Traefik настроен в режиме TLS passthrough - SSL-терминация происходит на team VM.

Это означает:
1. Traefik не расшифровывает трафик
2. Сертификат должен быть на team VM
3. Полная end-to-end шифрование

#### Добавление нового team

После добавления team в terraform.tfvars:

1. Применить terraform:
   ```bash
   terraform apply
   ```

2. Traefik динамическая конфигурация генерируется автоматически в `secrets/traefik-dynamic.yml`

3. Скопировать на edge VM (если нужно обновить вручную):
   ```bash
   scp -F ~/.ssh/ai-camp/ssh-config secrets/traefik-dynamic.yml jump@bastion:/opt/traefik/dynamic/teams.yml
   ```

   Обычно это не требуется - конфигурация обновляется автоматически при `terraform apply`.

### Управление конфигурацией Xray

#### Как работает Xray

Xray запущен на edge VM как systemd сервис и обеспечивает прозрачное проксирование (TPROXY):
- Перехватывает TCP/UDP трафик из private subnet
- Маршрутизирует по правилам: AI APIs и соцсети через VLESS proxy, остальное напрямую
- Конфигурация: `/opt/xray/config.json`

#### Изменение конфигурации Xray

##### Вариант 1: Через Terraform (рекомендуется)

Самый удобный способ — редактировать JSON конфиг и применять через Terraform.

**Первый запуск:**

1. После первого `terraform apply` создастся файл `secrets/xray-config.json`

2. Отредактируйте его напрямую (весь JSON целиком):
   ```bash
   nano secrets/xray-config.json
   ```

   Или используйте пример:
   ```bash
   cp templates/xray/config.example.json secrets/xray-config.json
   # Отредактируйте VLESS параметры
   ```

3. Примените изменения:
   ```bash
   cd environments/dev
   terraform apply
   ```

   Terraform автоматически:
   - Загрузит `secrets/xray-config.json` на edge VM
   - Перезапустит Xray сервис

**Последующие изменения:**

Просто отредактируйте `secrets/xray-config.json` и запустите `terraform apply`.

Можно менять:
- VLESS параметры (server, uuid, public_key и т.д.)
- Routing правила (добавлять/удалять домены)
- DNS настройки
- Логирование

**Важно:** Убедитесь что `jump_private_key_path` указывает на правильный SSH ключ:
```hcl
# В terraform.tfvars (раскомментировать если нужен другой путь)
jump_private_key_path = "~/.ssh/id_ed25519"
```

##### Вариант 2: Редактирование напрямую на edge VM

Для быстрых изменений без Terraform:

```bash
# Подключиться к edge VM
ssh jump@<edge-ip>

# Отредактировать конфигурацию
sudo nano /opt/xray/config.json

# Перезапустить Xray
sudo systemctl restart xray

# Проверить статус
sudo systemctl status xray
sudo journalctl -u xray --no-pager -n 20
```

**Внимание:** Изменения, сделанные напрямую на VM, будут перезаписаны при следующем `terraform apply`.

##### Вариант 3: Через локальный файл и scp

1. После `terraform apply` конфиг сохраняется в `secrets/xray-config.json`

2. Можно отредактировать его и загрузить вручную:
   ```bash
   scp secrets/xray-config.json jump@<edge-ip>:/tmp/
   ssh jump@<edge-ip> "sudo mv /tmp/xray-config.json /opt/xray/config.json && sudo systemctl restart xray"
   ```

#### Изменение routing правил

Routing правила находятся в секции `routing.rules` конфигурации Xray.

##### Добавить домен через proxy

```json
{
  "type": "field",
  "domain": [
    "geosite:category-ai-!cn",
    "geosite:youtube",
    "domain:example.com",
    "full:api.example.com"
  ],
  "outboundTag": "proxy"
}
```

##### Добавить домен напрямую (bypass proxy)

```json
{
  "type": "field",
  "domain": ["domain:mysite.ru"],
  "outboundTag": "direct"
}
```

##### Блокировать домен

```json
{
  "type": "field",
  "domain": ["domain:blocked.com"],
  "outboundTag": "block"
}
```

#### Доступные geosite категории

[https://github.com/v2fly/domain-list-community/tree/master/data](https://github.com/v2fly/domain-list-community/tree/master/data)

#### Пример: Добавить GitHub через proxy

Отредактируйте `/opt/xray/config.json` на edge VM:

```json
{
  "type": "field",
  "domain": [
    "geosite:category-ai-!cn",
    "geosite:notion",
    "geosite:youtube",
    "geosite:instagram",
    "geosite:tiktok",
    "geosite:linkedin",
    "geosite:telegram",
    "geosite:github"
  ],
  "outboundTag": "proxy"
}
```

Затем перезапустите Xray:
```bash
sudo systemctl restart xray
```

#### Изменение VLESS сервера

Если нужно сменить VLESS сервер:

1. Отредактировать `secrets/xray-config.json`, найти секцию `outbounds` с `"tag": "proxy"`:
   ```json
   {
     "tag": "proxy",
     "protocol": "vless",
     "settings": {
       "vnext": [{
         "address": "new-server.example.com",
         "port": 443,
         "users": [{
           "id": "your-new-uuid",
           "flow": "xtls-rprx-vision",
           "encryption": "none"
         }]
       }]
     },
     "streamSettings": {
       "network": "tcp",
       "security": "reality",
       "realitySettings": {
         "fingerprint": "chrome",
         "serverName": "www.microsoft.com",
         "publicKey": "new-public-key",
         "shortId": "new-short-id",
         "spiderX": ""
       }
     }
   }
   ```

2. Также обновить IP в routing правилах (секция `routing.rules`), найти правило с комментарием `"_comment": "Exclude VLESS server IP"`:
   ```json
   {
     "type": "field",
     "ip": ["1.2.3.4"],
     "outboundTag": "direct"
   }
   ```

3. Применить изменения (**без пересоздания edge VM**):
   ```bash
   cd environments/dev
   terraform apply
   ```

   Terraform автоматически обновит конфиг и перезапустит Xray.

4. **Дополнительно:** если изменился IP VLESS сервера, нужно обновить iptables правило:
   ```bash
   ssh jump@<edge-ip>
   # Удалить старое правило
   sudo iptables -t mangle -D XRAY -d <old-vless-ip> -j RETURN
   # Добавить новое
   sudo iptables -t mangle -I XRAY 5 -d <new-vless-ip> -j RETURN
   # Сохранить
   sudo netfilter-persistent save
   ```

#### Отключение TPROXY (только NAT)

Если нужно временно отключить прозрачное проксирование:

```bash
# На edge VM
sudo iptables -t mangle -D PREROUTING -s 10.20.0.0/24 -j XRAY
sudo systemctl stop xray
```

Трафик будет идти напрямую через NAT (MASQUERADE).

Для включения обратно:
```bash
sudo systemctl start xray
sudo iptables -t mangle -A PREROUTING -s 10.20.0.0/24 -j XRAY
```

#### Диагностика Xray

```bash
# Проверить статус Xray
sudo systemctl status xray

# Смотреть логи в реальном времени
sudo journalctl -u xray -f

# Проверить access log (какой трафик обрабатывается)
sudo tail -f /var/log/xray/access.log

# Проверить error log
sudo cat /var/log/xray/error.log

# Проверить конфигурацию (валидность JSON)
/usr/local/bin/xray run -test -config /opt/xray/config.json
```

### Диагностика инфраструктуры

#### VM не имеет доступа в интернет

1. Проверить маршрут:
   ```bash
   ip route | grep default
   ```

2. Проверить NAT на edge:
   ```bash
   # На edge VM
   sudo iptables -t nat -L -n -v | grep MASQUERADE
   ```

3. Проверить security group

#### Не работает SSH через jump-host

1. Проверить доступ к bastion:
   ```bash
   ssh -v jump@bastion.camp.aitalenthub.ru
   ```

2. Проверить ключи:
   ```bash
   ssh-add -l
   ls -la ~/.ssh/ai-camp/
   ```

3. Проверить AllowTcpForwarding на edge:
   ```bash
   # На edge VM
   grep AllowTcpForwarding /etc/ssh/sshd_config.d/*
   ```

#### TPROXY не работает

1. Проверить Xray сервис запущен:
   ```bash
   # На edge VM
   sudo systemctl status xray
   sudo journalctl -u xray -f
   ```

2. Проверить iptables правила:
   ```bash
   # На edge VM
   sudo iptables -t mangle -L PREROUTING -n -v
   sudo iptables -t mangle -L XRAY -n -v
   ```

3. Проверить policy routing:
   ```bash
   # На edge VM
   ip rule show
   ip route show table 100
   ```

4. Проверить, что VLESS server IP исключён:
   ```bash
   # На edge VM
   sudo iptables -t mangle -L XRAY -n -v | grep <vless-server-ip>
   ```

5. Проверить логи Xray:
   ```bash
   # На edge VM
   cat /var/log/xray/error.log
   cat /var/log/xray/access.log
   ```

---

## См. также

- [architecture.md](architecture.md) - архитектура инфраструктуры
- [xray-configuration.md](xray-configuration.md) - конфигурация Xray
- [modules.md](modules.md) - документация Terraform модулей
- [troubleshooting.md](troubleshooting.md) - решение проблем
- [development.md](development.md) - для разработчиков
