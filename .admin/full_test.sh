#!/bin/sh
#
# Runs through tests of the full flow and project
#
DATACENTER=dc1
OUTPUT=.admin/test.out

#startDockerCassandra name version
#Start up open source cassandra for the given version
startDockerCassandra() {
  echo "---------------------------------------------"
  echo "Starting Cassandra Docker (30 second pause to startup)"
  echo "---------------------------------------------"
  docker run --rm  -p 9042:9042 -d -e CASSANDRA_DC=$DATACENTER --label casquatch_test=$1 --name $1 -d cassandra:$2
  if [ $? -eq 0 ]; then
    retryLoop "docker exec -it $1 nodetool status 2>/dev/null | grep rack1 | grep -q 'UN'" 120
  else
    $?
  fi;
}

#startDockerDSE name version
#Start up datastax cassandra with solr enabled for the given version
startDockerDSE() {
  echo "---------------------------------------------"
  echo "Starting DSE Docker"
  echo "---------------------------------------------"
  docker run --rm -e DS_LICENSE=accept -p 9042:9042 -p 9142:9142 -d --name $1 -h dse.local --label casquatch_test=$1 -d datastax/dse-server:$2 -s
  if [ $? -eq 0 ]; then
    retryLoop "docker exec -it $1 dsetool status 2>/dev/null | grep rack1 | grep -q 'UN'" 120
  else
    $?
  fi;
}

#configureDSESSL name
#Configure SSL on DSE
configureDSESSL() {
  echo "---------------------------------------------"
  echo "Configure SSL"
  echo "---------------------------------------------"
  export TRUSTSTORE_PATH=`pwd`/.admin/dsessl/.truststore
  docker cp .admin/dsessl/.keystore $1:/opt/dse/resources/dse/conf/.keystore
  docker cp .admin/dsessl/.truststore $1:/opt/dse/resources/dse/conf/.truststore
  docker cp .admin/dsessl/cassandra.yaml.$2 $1:/opt/dse/resources/cassandra/conf/cassandra.yaml
  cp .admin/dsessl/client.truststore config/client.truststore
  docker restart $1
  retryLoop "docker exec -it $1 dsetool status 2>/dev/null | grep rack1 | grep -q 'UN'" 120
}

#installKeyspace name
#install the base keyspace
installKeyspace() {
  echo "---------------------------------------------"
  echo "Installing Keyspace"
  echo "---------------------------------------------"
  docker exec -i $1 cqlsh << EOF
CREATE KEYSPACE IF NOT EXISTS installTest WITH replication = { 'class' : 'SimpleStrategy', 'replication_factor' : 1}  AND durable_writes = true;
CREATE TYPE IF NOT EXISTS installTest.test_udt (val1 text, val2 int);
CREATE TABLE IF NOT EXISTS installTest.test_udt_table (id uuid primary key, udt frozen<test_udt>);
CREATE TABLE IF NOT EXISTS installTest.table_name (key_one int,key_two int,col_one text,col_two text,PRIMARY KEY ((key_one, key_two)));
EOF
}

#installSpringKeyspace name
#install the spring keyspace
installSpringKeyspace() {
  echo "---------------------------------------------"
  echo "Installing Spring Keyspace"
  echo "---------------------------------------------"
  docker exec -i $1 cqlsh << EOF
CREATE KEYSPACE IF NOT EXISTS springconfig WITH replication = { 'class' : 'SimpleStrategy', 'replication_factor' : 1}  AND durable_writes = true;
CREATE TABLE IF NOT EXISTS springconfig.configuration (application text,profile text,label text,key text,value text,PRIMARY KEY ((application, profile), label, key)) WITH CLUSTERING ORDER BY (label ASC, key ASC);
INSERT INTO springconfig.configuration (application,profile,label,key,value) values ('app','test','labelname','keyname','valuevalue');
EOF
}

#configureDriver keyspace
#Configure casquatch driver for the keyspace
configureDriver() {
  echo "---------------------------------------------"
  echo "Configure driver"
  echo "---------------------------------------------"
  mkdir config 2>>$OUTPUT
cat << EOF > config/application.properties
cassandraDriver.contactPoints=localhost
cassandraDriver.localDC=$DATACENTER
cassandraDriver.keyspace=$1
cassandraDriver.features.driverConfig=disabled
EOF
  if [ "$1" == "springconfig" ]; then
  cat << EOF >> config/application.properties
security.user.name=test
security.user.password=test
server.port=8888
EOF
  fi;
}

#runTests package test
#runs a speciifc junit test
runTests() {
  echo "---------------------------------------------"
  echo "Run Tests $1:$2"
  echo "---------------------------------------------"
  mvn -pl $1 -q -Dtest=$2 test
}

#startSpringConfig
#Start up spring config server and wait for it to come up
startSpringConfig() {
  echo "---------------------------------------------"
  echo "Starting Spring Config"
  echo "---------------------------------------------"
  nohup mvn -pl springconfigserver spring-boot:run > nohup.out 2>&1 &
  retryLoop "grep -q 'Started Application' nohup.out" 120
}

#cleanup name
#Kill apps and docker instances. Cleans up folders
cleanup() {
  echo "---------------------------------------------"
  echo "Cleanup"
  echo "---------------------------------------------"
  pkill -f  cassandragenerator
  pkill -f  springconfig
  docker ps -flabel=casquatch_test -q | xargs -I % docker kill %
  docker container ls -al -flabel=casquatch_test -q | xargs -I % docker rm %
  mvn clean
  mvn -f pom_install.xml -pl cassandramodels -q clean install
  rm -rf cassandramodels
  rm -rf config/application.properties
}

#testSpringConfig
#Test the running spring config server
testSpringConfig() {
  echo "---------------------------------------------"
  echo "Pulling test config. Should be keyname: valuevalue"
  echo "---------------------------------------------"
  curl -s -u test:test http://localhost:8888/app-test.yml | grep -q "keyname: valuevalue"
  #curl -u test:test http://localhost:8888/app/test/labelname
}

#showStatus returnCode
#Shows return code as a colored status
showStatus() {
  RED="\033[1;31m"
  GREEN="\033[1;32m"
  NOCOLOR="\033[0m"
  if [ $1 -eq 0 ]; then
    echo "${GREEN}[Success]${NOCOLOR}"
  else
    echo "${RED}[Fail]${NOCOLOR}"
    exit;
  fi
}

#retryLoop command timeout
#Run the command until it succeeds or hits the timeout
retryLoop() {
  command=$1
  timeout=$2
  lc=0
  retcode=-1
  sleep=5
  until [ $retcode -eq 0 ]; do
    if [ $lc -gt $((timeout/sleep)) ]; then
      return 1
    fi;
    lc=$((lc+1))
    sleep $sleep;
    eval $command
    retcode=$?
  done;
  sleep $((sleep*2))
}

#buildGenerator
#compiles the generator
buildGenerator() {
  mvn -f pom.xml -pl cassandragenerator -q clean package
}


#generateModels
#Generates the downloaded models
generateModels() {
  java -jar cassandragenerator/target/CassandraGenerator-*.jar  --keyspace=installTest --datacenter=$DATACENTER --package --output=cassandramodels
  mvn -f pom_install.xml -pl cassandramodels -q clean install
}

#installCasquatch
installCasquatch() {
  mvn -q clean install
}

#basicTestSuite name
#Runs the basic junit test suite
basicTestSuite() {
  echo "[$1][Install Casqutch]" \\c
  installCasquatch >> $OUTPUT 2>&1
  showStatus $?

  echo "[$1][Run Docker Tests]" \\c
  runTests cassandradriver CassandraDriverDockerTests >> $OUTPUT 2>&1
  showStatus $?
}

#generatorTestSuite
#Test suite for code generator
generatorTestSuite() {
  echo "[$1][Install Keyspace]" \\c
  installKeyspace $1 >> $OUTPUT 2>&1
  showStatus $?

  echo "[$1][Build Generator]" \\c
  buildGenerator >> $OUTPUT 2>&1
  showStatus $?

  echo "[$1][Generate Models]" \\c
  generateModels >> $OUTPUT 2>&1
  showStatus $?

}

#springTestSuite
#test suite for spring
springTestSuite() {

  echo "[$1][Install Spring Config Server Keyspace]" \\c
  installSpringKeyspace $1 >> $OUTPUT 2>&1
  showStatus $?

  echo "[$1][Configure Driver - Spring Config Server]" \\c
  configureDriver springconfig >> $OUTPUT 2>&1
  showStatus $?

  echo "[$1][Start Spring Config Server]" \\c
  startSpringConfig >> $OUTPUT 2>&1
  showStatus $?

  echo "[$1][Test Spring Config Server]" \\c
  testSpringConfig >> $OUTPUT 2>&1
  showStatus $?
}

#solrTestSuite
#test suite for solr
solrTestSuite() {
  echo "[$1][Run JUnit Solr Tests]" \\c
  runTests cassandradriver CassandraDriverDockerSolrTests >> $OUTPUT 2>&1
  showStatus $?
}

#sslTestSuite
#test suite for DSE SSL
sslTestSuite() {
  echo "[$1][Config SSL]" \\c
  configureDSESSL $1 $version >> $OUTPUT 2>&1
  showStatus $?

  echo "[$1][Run JUnit SSL Tests]" \\c
  export MAVEN_OPTS="-Djavax.net.ssl.trustStorePassword=cassandra -Djavax.net.ssl.trustStore=$TRUSTSTORE_PATH -Djavax.net.ssl.trustStoreType=jks"
  runTests cassandradriver CassandraDriverDockerSSLTests >> $OUTPUT 2>&1
  showStatus $?
}

#embeddedTests
#basic embeded tests
embeddedTests() {
  echo "[Embedded][Install Casqutch]" \\c
  installCasquatch >> $OUTPUT 2>&1
  showStatus $?

  echo "[Embedded][Run JUnitTests]" \\c
  runTests cassandradriver CassandraDriverEmbeddedTests >> $OUTPUT 2>&1
  showStatus $?
}

#cassandraTests version
#run all tests for open source cassandra on the specified version
cassandraTests() {
  version=$1
  container="Cassandra-"$version

  echo "[$container][Cleanup]" \\c
  cleanup $container >> $OUTPUT 2>&1
  showStatus $?

  echo "[$container][Start Docker]" \\c
  startDockerCassandra $container $version >> $OUTPUT 2>&1
  showStatus $?

  basicTestSuite  $container
  generatorTestSuite $container
  springTestSuite $container

  echo "[$container][Cleanup]" \\c
  cleanup $container >> $OUTPUT 2>&1
  showStatus $?
}

#dseTests version
#run all tests for datastax cassandra on the specified version
dseTests() {
  version=$1
  container="DSE-"$version

  echo "[$container][Cleanup]" \\c
  cleanup $container >> $OUTPUT 2>&1
  showStatus $?

  echo "[$container][Start Docker]" \\c
  startDockerDSE $container $version >> $OUTPUT 2>&1
  showStatus $?

  basicTestSuite $container
  generatorTestSuite $container
  springTestSuite $container
  solrTestSuite $container
  sslTestSuite $container

  echo "[$container][Run JUnit Enterprise Driver Tests]" \\c
  runTests cassandradriver-ee CassandraDriverEEDockerTests >> $OUTPUT 2>&1
  showStatus $?

  echo "[$container][Cleanup]" \\c
  cleanup $container >> $OUTPUT 2>&1
  showStatus $?
}

#Run all tests
embeddedTests
cassandraTests 3.0
cassandraTests 3.11
dseTests 5.1.12
dseTests 6.0.4
dseTests 6.7.0
