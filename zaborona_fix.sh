#!/bin/bash

echo "=== ПЕРЕВІРЕНА ВЕРСІЯ НАЛАШТУВАННЯ ZABORONA VPN ==="

# Зупинка поточного VPN
/etc/init.d/openvpn stop
sleep 3

# КЛЮЧОВЕ ВИПРАВЛЕННЯ: Використовуємо КОНФІГУРАЦІЙНИЙ ФАЙЛ замість UCI
echo "Використовуємо готовий .ovpn файл замість UCI налаштувань..."

# Перевіряємо наявність завантаженого конфігу
if [ ! -f "/etc/openvpn/zaborona-help.ovpn" ]; then
    echo "Завантажуємо конфігураційний файл..."
    wget --no-check-certificate "https://zaborona.help/openvpn-client-config/zaborona-help_maxroutes.ovpn" -O /etc/openvpn/zaborona-help.ovpn
fi

# Отримуємо параметри з оригінального .ovpn файлу
echo "Аналіз оригінального .ovpn файлу:"
grep "^remote " /etc/openvpn/zaborona-help.ovpn | head -1
grep "^port " /etc/openvpn/zaborona-help.ovpn | head -1
grep "^proto " /etc/openvpn/zaborona-help.ovpn | head -1

# Видаляємо UCI конфігурацію і налаштовуємо пряме використання .ovpn файлу
uci delete openvpn.zaborona_help 2>/dev/null

# Створюємо новий конфіг для прямого використання .ovpn файлу
uci set openvpn.zaborona_help=openvpn
uci set openvpn.zaborona_help.config='/etc/openvpn/zaborona-help.ovpn'
uci set openvpn.zaborona_help.enabled='1'

uci commit openvpn

# Модифікуємо .ovpn файл для коректної роботи з OpenWrt
echo "Модифікуємо .ovpn файл..."

# Додаємо налаштування для стабільної роботи
if ! grep -q "script-security 2" /etc/openvpn/zaborona-help.ovpn; then
    echo "script-security 2" >> /etc/openvpn/zaborona-help.ovpn
fi

if ! grep -q "up /etc/openvpn/update-resolv-conf" /etc/openvpn/zaborona-help.ovpn; then
    echo "up /etc/openvpn/update-resolv-conf" >> /etc/openvpn/zaborona-help.ovpn
    echo "down /etc/openvpn/update-resolv-conf" >> /etc/openvpn/zaborona-help.ovpn
fi

# Створюємо скрипт для управління DNS
cat > /etc/openvpn/update-resolv-conf << 'INNER_EOF'
#!/bin/sh
case $script_type in
up)
    # Зберігаємо оригінальні DNS
    cp /etc/resolv.conf /tmp/resolv.conf.zaborona.bak
    # Встановлюємо Zaborona DNS
    echo "nameserver 208.67.222.222" > /etc/resolv.conf
    echo "nameserver 208.67.220.220" >> /etc/resolv.conf
    ;;
down)
    # Відновлюємо оригінальні DNS
    if [ -f "/tmp/resolv.conf.zaborona.bak" ]; then
        mv /tmp/resolv.conf.zaborona.bak /etc/resolv.conf
    fi
    ;;
esac
INNER_EOF

chmod +x /etc/openvpn/update-resolv-conf

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

# Перезапуск сервісів
echo "Перезапуск сервісів..."
/etc/init.d/network restart
sleep 10
/etc/init.d/firewall restart
sleep 10
/etc/init.d/openvpn start

echo "Очікуємо підключення..."
sleep 40

# Перевірка результату
if ip addr show tun0 >/dev/null 2>&1; then
    echo "✅ SUCCESS: VPN підключений через .ovpn файл!"
    echo
    echo "Інтерфейс tun0:"
    ip addr show tun0
    echo
    echo "DNS сервери:"
    cat /etc/resolv.conf
    echo
    echo "Тест доступу до заблокованого сайту:"
    timeout 5 wget -q --spider http://vk.com && echo "✅ VK.com доступний" || echo "❌ VK.com недоступний"
    timeout 5 wget -q --spider https://ok.ru && echo "✅ OK.ru доступний" || echo "❌ OK.ru недоступний"
else
    echo "❌ Проблема з підключенням!"
    echo
    echo "Останні логи OpenVPN:"
    logread | grep openvpn | tail -10
    echo
    echo "Зміст .ovpn файлу (перші 20 рядків):"
    head -20 /etc/openvpn/zaborona-help.ovpn
    echo
    echo "Спробуйте ручний запуск для детальної діагностики:"
    echo "openvpn --config /etc/openvpn/zaborona-help.ovpn --verb 3"
fi

echo "=== НАЛАШТУВАННЯ ЗАВЕРШЕНО ==="
EOF
