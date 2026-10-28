# Конфигурация виртуальной машины devops-vm

Документ описывает конфигурацию учебного сервера после практических работ № 5 и № 6
и позволяет восстановить её со снимка `01-clean-install`. Команды выполняются по порядку.

Хост: Windows 11, VirtualBox 7.2, клиентские команды выполняются в Git Bash;
начиная с Пр6 команды rsync и `scripts/deploy.sh` выполняются в WSL версии 1 (Ubuntu),
куда скопированы `~/.ssh/devops_vm`, `~/.ssh/config`, `~/.ssh/known_hosts` (права 600).

## 1. Параметры машины

| Параметр | Значение |
|---|---|
| Имя ВМ | `devops-vm` |
| ОС | Ubuntu Server 24.04.5 LTS (64-bit), установка без minimized, без snaps |
| Оперативная память | 2048 МБ |
| Процессоры | 2 |
| Диск | 25 ГБ, динамический VDI, LVM (`/` = 11,5 ГБ, `/boot` = 2 ГБ) |
| Имя узла | `devops-vm`, FQDN `devops-vm.devops.local` |
| Пользователь при установке | `student` (группа `sudo`), установлен OpenSSH server |

## 2. Сетевые интерфейсы

| Адаптер VirtualBox | Тип | Интерфейс в ВМ | Адрес | Назначение |
|---|---|---|---|---|
| Адаптер 1 | NAT | `enp0s3` | `10.0.2.15/24` (DHCP) | выход в Интернет, apt; SSH с хоста через проброс порта |
| Адаптер 2 | Host-only (`VirtualBox Host-Only Ethernet Adapter`, сеть `192.168.56.0/24`) | `enp0s8` | `192.168.56.101/24` (DHCP) | прямой доступ с хоста (SSH, HTTP в Пр6) |

Адрес хоста в сети Host-only: `192.168.56.1`. Хост в сети NAT виден из ВМ как `10.0.2.2`.

## 3. Правило проброса портов

Адаптер 1 (NAT) → Дополнительно → Проброс портов:

| Имя | Протокол | Адрес хоста | Порт хоста | Адрес гостя | Порт гостя |
|---|---|---|---|---|---|
| ssh | TCP | 127.0.0.1 | 2222 | — | **2222** |

На чистой установке порт гостя равен 22; после переноса SSH на порт 2222 (раздел 5) его нужно сменить на 2222.

## 4. Учётные записи

| Имя | Группы | Способ входа по SSH |
|---|---|---|
| `student` | `student`, `sudo`, ... | вход по SSH запрещён (`AllowUsers devops`), только локальная консоль |
| `devops` | `devops`, `sudo`, `users` | только по ключу ed25519 (`~/.ssh/devops_vm` на хосте) |
| `root` | — | вход по SSH запрещён (`PermitRootLogin no`) |

Создание пользователя (на ВМ, под `student`):

```bash
sudo adduser devops
sudo usermod -aG sudo devops
groups devops
```

Ключ (на хосте, Git Bash), без парольной фразы:

```bash
ssh-keygen -t ed25519 -C "devops-vm-key" -f ~/.ssh/devops_vm
ssh-copy-id -i ~/.ssh/devops_vm.pub -p 2222 devops@127.0.0.1
```

Права на ВМ: `~/.ssh` = `700`, `~/.ssh/authorized_keys` = `600`.

Файл `~/.ssh/config` на хосте:

```
Host devops
    HostName 127.0.0.1
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes

Host devops.local
    HostName devops.local
    Port 2222
    User devops
    IdentityFile ~/.ssh/devops_vm
    IdentitiesOnly yes
```

## 5. Служба SSH

- Порт: **2222**.
- Основной файл `/etc/ssh/sshd_config` не изменялся, резервная копия: `/etc/ssh/sshd_config.backup`.
- Изменения вынесены в `/etc/ssh/sshd_config.d/99-hardening.conf`:

```
Port 2222

PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
PermitEmptyPasswords no
MaxAuthTries 3
LoginGraceTime 30

AllowUsers devops

X11Forwarding no
ClientAliveInterval 300
ClientAliveCountMax 2
```

- В `/etc/ssh/sshd_config.d/50-cloud-init.conf` строка `PasswordAuthentication yes` закомментирована
  (файлы читаются по алфавиту, действует первое значение, поэтому `99-` его не переопределяет).
- Активация по сокету отключена, служба запускается напрямую (иначе порт задаёт `ssh.socket`, а не `Port`).

Порядок применения (действующую SSH-сессию не закрывать, проверять в новом окне):

```bash
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup
sudo tee /etc/ssh/sshd_config.d/99-hardening.conf > /dev/null << 'EOF'
...содержимое выше...
EOF
sudo sed -i 's/^PasswordAuthentication yes/#PasswordAuthentication yes/' /etc/ssh/sshd_config.d/50-cloud-init.conf
sudo sshd -t && echo "Конфигурация корректна"
sudo sshd -T | grep -Ei "^(port|permitrootlogin|passwordauthentication|maxauthtries|allowusers)"
sudo systemctl disable --now ssh.socket
sudo systemctl enable --now ssh.service
sudo systemctl restart ssh
sudo ss -tlnp | grep sshd        # 0.0.0.0:2222
```

После этого в VirtualBox сменить порт гостя в правиле проброса на 2222 (раздел 3) и проверить `ssh devops`.

## 6. Правила межсетевого экрана

Политики по умолчанию: `deny (incoming)`, `allow (outgoing)`, `disabled (routed)`. Журналирование: `medium`.

| Порт | Действие | Комментарий |
|---|---|---|
| 2222/tcp (+v6) | LIMIT IN | SSH rate-limited |
| 80/tcp (+v6) | ALLOW IN | HTTP |
| 443/tcp (+v6) | ALLOW IN | HTTPS |

Команды (правило для 2222 создаётся **до** `ufw enable`):

```bash
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw limit 2222/tcp comment 'SSH rate-limited'
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'
sudo ufw enable
sudo ufw logging medium
sudo ufw status verbose
```

## 7. Локальное доменное имя

На хосте (PowerShell от администратора):

```powershell
Add-Content -Path C:\Windows\System32\drivers\etc\hosts -Value "192.168.56.101    devops.local"
ipconfig /flushdns
```

На ВМ:

```bash
sudo hostnamectl set-hostname devops-vm
sudo sed -i 's/^127.0.1.1.*/127.0.1.1 devops-vm.devops.local devops-vm/' /etc/hosts
hostname -f        # devops-vm.devops.local
```

Проверка с хоста: `ping devops.local`, `ssh devops.local`.

## 8. Веб-сервер

| Параметр | Значение |
|---|---|
| Пакет | `nginx` (из репозитория Ubuntu), служба `nginx.service` |
| Конфигурация ресурса | `/etc/nginx/sites-available/devops-site`, ссылка в `/etc/nginx/sites-enabled/` |
| Стандартный ресурс | отключён: удалена ссылка `/etc/nginx/sites-enabled/default` (файл в `sites-available` сохранён) |
| Каталог ресурса | `/var/www/devops-site`, владелец `devops:devops`, каталоги `755`, файлы `644` |
| Сертификат | `/etc/ssl/certs/devops.crt`, `root:root`, `644`, самоподписанный, SAN `DNS:devops.local` |
| Закрытый ключ | `/etc/ssl/private/devops.key`, `root:root`, `600` |
| Срок действия сертификата | 365 дней с даты выпуска (`openssl x509 -in /etc/ssl/certs/devops.crt -noout -dates`) |
| Журналы | `/var/log/nginx/devops-site.access.log`, `/var/log/nginx/devops-site.error.log` |
| Порты | 80 (только перенаправление 301 на HTTPS), 443 (TLSv1.2, TLSv1.3); правила UFW из раздела 6 |

Установка и каталог ресурса (на ВМ, под `devops`):

```bash
sudo apt update && sudo apt install -y nginx
sudo mkdir -p /var/www/devops-site
sudo chown -R devops:devops /var/www/devops-site
```

Сертификат и ключ:

```bash
sudo openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout /etc/ssl/private/devops.key \
    -out /etc/ssl/certs/devops.crt \
    -subj "/CN=devops.local" \
    -addext "subjectAltName=DNS:devops.local"
sudo chmod 600 /etc/ssl/private/devops.key
```

Конфигурация `/etc/nginx/sites-available/devops-site`:

```nginx
# Блок 1: перенаправление HTTP -> HTTPS
server {
    listen 80;
    listen [::]:80;
    server_name devops.local;
    return 301 https://$host$request_uri;
}

# Блок 2: ресурс по HTTPS
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name devops.local;

    ssl_certificate     /etc/ssl/certs/devops.crt;
    ssl_certificate_key /etc/ssl/private/devops.key;
    ssl_protocols       TLSv1.2 TLSv1.3;

    root /var/www/devops-site;
    index index.html;

    location / {
        try_files $uri $uri/ =404;
    }

    error_page 404 /404.html;

    access_log /var/log/nginx/devops-site.access.log;
    error_log /var/log/nginx/devops-site.error.log;
}
```

Активация (любое изменение применяется только через `nginx -t && reload`, не `restart`):

```bash
sudo ln -s /etc/nginx/sites-available/devops-site /etc/nginx/sites-enabled/
sudo rm /etc/nginx/sites-enabled/default
sudo nginx -t && sudo systemctl reload nginx
sudo ss -tlnp | grep nginx        # 0.0.0.0:80, 0.0.0.0:443
```

HSTS не включается (самоподписанный сертификат). Доверие на хосте: сертификат копируется
по SSH (`scp devops:/etc/ssl/certs/devops.crt ~/devops.crt`) и передаётся клиенту через `--cacert`.

Содержимое доставляется из каталога `site/` репозитория сценарием `scripts/deploy.sh`
(rsync с `--delete --chmod=D755,F644`, одно SSH-соединение, проверка `curl --cacert`).

## 9. Снимки состояния

| Снимок | Создан | Состояние |
|---|---|---|
| `01-clean-install` | 13.10.2026 20:16 | чистая установка, `apt upgrade`, OpenSSH, ВМ выключена |
| `02-keys-configured` | 13.10.2026 20:39 | пользователь `devops`, вход по ключу, `~/.ssh/config` на хосте |
| `03-ssh-hardened` | 13.10.2026 21:08 | `99-hardening.conf`, порт 2222, сокет отключён, проброс 2222→2222 |
| `04-nginx-https` | Пр6, после задания 2 | nginx, сертификат и ключ, ресурс `devops.local` по HTTPS, перенаправление HTTP→HTTPS |

## 10. Проверка

Скрипт `scripts/audit.sh` проверяет основные параметры (код возврата 0, если всё в порядке):

```bash
scp scripts/audit.sh devops:~/
ssh -t devops 'bash ~/audit.sh; echo "exit code: $?"'
```
