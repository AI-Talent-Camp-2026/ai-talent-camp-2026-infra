# Руководство для команд AI Talent Camp

> **Последнее обновление:** 2026-01-29  
> **Для команд участников**  
> **Связанные документы:** [quickstart.md](quickstart.md), [troubleshooting.md](troubleshooting.md)

## Введение

Это полное руководство для команд участников AI Talent Camp. Вы получаете выделенную виртуальную машину (VM) в облаке с полным контролем и root доступом.

**Что у вас есть:**
- Виртуальная машина Ubuntu 22.04 LTS
- 4 vCPU, 8GB RAM, 65GB SSD
- Полный sudo доступ
- Доступ в интернет (включая AI API)
- Доменное имя `teamXX.camp.aitalenthub.ru`
- SSH доступ через центральную точку входа

**Что вам нужно сделать:**
- Установить необходимое ПО (Docker, Nginx, и т.д.)
- Настроить reverse proxy
- Получить SSL сертификаты
- Развернуть ваше приложение
- Настроить автоматический деплой

---

## Содержание

1. [Подключение к VM](#подключение-к-vm)
2. [Настройка окружения](#настройка-окружения)
3. [Работа с доменами](#работа-с-доменами)
4. [Развертывание приложений](#развертывание-приложений)
5. [CI/CD и автодеплой](#cicd-и-автодеплой)
6. [Базы данных](#базы-данных)
7. [Мониторинг и логи](#мониторинг-и-логи)
8. [Troubleshooting](#troubleshooting)

---

## Подключение к VM

### Через терминал (SSH)

Вы получите папку `team-XX` с SSH ключами.

**Шаг 1: Копирование ключей**

```bash
# Скопировать папку с ключами
cp -r team-01 ~/.ssh/ai-camp

# Установить правильные права доступа
chmod 700 ~/.ssh/ai-camp
chmod 600 ~/.ssh/ai-camp/*-key
chmod 644 ~/.ssh/ai-camp/*.pub
chmod 644 ~/.ssh/ai-camp/ssh-config
```

**Шаг 2: Подключение**

```bash
# Использовать готовый конфиг
ssh -F ~/.ssh/ai-camp/ssh-config team01

# Или добавить в ваш ~/.ssh/config
cat ~/.ssh/ai-camp/ssh-config >> ~/.ssh/config
ssh team01
```

**Структура ключей:**

| Файл | Назначение |
|------|------------|
| `teamXX-jump-key` | Ключ для подключения (часть 1) |
| `teamXX-key` | Ключ для подключения (часть 2) |
| `teamXX-deploy-key` | Ключ для CI/CD (GitHub Actions) |
| `ssh-config` | Готовый SSH конфиг |

### Через IDE (VSCode/Cursor)

Работа через IDE удобнее - вы редактируете файлы как локальные.

**VSCode:**

1. Установите расширение **"Remote - SSH"**
2. Нажмите `Cmd/Ctrl+Shift+P` → `Remote-SSH: Connect to Host...`
3. Выберите `Configure SSH Hosts...` → `~/.ssh/config`
4. Добавьте содержимое из `~/.ssh/ai-camp/ssh-config`
5. Подключитесь к `team01`

**Cursor:**

Cursor построен на VSCode и использует те же расширения - следуйте инструкции для VSCode.

Подробная инструкция: [quickstart.md - Подключение через IDE](quickstart.md#вариант-c-подключение-через-vscodecursor)

### Копирование файлов

```bash
# Через scp
scp -F ~/.ssh/ai-camp/ssh-config file.txt team01:~/workspace/

# Загрузить файл с VM
scp -F ~/.ssh/ai-camp/ssh-config team01:~/workspace/file.txt ./
```

---

## Настройка окружения

### Обновление системы

Первым делом обновите пакеты:

```bash
sudo apt update
sudo apt upgrade -y
```

### Установка Docker и Docker Compose

Docker - рекомендуемый способ развертывания приложений.

```bash
# Добавить gpg ключи для установки докера через apt
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg
echo   "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Установить Docker и docker-compose
sudo apt update
sudo apt install -y docker.io docker-compose-plugin

# Запустить и добавить в автозагрузку
sudo systemctl enable docker
sudo systemctl start docker

# Добавить пользователя в группу docker (чтобы не использовать sudo)
sudo usermod -aG docker $USER

# Применить группу (нужно перезайти или использовать newgrp)
newgrp docker

# Проверить установку
docker --version
docker compose version
```

### Установка Nginx (reverse proxy)

Nginx будет принимать HTTPS трафик и проксировать на ваше приложение.

```bash
# Установить Nginx
sudo apt install -y nginx

# Запустить и добавить в автозагрузку
sudo systemctl enable nginx
sudo systemctl start nginx

# Проверить статус
sudo systemctl status nginx
```

**Проверка:** Откройте `http://<ваш-домен>` - должна отображаться стандартная страница Nginx.

### Базовая конфигурация Nginx

Создайте конфигурацию для вашего приложения:

```bash
sudo nano /etc/nginx/sites-available/myapp
```

**Пример конфигурации (HTTP, пока без SSL):**

```nginx
server {
    listen 80;
    server_name team01.camp.aitalenthub.ru; # тут надо поменять на ваш домен

    location / {
        proxy_pass http://localhost:3000;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

**Активировать конфигурацию:**

```bash
# Создать символическую ссылку
sudo ln -s /etc/nginx/sites-available/myapp /etc/nginx/sites-enabled/

# Удалить дефолтную конфигурацию
sudo rm /etc/nginx/sites-enabled/default

# Проверить конфигурацию
sudo nginx -t

# Перезагрузить Nginx
sudo systemctl reload nginx
```

### Получение SSL сертификата

Let's Encrypt предоставляет бесплатные SSL сертификаты.

```bash
# Установить Certbot
sudo apt install -y certbot python3-certbot-nginx

# Получить сертификат. Не забудьте поменять домен на ваш
sudo certbot --nginx -d team01.camp.aitalenthub.ru

# Следуйте инструкциям:
# 1. Введите email
# 2. Согласитесь с ToS
# 3. Выберите "2" (Redirect HTTP to HTTPS)
```

**Certbot автоматически:**
- Получит сертификат
- Обновит конфигурацию Nginx для HTTPS
- Настроит автоматическое обновление сертификата

**Проверить автообновление:**

```bash
# Посмотреть таймер
sudo systemctl status certbot.timer

# Тестовый запуск обновления
sudo certbot renew --dry-run
```

---

## Работа с доменами

### Ваш стандартный домен

Вы получаете: **`teamXX.camp.aitalenthub.ru`**

Где `XX` - номер команды (01, 02, и т.д.)

### Переименование домена

Вы можете изменить часть `teamXX` на своё название:

**Шаги:**

1. Создайте [issue в репозитории](https://github.com/AI-Talent-Camp-2026/ai-talent-camp-2026-infra/issues/new)
2. Заголовок: `Запрос на изменение домена для teamXX`
3. Укажите:
   ```
   Текущий домен: team01.camp.aitalenthub.ru
   Желаемое имя: myteam (только латиница, цифры, дефис)
   Новый домен: myteam.camp.aitalenthub.ru
   ```
4. Администратор обновит конфигурацию (обычно 1 рабочий день)
5. После одобрения обновите настройки на вашей VM

**Требования к имени:**
- Длина: 3-20 символов
- Разрешены: латиница (a-z), цифры (0-9), дефис (-)
- Примеры: `myteam`, `cool-project`, `hack2026`

**После смены домена на вашей VM:**

```bash
# 1. Обновить конфигурацию Nginx
sudo nano /etc/nginx/sites-available/myapp
# Изменить server_name на новый домен

# 2. Получить новый SSL сертификат
sudo certbot --nginx -d myteam.camp.aitalenthub.ru

# 3. Перезагрузить Nginx
sudo systemctl reload nginx
```

### Использование собственного домена

Если у вас есть свой домен, вы можете использовать его для доступа к вашему приложению.

**Шаг 1: Создать запрос на добавление домена**

Для корректной маршрутизации кастомного домена через центральный reverse proxy (Traefik), создайте [issue в репозитории](https://github.com/AI-Talent-Camp-2026/ai-talent-camp-2026-infra/issues/new):

```
Заголовок: Добавление кастомного домена для teamXX
Описание:
  Команда: team01
  Кастомный домен: app.mydomain.com
  Тип: HTTP + HTTPS (TLS passthrough)
```

Администратор добавит ваш домен в конфигурацию Traefik (обычно 1 рабочий день).

**Шаг 2: Настройка DNS**

После одобрения запроса, зайдите в панель управления вашего DNS провайдера (Cloudflare, Namecheap, и т.д.):

**CNAME**
```
Тип: CNAME
Имя: app (или любое другое: www, api, и т.д.)
Значение: team01.camp.aitalenthub.ru
TTL: Auto или 300
```

**Пример:**
```
app.mydomain.com → team01.camp.aitalenthub.ru (CNAME)
```

**Шаг 3: Проверка DNS (может занять до 48 часов)**

```bash
# Проверить CNAME запись
dig app.mydomain.com

# Должно быть (для CNAME):
# app.mydomain.com. 300 IN CNAME team01.camp.aitalenthub.ru.
# team01.camp.aitalenthub.ru. 300 IN A <IP edge VM>

# Для A-записи:
# app.mydomain.com. 300 IN A <IP edge VM>
```

**Шаг 4: Настройка Nginx на вашей VM**

Добавьте ваш домен в конфигурацию:

```bash
sudo nano /etc/nginx/sites-available/myapp
```

Добавьте ваш домен в `server_name`:

```nginx
server {
    listen 80;
    server_name team01.camp.aitalenthub.ru app.mydomain.com;
    # ... остальная конфигурация
}
```

**Шаг 5: Получить SSL сертификат**

```bash
# Получить сертификат для вашего домена
sudo certbot --nginx -d app.mydomain.com

# Или для обоих доменов сразу
sudo certbot --nginx -d team01.camp.aitalenthub.ru -d app.mydomain.com
```

**Важно:** 
- ⚠️ Без добавления домена в конфигурацию Traefik (Шаг 1), ваш кастомный домен не будет работать
- ✅ Стандартный домен `teamXX.camp.aitalenthub.ru` работает сразу без дополнительных настроек

---

## Развертывание приложений

### Docker Compose

Docker Compose позволяет описать всё приложение в одном файле.

#### Пример: Python FastAPI

**docker-compose.yml:**

```yaml
version: '3.8'

services:
  web:
    build: .
    container_name: fastapi-app
    restart: always
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://user:pass@db:5432/mydb
    depends_on:
      - db
    command: uvicorn main:app --host 0.0.0.0 --port 8000

  db:
    image: postgres:15-alpine
    container_name: postgres
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: mydb
    volumes:
      - postgres-data:/var/lib/postgresql/data

volumes:
  postgres-data:
```

**Dockerfile:**

```dockerfile
FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

## CI/CD и автодеплой

### GitHub Actions

Подключение к VM из CI/CD идёт **через jump-сервер (bastion)** — так же, как при ручном SSH. Нужны оба ключа: для bastion и для VM.

#### Шаг 1: Добавить ключи в GitHub Secrets

Подключение к VM двухшаговое: сначала bastion, затем VM. В секреты репозитория нужно добавить **два** ключа.

**1. Ключ для jump-сервера (bastion):**

```bash
# Скопировать приватный ключ для bastion
cat ~/.ssh/ai-camp/team01-jump-key
```

В GitHub: Settings → Secrets and variables → Actions → New repository secret  
- Name: `DEPLOY_JUMP_KEY`  
- Value: содержимое файла `team01-jump-key`

**2. Ключ для доступа к VM:**

```bash
# Скопировать приватный ключ для VM (тот же, что для ручного SSH)
cat ~/.ssh/ai-camp/team01-deploy-key
```

В GitHub: New repository secret  
- Name: `DEPLOY_KEY`  
- Value: содержимое файла `team01-deploy-key`

**Примечание:** Приватный IP вашей VM и hostname bastion возьмите из выданного вам `ssh-config` (поля `HostName` для bastion и для team01).

#### Шаг 2: Создать workflow с ProxyJump

В workflow подключаемся к VM так же, как вручную: через jump-сервер (bastion). Используется `ProxyCommand`: сначала SSH на bastion с jump-ключом, затем на VM с ключом VM для CI/CD.

Значения `BASTION_HOST`, `TEAM_VM_IP`, `TEAM_USER` берите из выданного файла `ssh-config` (в папке `team-XX/`): там указаны `HostName` для bastion и для вашей VM (приватный IP), а также имя пользователя.

`.github/workflows/deploy.yml`:

```yaml
name: Deploy to Production

on:
  push:
    branches: [ main ]

env:
  BASTION_HOST: bastion.camp.aitalenthub.ru
  TEAM_VM_IP: 10.20.0.5
  TEAM_USER: team01

jobs:
  deploy:
    runs-on: ubuntu-latest
    
    steps:
    - name: Checkout code
      uses: actions/checkout@v4
    
    - name: Setup SSH and known hosts
      run: |
        mkdir -p ~/.ssh
        chmod 700 ~/.ssh
        ssh-keyscan -H ${{ env.BASTION_HOST }} >> ~/.ssh/known_hosts
    
    - name: Deploy with Docker Compose
      env:
        JUMP_KEY: ${{ secrets.DEPLOY_JUMP_KEY }}
        VM_KEY: ${{ secrets.DEPLOY_KEY }}
      run: |
        echo "$JUMP_KEY" > ~/.ssh/jump_key
        echo "$VM_KEY" > ~/.ssh/vm_key
        chmod 600 ~/.ssh/jump_key ~/.ssh/vm_key
        ssh -o ProxyCommand="ssh -i ~/.ssh/jump_key -W %h:%p jump@${{ env.BASTION_HOST }}" \
            -i ~/.ssh/vm_key ${{ env.TEAM_USER }}@${{ env.TEAM_VM_IP }} << 'REMOTE'
          cd ~/workspace/myapp
          git pull origin main
          docker compose down
          docker compose build
          docker compose up -d
        REMOTE
```

**Важно:** Значения `BASTION_HOST`, `TEAM_VM_IP`, `TEAM_USER` возьмите из выданного вам файла `ssh-config` в папке `team-XX/`.

---

## Базы данных

### PostgreSQL в Docker

**docker-compose.yml:**

```yaml
version: '3.8'

services:
  postgres:
    image: postgres:18-alpine
    container_name: postgres
    restart: always
    environment:
      POSTGRES_USER: myuser
      POSTGRES_PASSWORD: mypassword
      POSTGRES_DB: mydb
    ports:
      - "5432:5432"
    volumes:
      - postgres-data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql

volumes:
  postgres-data:
```

**Подключение:**

```bash
# Из приложения на той же VM
DATABASE_URL=postgresql://myuser:mypassword@localhost:5432/mydb

# Подключиться через psql
docker exec -it postgres psql -U myuser -d mydb
```

### MongoDB в Docker

```yaml
services:
  mongodb:
    image: mongo:7
    container_name: mongodb
    restart: always
    environment:
      MONGO_INITDB_ROOT_USERNAME: admin
      MONGO_INITDB_ROOT_PASSWORD: password
    ports:
      - "27017:27017"
    volumes:
      - mongodb-data:/data/db

volumes:
  mongodb-data:
```

**Подключение:**

```bash
# Connection string
mongodb://admin:password@localhost:27017

# Подключиться через mongosh
docker exec -it mongodb mongosh -u admin -p password
```

### Redis в Docker

```yaml
services:
  redis:
    image: redis:7-alpine
    container_name: redis
    restart: always
    ports:
      - "6379:6379"
    volumes:
      - redis-data:/data

volumes:
  redis-data:
```

**Подключение:**

```bash
# Из приложения
REDIS_URL=redis://localhost:6379

# Подключиться через redis-cli
docker exec -it redis redis-cli
```

---

## Мониторинг и логи

### Системные логи

```bash
# Все системные логи
sudo journalctl -f

# Логи конкретного сервиса
sudo journalctl -u myapp -f

# Логи за последний час
sudo journalctl --since "1 hour ago"

# Логи Nginx
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### Docker логи

```bash
# Логи контейнера
docker logs -f myapp

# Логи всех контейнеров в docker-compose
docker compose logs -f

# Логи конкретного сервиса
docker compose logs -f app
```

### Мониторинг ресурсов

```bash
# CPU и память
htop
# или
btop

# Использование диска
df -h

# Использование диска по папкам
du -sh ~/workspace/*

# Docker использование диска
docker system df

# Очистка Docker (осторожно!)
docker system prune -a
```

---

## Troubleshooting

### Не могу подключиться по SSH

**Проверить права на ключи:**

```bash
ls -la ~/.ssh/ai-camp/
# Должно быть:
# drwx------ (700) для директории
# -rw------- (600) для приватных ключей
# -rw-r--r-- (644) для публичных ключей

# Исправить если нужно
chmod 700 ~/.ssh/ai-camp
chmod 600 ~/.ssh/ai-camp/*-key
chmod 644 ~/.ssh/ai-camp/*.pub
```

**Проверить подключение:**

```bash
# С verbose выводом
ssh -vvv -F ~/.ssh/ai-camp/ssh-config team01
```

**Проверить доступность центральной точки входа:**

```bash
ping bastion.camp.aitalenthub.ru
```

### Приложение не доступно извне

**1. Проверить что приложение запущено:**

```bash
# Посмотреть открытые порты
sudo ss -tlnp | grep -E ':(80|443|3000|5000|8000)'

# Должны видеть ваше приложение
```

**2. Проверить Nginx:**

```bash
# Статус
sudo systemctl status nginx

# Проверить конфигурацию
sudo nginx -t

# Логи ошибок
sudo tail -f /var/log/nginx/error.log
```

**3. Проверить файрвол (если настраивали):**

```bash
# Посмотреть правила
sudo ufw status

# Разрешить HTTP и HTTPS
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
```

**4. Проверить DNS:**

```bash
# Проверить что домен указывает на правильный IP
dig team01.camp.aitalenthub.ru
```

### Ошибка "Permission denied" в Docker

```bash
# Добавить пользователя в группу docker
sudo usermod -aG docker $USER

# Применить изменения (нужно перезайти)
newgrp docker

# Или выйти и зайти снова
exit
ssh -F ~/.ssh/ai-camp/ssh-config team01
```

### Нет места на диске

```bash
# Посмотреть использование
df -h

# Найти большие файлы
du -sh ~/workspace/* | sort -h

# Очистить Docker
docker system prune -a --volumes

# Очистить логи
sudo journalctl --vacuum-time=7d
```

### SSL сертификат не обновляется

```bash
# Проверить таймер certbot
sudo systemctl status certbot.timer

# Запустить обновление вручную
sudo certbot renew --dry-run

# Если есть ошибки, посмотреть логи
sudo tail -f /var/log/letsencrypt/letsencrypt.log
```

### Docker контейнер постоянно перезапускается

```bash
# Посмотреть логи
docker logs myapp

# Посмотреть последние 100 строк
docker logs --tail 100 myapp

# Запустить контейнер в интерактивном режиме для отладки
docker run -it myapp /bin/sh
```

### Высокая нагрузка CPU/памяти

```bash
# Посмотреть процессы
htop

# Найти процесс с высокой нагрузкой
top

# или использовать
btop

# Посмотреть использование ресурсов Docker контейнерами
docker stats

# Ограничить ресурсы контейнера в docker-compose.yml:
services:
  app:
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
```

---

## Полезные команды

### Системные

```bash
# Информация о системе
uname -a
lsb_release -a

# Использование ресурсов
btop
free -m
df -h

# Процессы
ps aux | grep myapp
pgrep -a myapp
```

### Docker

```bash
# Список контейнеров
docker ps -a

# Логи
docker logs -f container_name

# Войти в контейнер
docker exec -it container_name /bin/bash

# Статистика ресурсов
docker stats

# Очистка
docker system prune -a
```

### Nginx

```bash
# Проверить конфигурацию
sudo nginx -t

# Перезагрузить
sudo systemctl reload nginx

# Логи
sudo tail -f /var/log/nginx/access.log
sudo tail -f /var/log/nginx/error.log
```

### Git

```bash
# Клонировать репозиторий
git clone https://github.com/user/repo.git

# Обновить
git pull origin main

# Посмотреть статус
git status

# История коммитов
git log --oneline
```

---

## См. также

- [quickstart.md](quickstart.md) - быстрый старт для новичков
- [troubleshooting.md](troubleshooting.md) - подробное решение проблем
- [README.md](../README.md) - общая информация о проекте

---

**Нужна помощь?** Создайте [issue в репозитории](https://github.com/AI-Talent-Camp-2026/ai-talent-camp-2026-infra/issues/new).
