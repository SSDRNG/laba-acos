#!/bin/bash

SCRIPT="./log_archiver.sh"
TEST_DIR="/tmp/test_log_env"
IMG="$TEST_DIR/log.img"
MOUNT_POINT="$TEST_DIR/log"
BACKUP_DIR="$TEST_DIR/backup"

PASS=0
FAIL=0

check() {
    if [ "$2" -eq "$3" ]; then
        echo "ok: $1 (код $3)"
        PASS=$((PASS + 1))
    else
        echo "bad: $1 (ждали $2, получили $3)"
        FAIL=$((FAIL + 1))
    fi
}

setup() {
    echo "setup..."
    mkdir -p "$TEST_DIR"
    truncate -s 10M "$IMG"
    sudo mkfs.ext4 -q "$IMG"
    mkdir -p "$MOUNT_POINT"
    sudo mount -o loop "$IMG" "$MOUNT_POINT"
    sudo chown $USER "$MOUNT_POINT"
    mkdir -p "$BACKUP_DIR"
    echo "done"
}

cleanup() {
    echo "cleanup..."
    sudo umount "$MOUNT_POINT" 2>/dev/null
    rm -rf "$TEST_DIR"
}

run_test() {
    local desc="$1"
    local expected="$2"
    shift 2
    "$SCRIPT" "$@" > /dev/null 2>&1
    local code=$?
    check "$desc" "$expected" "$code"
}

setup

run_test "0 арг" 1
run_test "1 арг" 1 "$MOUNT_POINT"
run_test "2 арг" 1 "$MOUNT_POINT" 80
run_test "4 арг" 1 "$MOUNT_POINT" 80 5 extra

run_test "N=abc" 2 "$MOUNT_POINT" abc 5
run_test "N=-1" 2 "$MOUNT_POINT" -1 5
run_test "N=100" 2 "$MOUNT_POINT" 100 5

run_test "M=0" 3 "$MOUNT_POINT" 80 0
run_test "M=abc" 3 "$MOUNT_POINT" 80 abc

run_test "нет папки" 4 "/nonexistent_dir_xyz" 80 5

mkdir -p "$TEST_DIR/plain"
run_test "не маунтпоинт" 5 "$TEST_DIR/plain" 80 5

export BACKUP_DIR="$MOUNT_POINT/backup"
run_test "бэкап внутри лога" 6 "$MOUNT_POINT" 80 5
export BACKUP_DIR="$TEST_DIR/backup"

rm -f "$MOUNT_POINT"/*.log
echo "test" > "$MOUNT_POINT/a.log"
run_test "порог не превышен" 0 "$MOUNT_POINT" 99 5
if [ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]; then
    echo "ok: архива нет (и не надо)"
    PASS=$((PASS + 1))
else
    echo "bad: архив создался зря"
    FAIL=$((FAIL + 1))
fi

rm -f "$MOUNT_POINT"/*.log
echo "old1" > "$MOUNT_POINT/old1.log"
sleep 1
echo "old2" > "$MOUNT_POINT/old2.log"
sleep 1
echo "old3" > "$MOUNT_POINT/old3.log"
sleep 1
echo "new1" > "$MOUNT_POINT/new1.log"
run_test "архивация" 0 "$MOUNT_POINT" 0 2
ARCHIVE=$(ls "$BACKUP_DIR"/logs_*.tar.gz 2>/dev/null | head -n 1)
if [ -n "$ARCHIVE" ]; then
    echo "ok: архив есть"
    PASS=$((PASS + 1))
    COUNT=$(tar -tzf "$ARCHIVE" | wc -l)
    if [ "$COUNT" -eq 2 ]; then
        echo "ok: файлов 2"
        PASS=$((PASS + 1))
    else
        echo "bad: файлов $COUNT"
        FAIL=$((FAIL + 1))
    fi
    if [ ! -f "$MOUNT_POINT/old1.log" ] && [ ! -f "$MOUNT_POINT/old2.log" ]; then
        echo "ok: старые удалены"
        PASS=$((PASS + 1))
    else
        echo "bad: старые не удалены"
        FAIL=$((FAIL + 1))
    fi
    if [ -f "$MOUNT_POINT/old3.log" ] && [ -f "$MOUNT_POINT/new1.log" ]; then
        echo "ok: новые на месте"
        PASS=$((PASS + 1))
    else
        echo "bad: новые пропали"
        FAIL=$((FAIL + 1))
    fi
else
    echo "bad: архива нет"
    FAIL=$((FAIL + 1))
fi

rm -f "$MOUNT_POINT"/*.log
run_test "нет логов" 0 "$MOUNT_POINT" 0 5

cleanup

echo "итог: ok=$PASS, bad=$FAIL"
if [ "$FAIL" -eq 0 ]; then
    exit 0
else
    exit 1
fi
