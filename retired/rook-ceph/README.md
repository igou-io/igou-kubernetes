node cleanup:

```
rm -rf /var/lib/rook
DISK="/dev/sda"
sgdisk --zap-all $DISK
blkdiscard $DISK
ls /dev/mapper/ceph-* | xargs -I% -- dmsetup remove %
rm -rf /dev/ceph-*
```
