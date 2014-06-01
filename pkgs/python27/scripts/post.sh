grep -q '/usr/local/lib' /etc/ld.so.conf.d/* && exit 0 

echo '/usr/local/lib' > /etc/ld.so.conf.d/liblocal.conf && /sbin/ldconfig

