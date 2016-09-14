[![](https://badge.imagelayers.io/flowman/percona-xtradb-cluster:latest.svg)](https://imagelayers.io/?images=flowman/percona-xtradb-cluster:latest 'Get your own badge on imagelayers.io')

# What is Percona XtraDB Cluster?

Percona XtraDB Cluster is High Availability and Scalability solution for MySQL Users. Percona XtraDB Cluster provides: Synchronous replication. Transaction either commited on all nodes or none. Multi-master replication.

## Info

This container is not meant to be run standalone as it is part of a [Rancher](http://rancher.com) Catalog item. If it suites your purpose you are more then welcome to use it.

## Environment Variables

When you start the pxc image, you can adjust the configuration of the pxc instance by passing one or more environment variables on the docker run command line. Do note that none of the variables below will have any effect if you start the container with a data directory that already contains a database: any pre-existing database will always be left untouched on container startup.

`MYSQL_ROOT_PASSWORD`

This variable is mandatory and specifies the password that will be set for the root superuser account.

`PXC_SST_PASSWORD`

This variable is mandatory and specifies the password that will be set for the sst account.

`MYSQL_DATABASE`

This variable is optional and allows you to specify the name of a database to be created on image startup. If a user/password was supplied (see below) then that user will be granted superuser access (corresponding to GRANT ALL) to this database.

`MYSQL_USER, MYSQL_PASSWORD`

These variables are optional, used in conjunction to create a new user and to set that user's password. This user will be granted superuser permissions (see above) for the database specified by the `MYSQL_DATABASE` variable. Both variables are required for a user to be created.

Do note that there is no need to use this mechanism to create the root superuser, that user gets created by default with the password specified by the `MYSQL_ROOT_PASSWORD` variable.

`MYSQL_ALLOW_EMPTY_PASSWORD`

This is an optional variable. Set to yes to allow the container to be started with a blank password for the root user. NOTE: Setting this variable to yes is not recommended unless you really know what you are doing, since this will leave your Percona instance completely unprotected, allowing anyone to gain complete superuser access.

## Usage

## ... via `docker-compose`

Example Rancher docker-compose stack

```yaml
pxc:
  image: flowman/percona-xtradb-cluster-confd:v0.2.0
  labels:
    io.rancher.sidekicks: pxc-clustercheck,pxc-server,pxc-data
    io.rancher.scheduler.affinity:container_label_soft_ne: io.rancher.stack_service.name=$${stack_name}/$${service_name}
  volumes_from:
    - 'pxc-data'
pxc-clustercheck:
  image: flowman/percona-xtradb-cluster-clustercheck:v2.0
  net: "container:pxc"
pxc-server:
  image: flowman/percona-xtradb-cluster:5.6.28-1
  net: "container:pxc"
  environment:
    MYSQL_ROOT_PASSWORD: "password"
    PXC_SST_PASSWORD: "password"
  volumes_from:
    - 'pxc-data'
  entrypoint: bash -x /opt/rancher/start_pxc
pxc-data:
  image: flowman/percona-xtradb-cluster:5.6.28-1
  net: none
  environment:
    MYSQL_ALLOW_EMPTY_PASSWORD: "yes"
  volumes:
    - /var/lib/mysql
    - /etc/mysql/conf.d
    - /docker-entrypoint-initdb.d
  command: /bin/true
  labels:
    io.rancher.container.start_once: true
```

Example rancher-compose for monitoring pxc

```yaml
pxc:
  scale: 3
  health_check:
    port: 8000
    interval: 2000
    unhealthy_threshold: 3
    strategy: none
    request_line: GET / HTTP/1.1
    healthy_threshold: 2
    response_timeout: 2000
  metadata:
    mysqld: |
      innodb_buffer_pool_size=512M
      innodb_doublewrite=0
      innodb_flush_log_at_trx_commit=0
      innodb_file_per_table=1
      innodb_log_file_size=128M
      innodb_log_buffer_size=64M
      innodb_support_xa=0
      query_cache_size=0
      query_cache_type=0
      sync_binlog=0
      max_connections=1000
      wsrep_sst_auth=sstuser:password
```

## Build

For example, if you need to change anything, edit the Dockerfile and than build-it.

```bash
git clone git@github.com:Flowman/percona-xtradb-cluster.git
cd ./percona-xtradb-cluster
docker build --rm -t flowman/percona-xtradb-cluster .
```