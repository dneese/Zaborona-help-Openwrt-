# Zaborona VPN для OpenWrt 23.05 - Робоча інструкція

## 📖 Передісторія

Оригінальний скрипт з GitHub Wiki для OpenWrt 18.06 не працює на новіших версіях OpenWrt (23.05+) через кілька проблем:

- ❌ Відсутній порт у налаштуванні `remote`
- ❌ Проблеми з UCI налаштуваннями vs нативний .ovpn конфіг
- ❌ Некоректна обробка DNS серверів
- ❌ Застарілі налаштування cipher

## ✅ Робоче рішення

Використовуємо **оригінальний .ovpn файл** замість UCI налаштувань + правильне керування DNS.

## 🚀 Встановлення

### Крок 1: Підключіться до роутера через SSH
```bash
ssh root@192.168.1.1
```

### Крок 2: Встановіть пакети
```bash
opkg update
opkg install openvpn-openssl luci-app-openvpn luci-i18n-openvpn-ru libustream-openssl
```

### Крок 3: Скопіюйте і вставте цей скрипт в термінал
```bash
#!/bin/bash

echo "=== Налаштування Zaborona VPN для OpenWrt 23.05 ==="

# Зупинка поточного VPN
/etc/init.d/openvpn stop
sleep 3

# Створення директорії
mkdir -p /etc/openvpn

# Завантаження файлів
echo "Завантаження конфігураційних файлів..."
wget --no-check-certificate "https://zaborona.help/ca.crt" -O /etc/openvpn/ca.crt
wget --no-check-certificate "https://zaborona.help/zaborona-help.crt" -O /etc/openvpn/zaborona-help.crt
wget --no-check-certificate "https://zaborona.help/zaborona-help.key" -O /etc/openvpn/zaborona-help.key
wget --no-check-certificate "https://zaborona.help/openvpn-client-config/zaborona-help_maxroutes.ovpn" -O /etc/openvpn/zaborona-help.ovpn

# Налаштування OpenVPN через .ovpn файл (КЛЮЧОВЕ РІШЕННЯ)
uci delete openvpn.zaborona_help 2>/dev/null
uci delete openvpn.custom_config 2>/dev/null
uci delete openvpn.sample_server 2>/dev/null
uci delete openvpn.sample_client 2>/dev/null

uci set openvpn.zaborona_help=openvpn
uci set openvpn.zaborona_help.config='/etc/openvpn/zaborona-help.ovpn'
uci set openvpn.zaborona_help.enabled='1'
uci commit openvpn

# DNS скрипти для автоматичного перемикання
cat > /etc/openvpn/update-resolv-conf << 'EOF'
#!/bin/sh
case $script_type in
up)
    cp /etc/resolv.conf /tmp/resolv.conf.zaborona.bak
    echo "nameserver 208.67.222.222" > /etc/resolv.conf
    echo "nameserver 208.67.220.220" >> /etc/resolv.conf
    ;;
down)
    if [ -f "/tmp/resolv.conf.zaborona.bak" ]; then
        mv /tmp/resolv.conf.zaborona.bak /etc/resolv.conf
    fi
    ;;
esac
EOF

chmod +x /etc/openvpn/update-resolv-conf

# Модифікація .ovpn файлу для OpenWrt
if ! grep -q "script-security 2" /etc/openvpn/zaborona-help.ovpn; then
    echo "script-security 2" >> /etc/openvpn/zaborona-help.ovpn
fi

if ! grep -q "up /etc/openvpn/update-resolv-conf" /etc/openvpn/zaborona-help.ovpn; then
    echo "up /etc/openvpn/update-resolv-conf" >> /etc/openvpn/zaborona-help.ovpn
    echo "down /etc/openvpn/update-resolv-conf" >> /etc/openvpn/zaborona-help.ovpn
fi

# Налаштування мережі
uci set network.zaborona_help=interface
uci set network.zaborona_help.proto='none'
uci set network.zaborona_help.device='tun0'
uci set network.zaborona_help.auto='1'
uci commit network

# Налаштування firewall
WAN_ZONE=$(uci show firewall | grep "firewall\.@zone\[.*\]\.name='wan'" | cut -d'[' -f2 | cut -d']' -f1)
if [ -n "$WAN_ZONE" ]; then
    if ! uci get firewall.@zone[$WAN_ZONE].network | grep -q "zaborona_help"; then
        uci add_list firewall.@zone[$WAN_ZONE].network='zaborona_help'
    fi
else
    uci set firewall.@zone[1].network='wan zaborona_help'
fi
uci commit firewall

# Запуск сервісів
echo "Перезапуск сервісів..."
/etc/init.d/network restart
sleep 5
/etc/init.d/firewall restart
/etc/init.d/openvpn restart

echo "Очікування підключення (40 секунд)..."
sleep 40

# Перевірка результату
if ip addr show tun0 >/dev/null 2>&1; then
    echo "✅ SUCCESS: VPN підключений!"
    echo "Інтерфейс tun0:"
    ip addr show tun0
    echo "DNS:"
    cat /etc/resolv.conf
    echo "Тест доступу:"
    timeout 5 wget -q --spider http://vk.com && echo "✅ VK.com доступний" || echo "❌ VK.com недоступний"
else
    echo "❌ Помилка підключення. Логи:"
    logread | grep openvpn | tail -5
fi

echo "=== Налаштування завершено ==="
```

### Крок 4: Дочекайтеся завершення (2-3 хвилини)

## 🔍 Перевірка роботи

```bash
# Статус VPN
/etc/init.d/openvpn status

# Перевірка інтерфейсу
ip addr show tun0

# Тест заблокованих сайтів
curl -I http://vk.com
curl -I https://ok.ru
```

## 🎯 Ключові відмінності від оригінального скрипта

1. **Використання .ovpn файлу** замість індивідуальних UCI параметрів
2. **Автоматичне DNS перемикання** через up/down скрипти  
3. **Збільшений таймер** підключення до 40 секунд
4. **Сумісність з OpenWrt 23.05+**

## 🔧 Діагностика проблем

```bash
# Детальні логи
logread | grep openvpn

# Ручний запуск для діагностики
openvpn --config /etc/openvpn/zaborona-help.ovpn --verb 3

# Перевірка маршрутів
ip route | grep tun0
```

## ⚠️ Важливі примітки

- DNS автоматично перемикається на 208.67.222.222 та 208.67.220.220
- При відключенні VPN DNS відновлюються автоматично
- Працює з PPPoE та іншими типами WAN підключень
- Тестовано на OpenWrt 23.05.5

## 🤝 Внесок

Рішення знайдено та протестовано спільнотою користувачів OpenWrt та Zaborona VPN.

---
**Статус**: ✅ Працює на OpenWrt 23.05+  
**Останнє оновлення**: Вересень 2025


![Скриншот yandex.ru](Screenshot_20250909-202301.png)

![Скриншот mail.ru](Screenshot_20250909-203002.png).













