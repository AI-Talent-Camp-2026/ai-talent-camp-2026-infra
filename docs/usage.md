# Руководство пользователя AI Camp Infrastructure

## Содержание

1. [Подключение по SSH](#подключение-по-ssh)
2. [Настройка веб-сервера](#настройка-веб-сервера)
3. [Получение SSL-сертификата](#получение-ssl-сертификата)
4. [Работа с Docker](#работа-с-docker)
5. [Проверка NAT](#проверка-nat)
6. [Traefik routing](#traefik-routing)
7. [Troubleshooting](#troubleshooting)

---

## Подключение по SSH

### Через jump-host (bastion)

Все team VMs находятся в приватной подсети и доступны только через jump-host.

```bash
# Формат команды
ssh -J jump@<bastion-ip> <team-user>@<team-private-ip>

# Пример для team01
ssh -J jump@bastion.camp.aitalenthub.ru team01@10.0.2.10
```

### Настройка SSH config

Добавьте в `~/.ssh/config`:

```
Host bastion
    HostName bastion.camp.aitalenthub.ru
    User jump
    IdentityFile ~/.ssh/your-key

Host team01
    HostName 10.0.2.10
    User team01
    ProxyJump bastion
    IdentityFile ~/.ssh/team01-key
```

После этого подключение:

```bash
ssh team01
```

### Копирование файлов

```bash
# Через scp с jump-host
scp -J jump@bastion.camp.aitalenthub.ru file.txt team01@10.0.2.10:~/

# Или с настроенным SSH config
scp file.txt team01:~/
```

---

## Настройка веб-сервера

### Структура по умолчанию

- Web root: `/var/www/html`
- Конфиг nginx: `/etc/nginx/sites-available/default`
- Домен: `team<XX>.camp.aitalenthub.ru`

### Размещение статического сайта

```bash
# Перейти на VM команды
ssh team01

# Разместить файлы
cd /var/www/html
echo "<h1>Hello from Team 01!</h1>" > index.html

# Проверить nginx
sudo systemctl status nginx
```

### Настройка приложения на другом порту

Если ваше приложение работает на порту 3000:

```bash
sudo nano /etc/nginx/sites-available/default
```

```nginx
server {
    listen 80;
    server_name team01.camp.aitalenthub.ru;

    location / {
        proxy_pass http://127.0.0.1:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
```

```bash
sudo nginx -t
sudo systemctl reload nginx
```

---

## Получение SSL-сертификата

### Через certbot (HTTP-01 challenge)

```bash
# Установить certbot (уже установлен)
sudo certbot --nginx -d team01.camp.aitalenthub.ru

# Следовать инструкциям
# Certbot автоматически настроит nginx
```

### Автоматическое обновление

```bash
# Проверить таймер
sudo systemctl status certbot.timer

# Тест обновления
sudo certbot renew --dry-run
```

---

## Работа с Docker

### Базовые команды

```bash
# Проверить Docker
docker --version
docker ps

# Запустить контейнер
docker run -d -p 8080:80 --name myapp nginx

# Просмотр логов
docker logs myapp

# Остановить и удалить
docker stop myapp
docker rm myapp
```

### Docker Compose

```bash
# Создать docker-compose.yml
cat > docker-compose.yml << 'EOF'
version: '3.8'
services:
  app:
    image: nginx
    ports:
      - "8080:80"
    volumes:
      - ./html:/usr/share/nginx/html
EOF

# Запустить
docker-compose up -d

# Остановить
docker-compose down
```

---

## Проверка NAT

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

---

## Traefik routing

### Как работает маршрутизация

```
Internet → Edge VM (Traefik) → Team VM
                  │
                  ├─ team01.camp.aitalenthub.ru → Team01 VM
                  ├─ team02.camp.aitalenthub.ru → Team02 VM
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

1. Применить terraform
2. Обновить динамическую конфигурацию Traefik
3. Скопировать `secrets/traefik-dynamic.yml` на edge VM:

```bash
# На локальной машине
scp secrets/traefik-dynamic.yml jump@bastion:/opt/traefik/dynamic/teams.yml
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
sudo iptables -t nat -L -n -v
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
```

3. Проверить AllowTcpForwarding на edge:
```bash
grep AllowTcpForwarding /etc/ssh/sshd_config.d/*
```

### Сайт недоступен извне

1. Проверить nginx:
```bash
sudo systemctl status nginx
sudo nginx -t
```

2. Проверить порты:
```bash
sudo ss -tlnp | grep -E ':(80|443)'
```

3. Проверить Traefik на edge:
```bash
# На edge VM
docker logs traefik
```

### Certbot не может получить сертификат

1. Проверить DNS:
```bash
dig team01.camp.aitalenthub.ru
```

2. Проверить доступность порта 80:
```bash
# С внешней машины
curl -v http://team01.camp.aitalenthub.ru/.well-known/acme-challenge/test
```

3. Проверить Traefik routing

### Docker не запускается

```bash
# Проверить статус
sudo systemctl status docker

# Перезапустить
sudo systemctl restart docker

# Проверить логи
sudo journalctl -u docker -f
```

---

## Полезные команды

```bash
# Системная информация
htop
df -h
free -m

# Сеть
ip addr
ss -tlnp
curl ifconfig.co

# Docker
docker ps -a
docker system df
docker system prune

# Логи
sudo journalctl -f
sudo tail -f /var/log/nginx/error.log
```
