#!/bin/bash

# should get environment var from docker image / container:
# ${CATALINA_HOME} = /usr/local/tomcat
# SOLR_DIR_ROOT=${SOLR_DIR_ROOT:-'/opt/alfresco/solr4'}

set -e

JAVA_XMS=${JAVA_XMS:-'512M'}
JAVA_XMX=${JAVA_XMX:-'2048M'}
DEBUG=${DEBUG:-'false'}
JMX_ENABLED=${JMX_ENABLED:-'false'}
JMX_RMI_HOST=${JMX_RMI_HOST:-'0.0.0.0'}

CONFIG_FILE_SOLR_WORKSPACE=$SOLR_DIR_ROOT'/workspace-SpacesStore/conf/solrcore.properties'
CONFIG_FILE_SOLR_ARCHIVE=$SOLR_DIR_ROOT'/archive-SpacesStore/conf/solrcore.properties'
CONFIG_FILE_SOLR_SCHEMA_WORKSPACE=$SOLR_DIR_ROOT'/workspace-SpacesStore/conf/schema.xml'
TOMCAT_CONFIG_FILE=${CATALINA_HOME}'/bin/setenv.sh'
TOMCAT_SERVER_FILE=${CATALINA_HOME}'/conf/server.xml'

ALFRESCO_SSL=${ALFRESCO_SSL:-'https'}

SHARDING=${SHARDING:-'false'}
NUM_SHARDS=${NUM_SHARDS:-'3'}
NUM_NODES=${NUM_NODES:-'2'}
NODE_INSTANCE=${NODE_INSTANCE:-'1'}
TEMPLATE=${TEMPLATE:-'rerank'}
REPLICATION_FACTOR=${REPLICATION_FACTOR:-'1'}
SHARD_IDS=${SHARD_IDS:-'0,1'}

ALFRESCO_SOLR_SUGGESTER_ENABLED=${ALFRESCO_SOLR_SUGGESTER_ENABLED:-'true'}
ALFRESCO_SOLR_FACETABLE_CATEGORIES_ENABLED=${ALFRESCO_SOLR_FACETABLE_CATEGORIES_ENABLED:-'false'}

# sets an Alfresco / Tomcat parameter as a JAVA_OPTS parameter
# the key is ignored, the value should contain the "-D" flag if it's a property
function setJavaOption {
    JAVA_OPTS="$JAVA_OPTS $2"
}

function setJavaOptions {
    IFS=$'\n'
    for i in `env`
    do
	if [[ $i == JAVA_OPTS_* ]]
	    then
	    key=`echo $i | cut -d '=' -f 1 | cut -d '_' -f 3-`
	    value=`echo $i | cut -d '=' -f 2-`
	    setJavaOption $key $value
	fi
    done
}

function setOption {
    if grep --quiet -e "$1\s*=" "$3"; then
        # replace option
        sed -i "s#^\($1\s*=\s*\).*\$#\1$2#" $3
	    sed -i "s#^\#\($1\s*=\s*\).*\$#\1$2#" $3
        if (( $? )); then
            echo "setOption failed (replacing option $1=$2 in $3)"
            exit 1
        fi
    else
        # add option if it does not exist
        echo "$1=$2" >> $3
    fi
}

function setGlobalOptions {
    file=$1
    coreName=$2
    IFS=$'\n'
    for i in `env`
    do
        if [[ $i == GLOBAL_WORKSPACE_* ]]
        then
            if [ $coreName = alfresco ]
	        then
                key=`echo $i | cut -d '=' -f 1 | cut -d '_' -f 3-`
                value=`echo $i | cut -d '=' -f 2-`
                setOption $key $value "$file"
            fi
        elif [[ $i == GLOBAL_ARCHIVE_* ]]
        then
            if [ $coreName = archive ]
	        then
                key=`echo $i | cut -d '=' -f 1 | cut -d '_' -f 3-`
                value=`echo $i | cut -d '=' -f 2-`
                setOption $key $value "$file"
            fi
        elif [[ $i == GLOBAL_* ]]
        then
           key=`echo $i | cut -d '=' -f 1 | cut -d '_' -f 2-`
           value=`echo $i | cut -d '=' -f 2-`
           setOption $key $value "$file"
        fi
    done
}


# workspace core file might not exist (if sharded index)
if [ -f "$CONFIG_FILE_SOLR_WORKSPACE" ]
then
  setOption 'alfresco.host' "${ALFRESCO_HOST:-localhost}" "$CONFIG_FILE_SOLR_WORKSPACE"
  setOption 'alfresco.port' "${ALFRESCO_PORT:-8080}" "$CONFIG_FILE_SOLR_WORKSPACE"
  setOption 'alfresco.port.ssl' "${ALFRESCO_PORT_SSL:-8443}" "$CONFIG_FILE_SOLR_WORKSPACE"
  setOption 'alfresco.secureComms' "${ALFRESCO_SSL:-https}" "$CONFIG_FILE_SOLR_WORKSPACE"
  setOption 'enable.alfresco.tracking' "${ALFRESCO_ENABLE_TRACKING:-true}" "$CONFIG_FILE_SOLR_WORKSPACE"
  setOption 'alfresco.index.transformContent' "${ALFRESCO_INDEX_CONTENT:-true}" "$CONFIG_FILE_SOLR_WORKSPACE"
  setOption 'alfresco.corePoolSize' "${ALFRESCO_CORE_POOL_SIZE:-8}" "$CONFIG_FILE_SOLR_WORKSPACE"
  setOption 'solr.suggester.enabled' "${ALFRESCO_SOLR_SUGGESTER_ENABLED:-true}" "$CONFIG_FILE_SOLR_WORKSPACE"

  setGlobalOptions "$CONFIG_FILE_SOLR_WORKSPACE" alfresco
fi

if [ -f "$CONFIG_FILE_SOLR_ARCHIVE" ]
then
  setOption 'alfresco.host' "${ALFRESCO_HOST:-localhost}" "$CONFIG_FILE_SOLR_ARCHIVE"
  setOption 'alfresco.port' "${ALFRESCO_PORT:-8080}" "$CONFIG_FILE_SOLR_ARCHIVE"
  setOption 'alfresco.port.ssl' "${ALFRESCO_PORT_SSL:-8443}" "$CONFIG_FILE_SOLR_ARCHIVE"
  setOption 'alfresco.secureComms' "${ALFRESCO_SSL:-https}" "$CONFIG_FILE_SOLR_ARCHIVE"
  setOption 'enable.alfresco.tracking' "${ARCHIVE_ENABLE_TRACKING:-true}" "$CONFIG_FILE_SOLR_ARCHIVE"
  setOption 'alfresco.index.transformContent' "${ARCHIVE_INDEX_CONTENT:-true}" "$CONFIG_FILE_SOLR_ARCHIVE"

  setGlobalOptions "$CONFIG_FILE_SOLR_ARCHIVE" archive
fi

if [ -f "$CONFIG_FILE_SOLR_SCHEMA_WORKSPACE" ]
then
  if [ $ALFRESCO_SOLR_SUGGESTER_ENABLED = true ]
  then
    sed -i 's/.*\(<copyField source="suggest_\*" dest="suggest" \/>\).*/\1/g' "$CONFIG_FILE_SOLR_SCHEMA_WORKSPACE"
  else
    sed -i 's/.*\(<copyField source="suggest_\*" dest="suggest" \/>\).*/<!--\1-->/g' "$CONFIG_FILE_SOLR_SCHEMA_WORKSPACE"
  fi
  if [ $ALFRESCO_SOLR_FACETABLE_CATEGORIES_ENABLED = true ]
  then
    sed -i 's/\(.*<dynamicField.*name="\(category\|noderef\)@m_.*type="\)\(oldStandardAnalysis\)\(".*\)\(\/\)\(.*\)/\1identifier\4docValues="true" \/\6/g' "$CONFIG_FILE_SOLR_SCHEMA_WORKSPACE"
    sed -i 's/\(.*<dynamicField.*name="\(category\|noderef\)@s_.*type="\)\(oldStandardAnalysis\)\(".*\)\(sortMissingLast="true"\)\(.*\)/\1identifier\4docValues="true"\6/g' "$CONFIG_FILE_SOLR_SCHEMA_WORKSPACE"
  fi
fi

if [ $ALFRESCO_SSL = none ]
then
sed -i '/<Connector port="\${TOMCAT_PORT_SSL}" URIEncoding="UTF-8" protocol="org.apache.coyote.http11.Http11Protocol" SSLEnabled="true"/,+5d' $TOMCAT_SERVER_FILE
fi

# Tomcat-related properties
# for backwards compatibility, we keep some of the old options as well
setJavaOption 'TOMCAT_PORT' '-DTOMCAT_PORT='${TOMCAT_PORT:-8080}
setJavaOption 'TOMCAT_PORT_SSL' '-DTOMCAT_PORT_SSL='${TOMCAT_PORT_SSL:-8443}
setJavaOption 'TOMCAT_AJP_PORT' '-DTOMCAT_AJP_PORT='${TOMCAT_AJP_PORT:-8009}
setJavaOption 'TOMCAT_SERVER_PORT' '-DTOMCAT_SERVER_PORT='${TOMCAT_SERVER_PORT:-8005}
BC_TOMCAT_MAX_HTTP_HEADER_SIZE=${TOMCAT_MAX_HTTP_HEADER_SIZE:-$MAX_HTTP_HEADER_SIZE}
setJavaOption 'TOMCAT_MAX_HTTP_HEADER_SIZE' '-DTOMCAT_MAX_HTTP_HEADER_SIZE='${BC_TOMCAT_MAX_HTTP_HEADER_SIZE:-32768}
BC_TOMCAT_MAX_THREADS=${TOMCAT_MAX_THREADS:-$MAX_THREADS}
setJavaOption 'TOMCAT_MAX_THREADS' '-DTOMCAT_MAX_THREADS='${BC_TOMCAT_MAX_THREADS:-200}


if [ $JMX_ENABLED = true ]
then
    JAVA_OPTS="$JAVA_OPTS -Xms$JAVA_XMS -Xmx$JAVA_XMX -Dfile.encoding=UTF-8 -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.rmi.port=5000 -Dcom.sun.management.jmxremote.port=5000 -Djava.rmi.server.hostname=$JMX_RMI_HOST"
else
    JAVA_OPTS="$JAVA_OPTS -Xms$JAVA_XMS -Xmx$JAVA_XMX -Dfile.encoding=UTF-8"
fi

if [ $DEBUG = true ]
then
    JAVA_OPTS="$JAVA_OPTS -Xdebug -Xrunjdwp:transport=dt_socket,address=8000,server=y,suspend=n"
fi

setJavaOptions
echo "JAVA_OPTS=\""\$JAVA_OPTS" $JAVA_OPTS\"" >$TOMCAT_CONFIG_FILE
echo "export JAVA_OPTS" >> $TOMCAT_CONFIG_FILE

appStart () {
  if [[ $(stat -c %U /opt/alfresco/alf_data) != 'tomcat' ]]
  then
      chown -R tomcat:tomcat /opt/alfresco/alf_data
  fi
  gosu tomcat ${CATALINA_HOME}/bin/catalina.sh run
}

appHelp () {
  echo "Available options:"
  echo " app:start    - Start the application"
  echo " app:help     - Displays the help"
  echo " [command]    - Execute the specified linux command eg. bash."
}

case "$1" in
  app:start)
    appStart
    ;;
  app:help)
    appHelp
    ;;
  *)
    if [ -x $1 ]; then
      $1
    else
      prog=$(which $1)
      if [ -n "${prog}" ] ; then
        shift 1
        $prog $@
      else
        appHelp
      fi
    fi
    ;;
esac

exit 0
