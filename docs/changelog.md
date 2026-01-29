# История изменений

> **Последнее обновление:** 2026-01-29

## Формат

Changelog следует принципам [Keep a Changelog](https://keepachangelog.com/ru/1.0.0/) и использует [Semantic Versioning](https://semver.org/lang/ru/).

**Типы изменений:**
- **Added** - новые функции
- **Changed** - изменения в существующих функциях
- **Deprecated** - функции, которые скоро будут удалены
- **Removed** - удаленные функции
- **Fixed** - исправленные баги
- **Security** - исправления безопасности

---

## [Unreleased]

### Planned
- Admin dashboard для мониторинга
- Automatic DNS management
- Multi-region support

---

## [2.0.0] - 2026-01-29

### Changed
- **Xray переведен с Docker на systemd сервис**
  - Причина: поддержка TPROXY с `IP_TRANSPARENT` socket option
  - Лучшая производительность и надежность
  - [Подробнее](xray-configuration.md#xray-как-systemd-сервис)

- **Рефакторинг Terraform конфигурации**
  - Создан модуль `team-credentials` для управления SSH ключами
  - Создан модуль `config-sync` для синхронизации конфигураций
  - Упрощена структура `environments/dev/main.tf` (559 → 218 строк)
  - [Подробнее](refactoring.md)

- **Улучшена гибкость конфигурации Xray**
  - Поддержка любого протокола (Shadowsocks, VLESS, VMess, Trojan)
  - Конфигурация через `secrets/xray-config.json`
  - Балансировка нагрузки между proxy серверами
  - [Подробнее](xray-configuration.md)

### Added
- **Lifecycle правила для VM**
  - Предотвращение пересоздания VM при обновлении образа
  - `ignore_changes = [boot_disk[0].initialize_params[0].image_id]`

- **Автоматическая синхронизация конфигураций**
  - Xray config автоматически синхронизируется на edge VM
  - Traefik dynamic config генерируется автоматически
  - Jump keys синхронизируются на bastion

- **Comprehensive documentation**
  - [quickstart.md](quickstart.md) - быстрый старт для команд
  - [architecture.md](architecture.md) - детальная архитектура
  - [xray-configuration.md](xray-configuration.md) - конфигурация Xray
  - [troubleshooting.md](troubleshooting.md) - решение проблем
  - [modules.md](modules.md) - обновлено с новыми модулями

### Fixed
- **Проблема пересоздания VM при обновлении xray конфигурации**
  - Раньше: terraform apply пересоздавал все VM
  - Теперь: только обновление конфига без downtime

- **Циклические зависимости между модулями**
  - Генерация SSH ключей перенесена в main.tf
  - Модули team-credentials и config-sync независимы от VM

### Removed
- Docker deployment для Xray (заменен на systemd)

---

## [1.0.0] - 2025-12-15

### Added
- **Начальная реализация инфраструктуры**
  - Yandex Cloud provider
  - VPC с public и private subnets
  - Security groups для edge и team VMs

- **Terraform модули**
  - `network` - VPC и подсети
  - `security` - Security groups
  - `routing` - Route tables для NAT
  - `edge` - Edge/NAT VM
  - `team_vm` - VM для команд

- **Edge/NAT VM**
  - Traefik reverse proxy с TLS passthrough
  - Xray TPROXY для AI APIs (Docker контейнер)
  - NAT для private subnet
  - SSH bastion (jump host)

- **Автоматическая генерация credentials**
  - SSH ключи для bastion, VM, GitHub
  - Готовые SSH config файлы
  - JSON файл со сводкой всех команд

- **Документация**
  - README.md с Quick Start
  - docs/usage.md с детальным руководством
  - docs/modules.md с описанием модулей

### Security
- SSH key-based authentication (пароли отключены)
- Network isolation (private subnet)
- Security groups с минимальными правами
- TLS passthrough (end-to-end encryption)

---

## Руководство по версионированию

### Major (X.0.0)
- Breaking changes (несовместимые изменения)
- Примеры: изменение структуры модулей, удаление функций

### Minor (x.Y.0)
- Новые функции (обратно совместимые)
- Примеры: новые модули, новые возможности

### Patch (x.y.Z)
- Исправления багов
- Обновления документации
- Примеры: fix бага, улучшение docs

---

## Процесс обновления

При выпуске новой версии:

1. Обновить этот файл (changelog.md)
2. Создать git tag
   ```bash
   git tag -a v2.0.0 -m "Release v2.0.0"
   git push origin v2.0.0
   ```
3. Создать GitHub Release с описанием изменений
4. Уведомить команды о breaking changes (если есть)

---

## См. также

- [development.md](development.md) - процесс разработки
- [README.md](../README.md) - обзор проекта
