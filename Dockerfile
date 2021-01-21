FROM mariadb:10.5

VOLUME /etc/mysql

COPY on-start.sh /
COPY peer-finder /usr/local/bin/