FROM mariadb:10.5

VOLUME /etc/mysql

COPY on-start.sh /
COPY peer-finder /usr/local/bin/


EXPOSE 3306 4567 4568 4444