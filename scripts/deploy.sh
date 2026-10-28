#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"                    # псевдоним из ~/.ssh/config (ПР № 5, шаг 1.6)
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="$(git rev-parse --show-toplevel)/site/"

# 1. Разбор аргумента --dry-run
DRY_RUN=0
case "${1:-}" in
    "")        ;;
    --dry-run) DRY_RUN=1 ;;
    *)         echo "Использование: $0 [--dry-run]" >&2; exit 1 ;;
esac

# 2. Проверки по требованиям 4 и 5
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: нет файла ${LOCAL_DIR}index.html, доставка отменена" >&2
    exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
    echo "Ошибка: в репозитории есть незафиксированные изменения, доставка отменена:" >&2
    git status --short >&2
    exit 1
fi

COMMIT="$(git rev-parse --short HEAD)"

# 3. Синхронизация каталога ${LOCAL_DIR} на ${REMOTE}:${REMOTE_DIR}
# Одно SSH-соединение за запуск; BatchMode исключает запрос пароля
RSYNC_OPTS=(-avz --delete --chmod=D755,F644 -e "ssh -o BatchMode=yes -o ConnectTimeout=5")
if [[ $DRY_RUN -eq 1 ]]; then
    RSYNC_OPTS+=(--dry-run)
    echo "Пробный запуск: план доставки коммита ${COMMIT}"
else
    echo "Доставка коммита ${COMMIT} на ${REMOTE}:${REMOTE_DIR}"
fi

if ! rsync "${RSYNC_OPTS[@]}" "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"; then
    echo "Ошибка: синхронизация не выполнена" >&2
    exit 1
fi

# 4. При --dry-run — завершение с кодом 0 без проверки доступности
if [[ $DRY_RUN -eq 1 ]]; then
    echo "Пробный запуск завершён, состояние сервера не изменено"
    exit 0
fi

# 5. Проверка доступности ${SITE_URL} с проверкой сертификата
if ! curl -fsS --cacert "${CA_CERT}" --max-time 10 -o /dev/null "${SITE_URL}/"; then
    echo "Ошибка: ресурс ${SITE_URL} недоступен после доставки" >&2
    exit 1
fi

echo "Деплой выполнен: коммит ${COMMIT}, ресурс ${SITE_URL} доступен"
