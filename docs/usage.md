# Руководство пользователя AI Camp Infrastructure

## Содержание

1. [Подключение по SSH](#подключение-по-ssh)
2. [Настройка окружения команды](#настройка-окружения-команды)
3. [Проверка NAT и TPROXY](#проверка-nat-и-tproxy)
4. [Traefik routing](#traefik-routing)
5. [Управление конфигурацией Xray (VPN/Proxy)](#управление-конфигурацией-xray-vpnproxy)
6. [Troubleshooting](#troubleshooting)

---

## Подключение по SSH

### Для команд (используя сгенерированные ключи)

Каждая команда получает папку `secrets/team-XX/` со всеми необходимыми ключами.

#### Шаг 1: Копирование ключей

```bash
# Скопировать папку в ~/.ssh/
cp -r secrets/team-01 ~/.ssh/ai-camp

# Установить правильные права доступа
chmod 700 ~/.ssh/ai-camp
chmod 600 ~/.ssh/ai-camp/*-key
chmod 644 ~/.ssh/ai-camp/*.pub
chmod 644 ~/.ssh/ai-camp/ssh-config
```

#### Шаг 2: Подключение к VM

```bash
# Использовать готовый SSH config
ssh -F ~/.ssh/ai-camp/ssh-config team01
```

SSH config уже настроен с:
- Правильными ключами для bastion и VM
- ProxyJump через bastion
- Отключенной проверкой host keys (для удобства)

#### Структура ключей

| Файл | Назначение |
|------|------------|
| `teamXX-jump-key` | Приватный ключ для подключения к bastion |
| `teamXX-key` | Приватный ключ для подключения к VM команды |
| `teamXX-deploy-key` | Приватный ключ для GitHub Actions / CI/CD |
| `ssh-config` | Готовый SSH конфиг |

### Для админа (через jump-host)

```bash
# Формат команды
ssh -J jump@<bastion-ip> <team-user>@<team-private-ip>

# Пример для team01
ssh -J jump@bastion.camp.aitalenthub.ru team01@10.0.2.10
```

### Настройка SSH config вручную (альтернатива)

Если хотите настроить SSH config самостоятельно, добавьте в `~/.ssh/config`:

```
Host bastion
    HostName bastion.camp.aitalenthub.ru
    User jump
    IdentityFile ~/.ssh/ai-camp/team01-jump-key
    IdentitiesOnly yes
    StrictHostKeyChecking no

Host team01
    HostName 10.0.2.10
    User team01
    ProxyJump bastion
    IdentityFile ~/.ssh/ai-camp/team01-key
    IdentitiesOnly yes
    StrictHostKeyChecking no
```

После этого подключение:

```bash
ssh team01
```

### Копирование файлов

```bash
# Через scp с готовым SSH config
scp -F ~/.ssh/ai-camp/ssh-config file.txt team01:~/

# Или через jump-host напрямую
scp -J jump@bastion.camp.aitalenthub.ru file.txt team01@10.0.2.10:~/
```

---

## Настройка окружения команды

### Базовая VM

Team VM создаётся с минимальной конфигурацией:
- Ubuntu 22.04 LTS
- Пользователь с sudo правами
- Рабочая директория `/home/<user>/workspace`

**Команды устанавливают всё необходимое сами:**
- Docker (если нужен)
- Nginx / веб-сервер (если нужен)
- Языки программирования и инструменты

### Установка Docker (пример)

```bash
# Подключиться к VM
ssh -F ~/.ssh/ai-camp/ssh-config team01

# Установить Docker
sudo apt update
sudo apt install -y docker.io docker-compose
sudo systemctl enable docker
sudo systemctl start docker

# Добавить пользователя в группу docker
sudo usermod -aG docker team01
# Выйти и зайти снова для применения группы
```

### Установка Nginx (пример)

```bash
sudo apt install -y nginx
sudo systemctl enable nginx
sudo systemctl start nginx
```

### Настройка приложения

#### Пример: Node.js приложение

```bash
# Установить Node.js
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt install -y nodejs

# Создать приложение
cd ~/workspace
npm init -y
npm install express

# Запустить на порту 3000
node app.js
```

#### Пример: Python приложение

```bash
# Установить Python и зависимости
sudo apt install -y python3 python3-pip python3-venv

# Создать виртуальное окружение
cd ~/workspace
python3 -m venv venv
source venv/bin/activate
pip install flask

# Запустить на порту 5000
flask run --host=0.0.0.0 --port=5000
```

### Получение SSL-сертификата

Если используете Nginx:

```bash
# Установить certbot
sudo apt install -y certbot python3-certbot-nginx

# Получить сертификат
sudo certbot --nginx -d team01.camp.aitalenthub.ru

# Автоматическое обновление уже настроено
```

---

## Проверка NAT и TPROXY

### Проверка исходящего трафика

```bash
# Проверить внешний IP (должен быть IP edge VM)
curl ifconfig.co

# Проверить доступ к интернету
curl -I https://google.com

# Проверить DNS
nslookup google.com
```

### Проверка маршрутов

```bash
# Посмотреть таблицу маршрутизации
ip route

# Должен быть маршрут через edge VM:
# default via 10.0.1.x dev eth0
```

### Проверка TPROXY (прозрачное проксирование)

TPROXY автоматически перехватывает трафик и маршрутизирует через VLESS proxy:

```bash
# Проверить, что AI API идут через proxy
curl -v https://api.openai.com/v1/models

# Проверить YouTube (тоже через proxy)
curl -I https://www.youtube.com

# Обычные сайты идут напрямую
curl -I https://google.com
```

**Важно:** Команды не настраивают ничего - всё работает прозрачно. Весь трафик из private subnet автоматически перехватывается на edge VM и маршрутизируется по правилам Xray.

### Что идёт через VLESS proxy

- AI APIs (OpenAI, Anthropic, Google AI, Groq, Mistral и др.)
- Соцсети (YouTube, Instagram, TikTok, LinkedIn, Telegram, Notion)
- Остальной трафик идёт напрямую (direct)

---

## Traefik routing

### Как работает маршрутизация

```
Internet → Edge VM (Traefik) → Team VM
                  │
                  ├─ team01.camp.aitalenthub.ru → Team01 VM:80/443
                  ├─ team02.camp.aitalenthub.ru → Team02 VM:80/443
                  └─ ...
```

### TLS Passthrough

Traefik настроен в режиме TLS passthrough - SSL-терминация происходит на team VM.

Это означает:
1. Traefik не расшифровывает трафик
2. Сертификат должен быть на team VM
3. Полная end-to-end шифрование

### Добавление нового team

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

---

## Управление конфигурацией Xray (VPN/Proxy)

### Как работает Xray

Xray запущен на edge VM как systemd сервис и обеспечивает прозрачное проксирование (TPROXY):
- Перехватывает TCP/UDP трафик из private subnet
- Маршрутизирует по правилам: AI APIs и соцсети через VLESS proxy, остальное напрямую
- Конфигурация: `/opt/xray/config.json`

### Изменение конфигурации Xray

#### Вариант 1: Через Terraform (рекомендуется)

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

#### Вариант 2: Редактирование напрямую на edge VM

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

#### Вариант 3: Через локальный файл и scp

1. После `terraform apply` конфиг сохраняется в `secrets/xray-config.json`

2. Можно отредактировать его и загрузить вручную:
   ```bash
   scp secrets/xray-config.json jump@<edge-ip>:/tmp/
   ssh jump@<edge-ip> "sudo mv /tmp/xray-config.json /opt/xray/config.json && sudo systemctl restart xray"
   ```

### Изменение routing правил

Routing правила находятся в секции `routing.rules` конфигурации Xray.

#### Добавить домен через proxy

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

#### Добавить домен напрямую (bypass proxy)

```json
{
  "type": "field",
  "domain": ["domain:mysite.ru"],
  "outboundTag": "direct"
}
```

#### Блокировать домен

```json
{
  "type": "field",
  "domain": ["domain:blocked.com"],
  "outboundTag": "block"
}
```

### Доступные geosite категории

- `geosite:category-ai-!cn` - AI сервисы (OpenAI, Anthropic, Google AI и др.)
- `geosite:youtube` - YouTube
- `geosite:instagram` - Instagram
- `geosite:tiktok` - TikTok
- `geosite:linkedin` - LinkedIn
- `geosite:telegram` - Telegram
- `geosite:notion` - Notion
- `geosite:github` - GitHub
- `geosite:google` - Google сервисы

### Пример: Добавить GitHub через proxy

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

### Изменение VLESS сервера

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

### Отключение TPROXY (только NAT)

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

### Диагностика

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

---

## Troubleshooting

### VM не имеет доступа в интернет

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

### Не работает SSH через jump-host

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

### TPROXY не работает

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

### Сайт недоступен извне

1. Проверить, что приложение запущено:
   ```bash
   # На team VM
   sudo ss -tlnp | grep -E ':(80|443|3000|5000)'
   ```

2. Проверить Traefik на edge:
   ```bash
   # На edge VM
   docker logs traefik
   ```

3. Проверить DNS:
   ```bash
   dig team01.camp.aitalenthub.ru
   ```

4. Проверить security groups

### Certbot не может получить сертификат

1. Проверить DNS:
   ```bash
   dig team01.camp.aitalenthub.ru
   ```

2. Проверить доступность порта 80 через Traefik:
   ```bash
   # С внешней машины
   curl -v http://team01.camp.aitalenthub.ru/.well-known/acme-challenge/test
   ```

3. Проверить, что Nginx слушает на порту 80:
   ```bash
   # На team VM
   sudo ss -tlnp | grep :80
   ```

### GitHub Actions / CI/CD

Для использования deploy key в GitHub Actions:

1. Скопировать публичный ключ:
   ```bash
   cat ~/.ssh/ai-camp/team01-deploy-key.pub
   ```

2. Добавить в GitHub repo:
   - Settings → Deploy keys → Add deploy key
   - Вставить публичный ключ
   - Выбрать "Allow write access" если нужно

3. Использовать в GitHub Actions:
   ```yaml
   - name: Setup SSH
     uses: webfactory/ssh-agent@v0.7.0
     with:
       ssh-private-key: ${{ secrets.DEPLOY_KEY }}

   - name: Deploy
     run: |
       ssh -F ~/.ssh/ai-camp/ssh-config team01 "cd ~/workspace && git pull"
   ```

---

## Полезные команды

```bash
# Системная информация
htop
df -h
free -m
uname -a

# Сеть
ip addr
ip route
ss -tlnp
curl ifconfig.co

# Docker (если установлен)
docker ps -a
docker system df
docker system prune

# Логи
sudo journalctl -f
sudo tail -f /var/log/syslog

# Проверка подключения
ping 8.8.8.8
curl -I https://google.com
```
