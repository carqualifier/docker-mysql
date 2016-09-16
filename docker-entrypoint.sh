#!/bin/bash
set -e

MYSQL_TYPE_USER=$(curl -s -H "X-Vault-Token:$VAULT_TOKEN" http://$VAULT_NODE:8200/v1/secret/internal/carqualifier/mysql/${DB_TYPE}/user/general | jq -r '.data')
MYSQL_TYPE_USERNAME=$(echo $MYSQL_TYPE_USER | jq -r '.username')
MYSQL_TYPE_PASSWORD=$(echo $MYSQL_TYPE_USER | jq -r '.password')

MYSQL_ROOT_USER=$(curl -s -H "X-Vault-Token:$VAULT_TOKEN" http://$VAULT_NODE:8200/v1/secret/internal/carqualifier/mysql/${DB_TYPE}/user/root | jq -r '.data')
MYSQL_ROOT_USERNAME=$(echo $MYSQL_ROOT_USER | jq -r '.username')
MYSQL_ROOT_PASSWORD=$(echo $MYSQL_ROOT_USER | jq -r '.password')

# if command starts with an option, prepend mysqld
if [ "${1:0:1}" = '-' ]; then
	set -- mysqld "$@"
fi

if [ "$1" = 'mysqld' ]; then
	# Get config
	DATADIR="$(mysqld --verbose --help 2>/dev/null | awk '$1 == "datadir" { print $2; exit }')"

	if [ ! -d "$DATADIR/mysql" ] && [ ! -f "/opt/rancher/configured" ]; then
		if [ -z "$MYSQL_ROOT_PASSWORD" -a -z "$MYSQL_ALLOW_EMPTY_PASSWORD" ]; then
			echo >&2 'error: database is uninitialized and MYSQL_ROOT_PASSWORD not set'
			echo >&2 '  Did you forget to add -e MYSQL_ROOT_PASSWORD=... ?'
			exit 1
		fi

		if [ -z "$PXC_SST_PASSWORD" ]; then
			echo >&2 'error: database is uninitialized and PXC_SST_PASSWORD not set'
			echo >&2 '  Did you forget to add -e PXC_SST_PASSWORD=... ?'
			exit 1
		fi

		mkdir -p "$DATADIR"
		chown -R mysql:mysql "$DATADIR"

        sed -i 's/^\(!includedir\)/#\1/' /etc/mysql/my.cnf

		echo 'Initializing database'
		mysql_install_db --user=mysql --datadir="$DATADIR" --rpm
		echo 'Database initialized'

		"$@" --skip-networking &
		pid="$!"

		mysql=( mysql --protocol=socket -uroot )

		for i in {30..0}; do
			if echo 'SELECT 1' | "${mysql[@]}" &> /dev/null; then
				break
			fi
			echo 'MySQL init process in progress...'
			sleep 1
		done
		if [ "$i" = 0 ]; then
			echo >&2 'MySQL init process failed.'
			exit 1
		fi

		if [ -z "$MYSQL_INITDB_SKIP_TZINFO" ]; then
			# sed is for https://bugs.mysql.com/bug.php?id=20545
			mysql_tzinfo_to_sql /usr/share/zoneinfo | sed 's/Local time zone must be set--see zic manual page/FCTY/' | "${mysql[@]}" mysql
		fi

		"${mysql[@]}" <<-EOSQL
			-- What's done in this file shouldn't be replicated
			--  or products like mysql-fabric won't work
			SET @@SESSION.SQL_LOG_BIN=0;

			DELETE FROM mysql.user ;
			CREATE USER '${MYSQL_ROOT_USERNAME}'@'%' IDENTIFIED BY '${MYSQL_ROOT_PASSWORD}' ;
			GRANT ALL ON *.* TO '${MYSQL_ROOT_USERNAME}'@'%' WITH GRANT OPTION ;
			DROP DATABASE IF EXISTS test ;
			CREATE USER 'sstuser'@'%' IDENTIFIED BY '${PXC_SST_PASSWORD}' ;
			GRANT RELOAD, LOCK TABLES, REPLICATION CLIENT ON *.* TO 'sstuser'@'%' ;
			GRANT PROCESS ON *.* TO 'clustercheckuser'@'localhost' IDENTIFIED BY 'clustercheckpassword!' ;
			FLUSH PRIVILEGES ;
		EOSQL

		if [ ! -z "$MYSQL_ROOT_PASSWORD" ]; then
			mysql+=( -p"${MYSQL_ROOT_PASSWORD}" )
		fi

		if [ "$MYSQL_DATABASE" ]; then
			echo "CREATE DATABASE IF NOT EXISTS \`$MYSQL_DATABASE\` ;" | "${mysql[@]}"
			mysql+=( "$MYSQL_DATABASE" )
		fi

		if [ "$MYSQL_TYPE_USERNAME" -a "$MYSQL_TYPE_PASSWORD" ]; then
			echo "CREATE USER '$MYSQL_TYPE_USERNAME'@'%' IDENTIFIED BY '$MYSQL_TYPE_PASSWORD' ;" | "${mysql[@]}"

			if [ "$MYSQL_DATABASE" ]; then
				echo "GRANT ALL ON \`$MYSQL_DATABASE\`.* TO '$MYSQL_TYPE_USERNAME'@'%' ;" | "${mysql[@]}"
			fi

			echo 'FLUSH PRIVILEGES ;' | "${mysql[@]}"
		fi

		echo
		for f in /docker-entrypoint-initdb.d/*; do
			case "$f" in
				*.sh)  echo "$0: running $f"; . "$f" ;;
				*.sql) echo "$0: running $f"; "${mysql[@]}" < "$f" && echo ;;
				*)     echo "$0: ignoring $f" ;;
			esac
			echo
		done

		if ! kill -s TERM "$pid" || ! wait "$pid"; then
			echo >&2 'MySQL init process failed.'
			exit 1
		fi

        sed -i '/^#!includedir/{s/^#//}' /etc/mysql/my.cnf

		echo 'MySQL init process done. Ready for start up.'
		echo
	fi

	chown -R mysql:mysql "$DATADIR"
fi

exec "$@"