# Troubleshooting - Решение проблем

> **Последнее обновление:** 2026-01-29  
> **Связанные документы:** [user-guide.md](user-guide.md), [xray-configuration.md](xray-configuration.md)

## Обзор

Это руководство поможет решить типичные проблемы с инфраструктурой AI Talent Camp.

**Структура каждой проблемы:**
- **Симптомы** - что вы видите
- **Диагностика** - как проверить
- **Решение** - как исправить
- **Профилактика** - как избежать

---

## Содержание

- [SSH и подключение](#ssh-и-подключение)
- [Интернет и NAT](#интернет-и-nat)
- [TPROXY и Xray](#tproxy-и-xray)
- [Traefik и HTTP/HTTPS](#traefik-и-httphttps)
- [DNS](#dns)
- [Performance](#performance)

---

## SSH и подключение

### Проблема: SSH Connection Refused

**Симптомы:**
```
ssh: connect to host bastion.camp.aitalenthub.ru port 22: Connection refused
```

**Диагностика:**
```bash
# 1. Проверить доступность хоста
ping bastion.camp.aitalenthub.ru

# 2. Проверить порт 22
nc -zv bastion.camp.aitalenthub.ru 22

# 3. Проверить DNS
nslookup bastion.camp.aitalenthub.ru
```

**Решение:**
1. Если ping не работает - проверить DNS записи
2. Если порт 22 закрыт - проверить security group на edge VM
3. Если все работает, но SSH отказывает - проверить SSH service на edge VM:
   ```bash
   # На edge VM (через консоль Yandex Cloud)
   sudo systemctl status sshd
   sudo journalctl -u sshd -n 50
   ```

**Профилактика:**
- Не изменять SSH конфигурацию без backup
- Всегда тестировать SSH в новом окне перед закрытием существующей сессии

---

### Проблема: Permission Denied (publickey)

**Симптомы:**
```
Permission denied (publickey).
```

**Диагностика:**
```bash
# 1. Проверить наличие ключей
ls -la ~/.ssh/ai-camp/

# 2. Проверить права доступа
ls -la ~/.ssh/ai-camp/*-key

# 3. Попробовать с verbose
ssh -vvv -F ~/.ssh/ai-camp/ssh-config team01
```

**Решение:**
1. **Неправильные права доступа:**
   ```bash
   chmod 600 ~/.ssh/ai-camp/*-key
   chmod 644 ~/.ssh/ai-camp/*.pub
   ```

2. **Неправильный ключ:**
   ```bash
   # Проверить, какой ключ используется
   ssh -vvv -F ~/.ssh/ai-camp/ssh-config team01 2>&1 | grep "identity file"
   
   # Убедиться, что используется правильный ключ
   cat ~/.ssh/ai-camp/ssh-config | grep IdentityFile
   ```

3. **Ключ не добавлен на сервер:**
   - Обратиться к администратору для добавления публичного ключа

**Профилактика:**
- Использовать готовый `ssh-config` из папки команды
- Не модифицировать ключи вручную

---

### Проблема: ProxyJump не работает

**Симптомы:**
```
ssh: Could not resolve hostname 10.20.0.8: Name or service not known
```

**Диагностика:**
```bash
# 1. Проверить SSH config
cat ~/.ssh/ai-camp/ssh-config

# 2. Проверить подключение к bastion отдельно
ssh -F ~/.ssh/ai-camp/ssh-config -J jump@bastion.camp.aitalenthub.ru echo "OK"

# 3. Проверить AllowTcpForwarding
ssh jump@bastion.camp.aitalenthub.ru "grep AllowTcpForwarding /etc/ssh/sshd_config.d/*"
```

**Решение:**
1. **AllowTcpForwarding отключен:**
   ```bash
   # На edge VM
   sudo nano /etc/ssh/sshd_config.d/99-jump-host.conf
   # Добавить: AllowTcpForwarding yes
   sudo systemctl restart sshd
   ```

2. **Неправильный SSH config:**
   - Использовать готовый ssh-config из `secrets/team-XX/`

**Профилактика:**
- Не изменять SSH конфигурацию на bastion вручную

---

## Интернет и NAT

### Проблема: VM не имеет доступа в интернет

**Симптомы:**
```bash
curl google.com
# curl: (6) Could not resolve host: google.com
```

**Диагностика:**
```bash
# На team VM
# 1. Проверить default route
ip route | grep default

# 2. Проверить DNS
cat /etc/resolv.conf

# 3. Проверить доступность edge VM
ping 192.168.1.x  # IP edge VM

# На edge VM
# 4. Проверить NAT правила
sudo iptables -t nat -L -n -v | grep MASQUERADE

# 5. Проверить ip_forward
sysctl net.ipv4.ip_forward
```

**Решение:**
1. **Нет default route:**
   ```bash
   # Проверить route table в Terraform
   # Должен быть route: 0.0.0.0/0 -> edge private IP
   ```

2. **NAT не настроен:**
   ```bash
   # На edge VM
   sudo iptables -t nat -A POSTROUTING -s 10.20.0.0/24 -o eth0 -j MASQUERADE
   sudo netfilter-persistent save
   ```

3. **ip_forward отключен:**
   ```bash
   # На edge VM
   sudo sysctl -w net.ipv4.ip_forward=1
   echo "net.ipv4.ip_forward = 1" | sudo tee -a /etc/sysctl.conf
   ```

**Профилактика:**
- Не изменять networking на edge VM вручную
- Все изменения делать через Terraform

---

### Проблема: Медленный интернет

**Симптомы:**
- Загрузка файлов очень медленная
- High latency

**Диагностика:**
```bash
# 1. Проверить bandwidth
curl -o /dev/null http://speedtest.tele2.net/100MB.zip

# 2. Проверить latency
ping -c 10 8.8.8.8

# 3. Проверить загрузку CPU на edge VM
ssh jump@bastion.camp.aitalenthub.ru "htop"

# 4. Проверить network utilization
ssh jump@bastion.camp.aitalenthub.ru "ifstat -i eth0 1 5"
```

**Решение:**
1. **Edge VM перегружен:**
   - Увеличить cores/memory edge VM через Terraform
   
2. **Слишком много команд:**
   - Проверить количество активных team VMs
   - Рассмотреть upgrade edge VM

3. **Проблемы с proxy:**
   - Проверить latency к proxy серверу
   - Рассмотреть другой proxy сервер

**Профилактика:**
- Мониторить загрузку edge VM
- Масштабировать ресурсы проактивно

---

## TPROXY и Xray

### Проблема: TPROXY не работает

**Симптомы:**
- AI API недоступны (`curl api.openai.com` - timeout)
- Или наоборот, все сайты недоступны

**Диагностика:**
```bash
# На edge VM
# 1. Проверить статус Xray
sudo systemctl status xray

# 2. Проверить логи
sudo journalctl -u xray -n 100

# 3. Проверить iptables mangle
sudo iptables -t mangle -L XRAY -n -v

# 4. Проверить policy routing
ip rule show | grep "fwmark 0x1"
ip route show table 100

# 5. Проверить access log
sudo tail -f /var/log/xray/access.log
```

**Решение:**
1. **Xray не запущен:**
   ```bash
   sudo systemctl start xray
   sudo systemctl enable xray
   ```

2. **Ошибка в конфигурации:**
   ```bash
   /usr/local/bin/xray run -test -config /opt/xray/config.json
   # Исправить ошибки
   sudo systemctl restart xray
   ```

3. **iptables правила отсутствуют:**
   ```bash
   # Проверить cloud-init был выполнен
   sudo cloud-init status
   
   # Или пересоздать правила вручную
   # См. modules/edge/cloud-init.tpl
   ```

4. **Policy routing не работает:**
   ```bash
   sudo ip rule add fwmark 1 table 100
   sudo ip route add local 0.0.0.0/0 dev lo table 100
   ```

**Профилактика:**
- Не изменять iptables вручную
- Все изменения Xray конфига делать через Terraform
- Тестировать конфиг перед применением: `xray run -test`

---

### Проблема: Timeout при подключении к AI API

**Симптомы:**
```bash
curl -m 10 https://api.openai.com
# curl: (28) Operation timed out after 10000 milliseconds
```

**Диагностика:**
```bash
# На edge VM
# 1. Проверить логи Xray
sudo tail -f /var/log/xray/access.log
sudo tail -f /var/log/xray/error.log

# 2. Проверить connectivity к proxy серверу
nc -zv <proxy-server-ip> <proxy-port>

# 3. Проверить, что IP proxy исключен из TPROXY
sudo iptables -t mangle -L XRAY -n -v | grep <proxy-server-ip>

# 4. Проверить routing правила
jq '.routing.rules' /opt/xray/config.json
```

**Решение:**
1. **Proxy сервер IP не исключен из TPROXY (петля маршрутизации):**
   ```bash
   # Добавить исключение в iptables
   sudo iptables -t mangle -I XRAY 5 -d <proxy-server-ip> -j RETURN
   sudo netfilter-persistent save
   
   # Добавить в Xray config.json
   {
     "type": "field",
     "ip": ["<proxy-server-ip>"],
     "outboundTag": "direct"
   }
   ```

2. **Неправильные учетные данные proxy:**
   - Проверить настройки outbound в config.json
   - Проверить пароль/ключи

3. **Proxy сервер недоступен:**
   ```bash
   nc -zv <proxy-server-ip> <proxy-port>
   # Если не отвечает - сменить proxy сервер
   ```

**Профилактика:**
- При изменении proxy сервера всегда добавлять его IP в исключения (iptables + routing)
- Тестировать connectivity перед применением

---

### Проблема: Трафик не маршрутизируется через proxy

**Симптомы:**
- AI API доступны, но идут напрямую (не через proxy)
- В access.log видно: `[tproxy-in -> direct]` вместо `[tproxy-in -> proxy]`

**Диагностика:**
```bash
# На edge VM
# 1. Проверить access log
sudo grep "api.openai.com" /var/log/xray/access.log

# 2. Проверить routing правила
jq '.routing.rules[] | select(.outboundTag == "proxy")' /opt/xray/config.json

# 3. Проверить geosite файл
ls -lh /usr/local/bin/geosite.dat
```

**Решение:**
1. **Домен не попадает под правило:**
   ```json
   // Добавить в routing.rules
   {
     "type": "field",
     "domain": [
       "geosite:category-ai-!cn",
       "domain:api.openai.com",  // Явно указать
       "full:openai.com"         // Точное совпадение
     ],
     "outboundTag": "proxy"
   }
   ```

2. **Неправильный порядок правил:**
   ```json
   // Правило direct выше proxy правила
   // Переставить порядок: proxy правила должны быть выше
   ```

3. **geosite.dat устарел:**
   ```bash
   wget -O /usr/local/bin/geosite.dat \
     https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat
   sudo systemctl restart xray
   ```

**Профилактика:**
- Регулярно обновлять geosite.dat
- Тестировать routing правила после изменений
- Использовать явные domain правила для критичных сервисов

---

## Traefik и HTTP/HTTPS

### Проблема: Сайт недоступен извне

**Симптомы:**
- `curl team01.camp.aitalenthub.ru` - connection timeout или refused

**Диагностика:**
```bash
# 1. Проверить DNS
dig team01.camp.aitalenthub.ru

# 2. Проверить приложение запущено на team VM
ssh -F ~/.ssh/ai-camp/ssh-config team01 "sudo ss -tlnp | grep ':80\|:443'"

# На edge VM
# 3. Проверить Traefik
docker ps | grep traefik
docker logs traefik | tail -50

# 4. Проверить динамическую конфигурацию
cat /opt/traefik/dynamic/teams.yml | grep team01
```

**Решение:**
1. **DNS не настроен:**
   ```bash
   # Добавить A запись
   team01.camp.aitalenthub.ru  A  <edge-public-ip>
   ```

2. **Приложение не запущено:**
   ```bash
   # На team VM запустить приложение на порту 80 или 443
   ```

3. **Traefik не знает о route:**
   ```bash
   # Проверить /opt/traefik/dynamic/teams.yml
   # Должно быть:
   tcp:
     routers:
       team01:
         entryPoints: ["websecure"]
         rule: "HostSNI(`team01.camp.aitalenthub.ru`)"
         service: "team01"
     services:
       team01:
         loadBalancer:
           servers:
             - address: "10.20.0.8:443"
   
   # Если нет - применить terraform apply
   ```

4. **Security group блокирует:**
   - Проверить team SG разрешает 80/443 от edge SG

**Профилактика:**
- Настраивать DNS перед развертыванием
- Использовать systemd service для автозапуска приложения

---

### Проблема: SSL Certificate Error

**Симптомы:**
```
curl: (60) SSL certificate problem: unable to get local issuer certificate
```

**Диагностика:**
```bash
# 1. Проверить сертификат
openssl s_client -connect team01.camp.aitalenthub.ru:443 -servername team01.camp.aitalenthub.ru

# На team VM
# 2. Проверить наличие сертификата
sudo ls -la /etc/letsencrypt/live/team01.camp.aitalenthub.ru/
```

**Решение:**
1. **Сертификат не установлен:**
   ```bash
   # На team VM
   sudo apt install certbot python3-certbot-nginx
   sudo certbot --nginx -d team01.camp.aitalenthub.ru
   ```

2. **Сертификат истёк:**
   ```bash
   # Обновить
   sudo certbot renew
   ```

3. **Неправильный hostname:**
   - Убедиться, что certbot запрашивает сертификат для правильного домена

**Профилактика:**
- Certbot автоматически обновляет сертификаты
- Проверять: `sudo certbot renew --dry-run`

---

## DNS

### Проблема: DNS не разрешается

**Симптомы:**
```bash
nslookup team01.camp.aitalenthub.ru
# Server:		127.0.0.53
# ** server can't find team01.camp.aitalenthub.ru: NXDOMAIN
```

**Диагностика:**
```bash
# 1. Проверить DNS записи
dig team01.camp.aitalenthub.ru
dig team01.camp.aitalenthub.ru @8.8.8.8

# 2. Проверить propagation
# https://dnschecker.org/

# 3. Проверить wildcard
dig any-subdomain.camp.aitalenthub.ru
```

**Решение:**
1. **DNS запись не создана:**
   - Добавить A запись в DNS провайдере
   
2. **DNS propagation не завершен:**
   - Подождать 5-15 минут
   - Использовать `@8.8.8.8` для проверки

3. **Wildcard не настроен:**
   ```
   # Добавить wildcard запись
   *.camp.aitalenthub.ru  A  <edge-public-ip>
   ```

**Профилактика:**
- Использовать wildcard DNS для автоматического routing
- Проверять DNS перед развертыванием команды

---

## Performance

### Проблема: Высокая загрузка CPU на Team VM

**Диагностика:**
```bash
# На team VM
htop
top -bn1 | head -20

# Найти процесс с высокой загрузкой
ps aux --sort=-%cpu | head -10
```

**Решение:**
1. **Приложение требует больше ресурсов:**
   - Оптимизировать код
   - Или запросить у администратора увеличение vCPU

2. **Runaway процесс:**
   ```bash
   # Убить процесс
   sudo kill -9 <PID>
   ```

**Профилактика:**
- Мониторить ресурсы: `htop`, `vmstat`
- Использовать resource limits (systemd, cgroups)

---

### Проблема: Disk Full

**Симптомы:**
```
No space left on device
```

**Диагностика:**
```bash
df -h
du -sh ~/* | sort -h
```

**Решение:**
1. **Очистить логи:**
   ```bash
   sudo journalctl --vacuum-time=1d
   ```

2. **Очистить Docker:**
   ```bash
   docker system prune -a
   ```

3. **Удалить старые файлы:**
   ```bash
   rm -rf ~/workspace/old-projects/
   ```

**Профилактика:**
- Регулярно проверять: `df -h`
- Настроить log rotation
- Использовать Docker volume для данных

---

## Получение помощи

Если проблема не решена:

1. **Собрать диагностическую информацию:**
   ```bash
   # На team VM
   ip addr > diag.txt
   ip route >> diag.txt
   curl ifconfig.co >> diag.txt
   
   # На edge VM
   sudo systemctl status xray >> diag-edge.txt
   sudo iptables -t mangle -L XRAY -n -v >> diag-edge.txt
   ```

2. **Проверить логи:**
   - Xray: `/var/log/xray/error.log`
   - Traefik: `docker logs traefik`
   - System: `/var/log/syslog`

3. **Обратиться к администратору** с диагностической информацией

---

## См. также

- [user-guide.md](user-guide.md) - руководство пользователя
- [xray-configuration.md](xray-configuration.md) - конфигурация Xray
- [architecture.md](architecture.md) - архитектура инфраструктуры
