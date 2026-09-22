#!/bin/bash

BACKUP_DIR="${BACKUP_DIR:-/backup}"     # куда класть архив (по умолчанию /backup)

fail() {
    echo "ОШИБКА: $1" >&2
    exit "$2"
}

get_percent() {
    df --output=pcent "$LOG_DIR" | tail -n 1 | tr -d ' %'
}

if [ $# -ne 3 ]; then
    fail "нужно 3 аргумента, а передано $#. Пример: $0 /log 80 5" 1
fi

LOG_DIR="$1"
N="$2"
M="$3"

if ! [ "$N" -ge 0 ] 2>/dev/null || ! [ "$N" -le 99 ] 2>/dev/null; then
    fail "N='$N' - нужно целое число от 0 до 99 (порог заполнения в %)" 2
fi
if ! [ "$M" -ge 1 ] 2>/dev/null; then
    fail "M='$M' - нужно целое число от 1 (сколько файлов архивировать)" 3
fi
if [ ! -d "$LOG_DIR" ]; then
    fail "'$LOG_DIR' не существует или это не папка" 4
fi
if [ ! -r "$LOG_DIR" ]; then
    fail "нет прав на чтение '$LOG_DIR' (попробуйте sudo)" 4
fi
if ! mountpoint -q "$LOG_DIR"; then
    fail "'$LOG_DIR' не отдельный раздел ограниченного размера (его нужно смонтировать)" 5
fi
case "$BACKUP_DIR" in
    "$LOG_DIR" | "$LOG_DIR"/*)
        fail "папка бэкапа '$BACKUP_DIR' находится внутри '$LOG_DIR'" 6
        ;;
esac

PERCENT=$(get_percent)
if ! [ "$PERCENT" -ge 0 ] 2>/dev/null; then
    fail "не удалось узнать заполнение '$LOG_DIR'" 7
fi
echo "Заполнено: ${PERCENT}% (порог: ${N}%)"

if ! [ "$PERCENT" -gt "$N" ]; then
    echo "Заполнено не больше ${N}%, архивация не нужна."
    exit 0
fi

FILES=$(ls -tr "$LOG_DIR" | grep '\.log' | head -n "$M")
if [ -z "$FILES" ]; then
    echo "В '$LOG_DIR' нет файлов *.log, архивировать нечего."
    exit 0
fi
COUNT=$(echo "$FILES" | wc -l)
echo "Архивирую файлов: $COUNT"

if ! mkdir -p "$BACKUP_DIR" 2>/dev/null; then
    fail "не удалось создать папку '$BACKUP_DIR' (попробуйте sudo)" 8
fi
ARCHIVE="$BACKUP_DIR/logs_$(date +%Y%m%d_%H%M%S).tar.gz"

if ! tar -czf "$ARCHIVE" -C "$LOG_DIR" $FILES; then
    rm -f "$ARCHIVE"
    fail "не удалось создать архив '$ARCHIVE', файлы не тронуты" 9
fi

if ! tar -tzf "$ARCHIVE" > /dev/null 2>&1; then
    rm -f "$ARCHIVE"
    fail "архив повреждён, файлы не тронуты" 9
fi

cd "$LOG_DIR" && rm -f $FILES

echo "Архив: $ARCHIVE"
echo "После архивации заполнено: $(get_percent)%"
