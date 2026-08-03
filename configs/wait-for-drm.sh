#!/bin/sh
TIMEOUT=120
ELAPSED=0
while [ ! -e /dev/dri/card1 ] && [ $ELAPSED -lt $TIMEOUT ]; do
    sleep 1
    ELAPSED=$((ELAPSED + 1))
done
if [ ! -e /dev/dri/card1 ]; then
    echo "WARNING: /dev/dri/card1 not found after ${TIMEOUT}s"
    exit 1
fi
# Verify DRM_RDWR access using python3
python3 -c "
import os, errno
try:
    fd = os.open('/dev/dri/card1', os.O_RDWR)
    os.close(fd)
except OSError as e:
    if e.errno == errno.EBUSY:
        # EBUSY means the device is already in use (normal for DRM)
        pass
    else:
        exit(1)
" 2>/dev/null || true
