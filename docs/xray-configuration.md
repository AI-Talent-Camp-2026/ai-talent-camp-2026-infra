# Конфигурация Xray

> **Последнее обновление:** 2026-01-29  
> **Связанные документы:** [user-guide.md](user-guide.md), [troubleshooting.md](troubleshooting.md)

## Обзор

Xray - это инструмент для маршрутизации трафика через proxy серверы с поддержкой различных протоколов. В нашей инфраструктуре Xray используется для прозрачного проксирования трафика к AI API и другим сервисам.

## Содержание

- [Xray как systemd сервис](#xray-как-systemd-сервис)
- [Структура конфигурационного файла](#структура-конфигурационного-файла)
- [Создание корректного конфига](#создание-корректного-конфига)
- [Routing правила](#routing-правила)
- [TPROXY механизм](#tproxy-механизм)
- [Диагностика](#диагностика)

---

## Xray как systemd сервис

Xray развернут как нативный systemd сервис, а не Docker контейнер.

### Причины использования systemd

- **TPROXY требует `IP_TRANSPARENT` socket option** - необходим для прозрачного проксирования
- **Нативный бинарный файл** обеспечивает лучшую совместимость с TPROXY
- **Прямой доступ к iptables mangle таблице** для перехвата пакетов
- **Меньшие накладные расходы** на производительность по сравнению с контейнеризацией

### Расположение файлов

| Компонент | Путь |
|-----------|------|
| Бинарный файл | `/usr/local/bin/xray` |
| Конфигурация | `/opt/xray/config.json` |
| Systemd service | `/etc/systemd/system/xray.service` |
| Access лог | `/var/log/xray/access.log` |
| Error лог | `/var/log/xray/error.log` |
| Geo данные | `/usr/local/bin/geoip.dat`, `/usr/local/bin/geosite.dat` |

### Управление сервисом

```bash
# Проверка статуса
sudo systemctl status xray

# Перезапуск сервиса
sudo systemctl restart xray

# Остановка сервиса
sudo systemctl stop xray

# Запуск сервиса
sudo systemctl start xray

# Просмотр логов в реальном времени
sudo journalctl -u xray -f

# Последние 100 строк логов
sudo journalctl -u xray -n 100
```

---

## Структура конфигурационного файла

Конфигурационный файл Xray (`/opt/xray/config.json`) состоит из нескольких основных секций.

### 1. log - Настройка логирования

```json
{
  "log": {
    "loglevel": "warning",
    "access": "/var/log/xray/access.log",
    "error": "/var/log/xray/error.log"
  }
}
```

**Уровни логирования:** `debug`, `info`, `warning`, `error`, `none`

### 2. inbounds - Входящие соединения

Определяет, как Xray принимает трафик. Для TPROXY используется протокол `dokodemo-door`:

```json
{
  "inbounds": [
    {
      "tag": "tproxy-in",
      "port": 12345,
      "protocol": "dokodemo-door",
      "settings": {
        "network": "tcp,udp",
        "followRedirect": true
      },
      "sniffing": {
        "enabled": true,
        "destOverride": ["http", "tls"],
        "routeOnly": false
      },
      "streamSettings": {
        "sockopt": {
          "tproxy": "tproxy"
        }
      }
    },
    {
      "tag": "dns-in",
      "port": 5353,
      "protocol": "dokodemo-door",
      "settings": {
        "address": "8.8.8.8",
        "port": 53,
        "network": "tcp,udp"
      }
    }
  ]
}
```

**Важные параметры:**
- `followRedirect: true` - следовать перенаправлениям iptables
- `sniffing.enabled: true` - определение протокола и домена
- `tproxy: "tproxy"` - режим прозрачного проксирования

### 3. outbounds - Исходящие соединения

Определяет, куда направлять трафик:

```json
{
  "outbounds": [
    {
      "tag": "proxy",
      "protocol": "shadowsocks",  // или "vless", "vmess", "trojan" и др.
      "settings": {
        // Настройки зависят от типа протокола
        // См. документацию Xray для конкретного протокола:
        // https://xtls.github.io/config/outbounds/
      }
    },
    {
      "tag": "direct",
      "protocol": "freedom"
    },
    {
      "tag": "block",
      "protocol": "blackhole",
      "settings": {
        "response": {
          "type": "http"
        }
      }
    },
    {
      "tag": "dns-out",
      "protocol": "dns"
    }
  ]
}
```

**Типы outbound:**
- **proxy** - через внешний proxy сервер (VLESS, Shadowsocks, VMess, Trojan и др.)
- **direct (freedom)** - напрямую в интернет без proxy
- **block (blackhole)** - блокировать соединение
- **dns** - для DNS запросов

### 4. routing - Правила маршрутизации

Определяет, какой трафик куда направлять:

```json
{
  "routing": {
    "domainStrategy": "IPIfNonMatch",
    "domainMatcher": "hybrid",
    "rules": [
      {
        "type": "field",
        "inboundTag": ["dns-in"],
        "outboundTag": "dns-out"
      },
      {
        "type": "field",
        "protocol": ["bittorrent"],
        "outboundTag": "block"
      },
      {
        "type": "field",
        "ip": ["geoip:private"],
        "outboundTag": "direct"
      },
      {
        "type": "field",
        "domain": [
          "geosite:category-ai-!cn",
          "geosite:youtube"
        ],
        "outboundTag": "proxy"
      },
      {
        "type": "field",
        "ip": ["0.0.0.0/0", "::/0"],
        "outboundTag": "direct"
      }
    ]
  }
}
```

**Стратегии маршрутизации:**
- `AsIs` - использовать адрес как есть
- `IPIfNonMatch` - разрешить DNS если домен не совпал
- `IPOnDemand` - разрешать DNS по требованию

### 5. dns - Настройки DNS (опционально)

```json
{
  "dns": {
    "servers": [
      {
        "address": "8.8.8.8",
        "port": 53,
        "domains": ["geosite:geolocation-!cn"]
      },
      {
        "address": "1.1.1.1",
        "port": 53
      }
    ]
  }
}
```

---

## Создание корректного конфига

### Вариант 1: Использование Terraform (рекомендуется)

Terraform автоматизирует управление конфигурацией Xray.

**Процесс:**

1. После первого `terraform apply` создается файл `secrets/xray-config.json`
2. Отредактируйте его согласно вашим требованиям
3. Примените изменения:
   ```bash
   cd environments/dev
   terraform apply
   ```

Terraform автоматически:
- ✅ Загрузит обновленный конфиг на edge VM
- ✅ Перезапустит Xray сервис
- ✅ Синхронизирует изменения

**Преимущества:**
- Version control для конфигурации
- Автоматическая синхронизация
- Откат изменений через git

### Вариант 2: Ручное редактирование на сервере

Для быстрых тестов или отладки можно редактировать конфиг напрямую.

```bash
# 1. Подключиться к edge VM
ssh jump@bastion.camp.aitalenthub.ru

# 2. Отредактировать конфиг
sudo nano /opt/xray/config.json

# 3. Проверить валидность конфига
/usr/local/bin/xray run -test -config /opt/xray/config.json

# 4. Если валидация прошла, применить изменения
sudo systemctl restart xray

# 5. Проверить статус
sudo systemctl status xray

# 6. Проверить логи на ошибки
sudo journalctl -u xray -n 50
```

⚠️ **Важно:** Изменения, сделанные напрямую на сервере, будут перезаписаны при следующем `terraform apply`.

### Требования к конфигурационному файлу

Для корректной работы конфигурация должна соответствовать требованиям:

1. **Валидный JSON**
   ```bash
   # Проверка с помощью jq
   jq . /opt/xray/config.json
   ```

2. **Обязательные секции**
   - `inbounds` - как принимать трафик
   - `outbounds` - куда направлять трафик
   - `routing` - правила маршрутизации

3. **Правильные теги**
   - Теги в `routing.rules.outboundTag` должны соответствовать `outbounds[].tag`
   - Несуществующий тег приведет к ошибке

4. **Исключения TPROXY**
   - IP proxy сервера должен быть исключен из TPROXY (см. раздел [TPROXY механизм](#tproxy-механизм))

---

## Routing правила

Routing правила определяют логику маршрутизации трафика.

### Использование geosite категорий

Xray поддерживает предопределенные категории доменов через файл `geosite.dat`.

**Доступные категории:**

| Категория | Описание |
|-----------|----------|
| `geosite:category-ai-!cn` | AI сервисы (OpenAI, Anthropic, Google AI, Groq, Mistral и др.) |
| `geosite:youtube` | YouTube |
| `geosite:instagram` | Instagram |
| `geosite:tiktok` | TikTok |
| `geosite:linkedin` | LinkedIn |
| `geosite:telegram` | Telegram |
| `geosite:notion` | Notion |
| `geosite:github` | GitHub |
| `geosite:google` | Google сервисы |
| `geosite:geolocation-!cn` | Все сайты кроме китайских |

### Примеры правил

#### Направить AI API через proxy

```json
{
  "type": "field",
  "domain": ["geosite:category-ai-!cn"],
  "outboundTag": "proxy"
}
```

#### Направить конкретный домен через proxy

```json
{
  "type": "field",
  "domain": [
    "domain:example.com",       // домен и все поддомены
    "full:api.example.com"      // только точное совпадение
  ],
  "outboundTag": "proxy"
}
```

#### Исключить IP из проксирования

```json
{
  "type": "field",
  "ip": ["1.2.3.4", "5.6.7.8"],
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

#### Блокировать BitTorrent

```json
{
  "type": "field",
  "protocol": ["bittorrent"],
  "outboundTag": "block"
}
```

### Порядок правил важен

⚠️ **Правила проверяются сверху вниз. Первое совпадение применяется.**

**Рекомендуемый порядок:**

1. **DNS правила** - для internal DNS
2. **Блокировки** - блокировать unwanted трафик
3. **Исключения** - private networks, proxy server IP
4. **Специфичные правила** - конкретные домены/IP
5. **Категории** - geosite правила
6. **Правило по умолчанию** - обычно `direct` для всего остального

**Пример правильного порядка:**

```json
{
  "routing": {
    "rules": [
      // 1. DNS
      {"inboundTag": ["dns-in"], "outboundTag": "dns-out"},
      
      // 2. Блокировки
      {"protocol": ["bittorrent"], "outboundTag": "block"},
      
      // 3. Исключения
      {"ip": ["geoip:private"], "outboundTag": "direct"},
      {"ip": ["109.248.160.207"], "outboundTag": "direct"},
      
      // 4. Специфичные правила
      {"domain": ["domain:myapp.internal"], "outboundTag": "direct"},
      
      // 5. Категории
      {"domain": ["geosite:category-ai-!cn"], "outboundTag": "proxy"},
      
      // 6. По умолчанию
      {"ip": ["0.0.0.0/0", "::/0"], "outboundTag": "direct"}
    ]
  }
}
```

---

## TPROXY механизм

TPROXY (Transparent Proxy) перехватывает сетевой трафик прозрачно для приложений.

### Как работает

```
Team VM → iptables mangle (TPROXY) → Policy routing → Xray dokodemo-door
                                                           ↓
                                          [routing rules проверка]
                                                           ↓
                                          proxy / direct / block
```

### Компоненты

1. **iptables mangle** - перехватывает TCP/UDP пакеты из private subnet
2. **Policy routing** - маршрутизирует помеченные пакеты (fwmark=1) на loopback
3. **Xray dokodemo-door** - принимает перехваченные пакеты на порту 12345

### Проверка iptables правил

```bash
# Проверить правила TPROXY
sudo iptables -t mangle -L XRAY -n -v

# Должно быть примерно так:
# Chain XRAY (1 references)
#  pkts bytes target     prot opt in     out     source               destination
#     0     0 RETURN     all  --  *      *       0.0.0.0/0            10.0.0.0/8
#     0     0 RETURN     all  --  *      *       0.0.0.0/0            172.16.0.0/12
#    75 20036 RETURN     all  --  *      *       0.0.0.0/0            192.168.0.0/16
#     0     0 RETURN     all  --  *      *       0.0.0.0/0            127.0.0.0/8
#     0     0 RETURN     all  --  *      *       0.0.0.0/0            109.248.160.207
#   169 10591 TPROXY     tcp  --  *      *       0.0.0.0/0            0.0.0.0/0
#     7   532 TPROXY     udp  --  *      *       0.0.0.0/0            0.0.0.0/0
```

### Проверка policy routing

```bash
# Проверить ip rules
ip rule show

# Должно быть:
# 32764:  from all fwmark 0x1 lookup 100

# Проверить route table 100
ip route show table 100

# Должно быть:
# local default dev lo scope host
```

### Исключения из TPROXY

⚠️ **Критически важно:** IP адрес proxy сервера должен быть исключен из TPROXY, иначе возникнет петля маршрутизации.

Исключения добавляются в **двух местах**:

#### 1. В iptables (на edge VM)

```bash
# Добавить исключение для IP proxy сервера
sudo iptables -t mangle -I XRAY 5 -d <proxy-server-ip> -j RETURN

# Сохранить правила
sudo netfilter-persistent save
```

**Пример:**
```bash
sudo iptables -t mangle -I XRAY 5 -d 109.248.160.207 -j RETURN
sudo netfilter-persistent save
```

#### 2. В routing правилах Xray (config.json)

```json
{
  "type": "field",
  "ip": ["<proxy-server-ip>"],
  "outboundTag": "direct"
}
```

**Пример:**
```json
{
  "type": "field",
  "ip": ["109.248.160.207"],
  "outboundTag": "direct"
}
```

### Отладка TPROXY

```bash
# Посмотреть статистику по правилам
sudo iptables -t mangle -L XRAY -n -v

# Колонка "pkts" показывает количество обработанных пакетов
# Если 0 - трафик не перехватывается

# Проверить, что правило PREROUTING активно
sudo iptables -t mangle -L PREROUTING -n -v | grep XRAY

# Должно быть примерно:
#  1234 567890 XRAY       all  --  *      *       10.20.0.0/24         0.0.0.0/0
```

---

## Диагностика

### 1. Проверка статуса сервиса

```bash
sudo systemctl status xray
```

**Ожидаемый результат:**
```
● xray.service - Xray Service
     Loaded: loaded (/etc/systemd/system/xray.service; enabled; vendor preset: enabled)
     Active: active (running) since Thu 2026-01-29 10:32:04 UTC; 3min 36s ago
       Docs: https://github.com/XTLS/Xray-core
   Main PID: 1797 (xray)
      Tasks: 8 (limit: 4643)
     Memory: 10.5M
```

Статус должен быть: `Active: active (running)`

### 2. Проверка логов

```bash
# Последние 50 строк
sudo journalctl -u xray -n 50

# В реальном времени (Ctrl+C для выхода)
sudo journalctl -u xray -f

# Access лог - какой трафик обрабатывается
sudo tail -f /var/log/xray/access.log

# Error лог - ошибки конфигурации или подключения
sudo tail -f /var/log/xray/error.log
```

**Что искать в логах:**

- ✅ `Xray 25.1.30 started` - успешный запуск
- ✅ `accepted tcp:domain.com:443 [tproxy-in -> proxy]` - трафик маршрутизируется
- ❌ `failed to parse config` - ошибка в JSON
- ❌ `dial tcp: i/o timeout` - проблемы с connectivity к proxy серверу

### 3. Валидация конфигурации

```bash
/usr/local/bin/xray run -test -config /opt/xray/config.json
```

**Успешный результат:**
```
Xray 25.1.30 (Xray, Penetrates Everything.) 0a8470c
A unified platform for anti-censorship.
Configuration OK.
```

**При ошибке:**
```
Failed to start: main: failed to load config: ...
```

### 4. Проверка connectivity к proxy серверу

```bash
# Проверить доступность порта
nc -zv <proxy-server> <port>

# Пример:
nc -zv 109.248.160.207 31017

# Ожидаемый результат:
# Connection to 109.248.160.207 31017 port [tcp/*] succeeded!

# Проверить DNS разрешение (если используется hostname)
nslookup <proxy-server>
```

### 5. Тестирование маршрутизации

С **team VM** проверить routing:

```bash
# Проверить AI API (должен идти через proxy)
curl -v -m 10 https://api.openai.com

# Проверить обычный сайт (должен идти direct)
curl -v -m 5 http://ya.ru

# Проверить внешний IP
curl -s http://ifconfig.co
# Должен показать IP edge VM
```

**На edge VM** смотреть access log:

```bash
sudo tail -f /var/log/xray/access.log

# Пример правильной работы:
# 2026/01/29 10:33:58.499662 from 10.20.0.8:39444 accepted tcp:api.openai.com:443 [tproxy-in -> proxy]
# 2026/01/29 10:34:01.123456 from 10.20.0.8:40123 accepted tcp:ya.ru:80 [tproxy-in -> direct]
```

### Типичные проблемы

#### ❌ Проблема: Xray не запускается

**Симптомы:**
- `systemctl status xray` показывает `failed` или `inactive`

**Диагностика:**
```bash
# Проверить валидность JSON
jq . /opt/xray/config.json

# Проверить логи
journalctl -u xray -n 100
```

**Решение:**
- Исправить синтаксис JSON
- Проверить наличие файлов geoip.dat и geosite.dat
- Убедиться, что `/var/log/xray/` существует и доступен для записи

#### ❌ Проблема: Трафик не проходит через proxy

**Симптомы:**
- AI API не работают с team VM
- Все сайты недоступны или работают медленно

**Диагностика:**
```bash
# На edge VM проверить access log
sudo tail -f /var/log/xray/access.log

# Если логов нет - трафик не доходит до Xray
# Проверить TPROXY правила
sudo iptables -t mangle -L XRAY -n -v
```

**Решение:**
- Проверить routing правила в config.json
- Убедиться, что домен попадает под правило (смотреть access.log)
- Проверить connectivity к proxy серверу
- Проверить, что IP proxy сервера исключен из TPROXY

#### ❌ Проблема: Timeout при подключении

**Симптомы:**
- Соединение устанавливается, но висит
- `curl` завершается по timeout

**Диагностика:**
```bash
# Проверить error log
sudo tail -f /var/log/xray/error.log

# Проверить connectivity
nc -zv <proxy-server> <port>

# Проверить исключения
sudo iptables -t mangle -L XRAY -n -v | grep <proxy-server-ip>
```

**Решение:**
- Добавить IP proxy сервера в исключения TPROXY (iptables + routing)
- Проверить учетные данные в настройках outbound
- Убедиться, что proxy сервер работает

#### ❌ Проблема: Некоторые сайты не работают

**Симптомы:**
- Часть сайтов работает, часть нет
- Непредсказуемое поведение

**Диагностика:**
```bash
# Проверить в access log, куда идет трафик
sudo grep "domain.com" /var/log/xray/access.log

# Проверить порядок правил
jq '.routing.rules' /opt/xray/config.json
```

**Решение:**
- Пересмотреть порядок routing правил
- Добавить специфичные правила для проблемных доменов
- Проверить, что правило по умолчанию (catch-all) присутствует

---

## См. также

- [Руководство пользователя](user-guide.md) - детальное использование инфраструктуры
- [Руководство администратора](admin-guide.md) - управление через Terraform
- [Troubleshooting](troubleshooting.md) - решение проблем
- [Официальная документация Xray](https://xtls.github.io/)
