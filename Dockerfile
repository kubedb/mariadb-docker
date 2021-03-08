FROM mariadb:10.4.17

VOLUME /etc/mysql

COPY on-start.sh /
COPY peer-finder /usr/local/bin/
