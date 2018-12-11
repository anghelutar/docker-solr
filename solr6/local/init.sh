#!/bin/bash

# should get environment var from docker image / container:
# ${SOLR_INSTALL_HOME} = /opt/alfresco-search-services

set -e

SOLR_DIR_ROOT='/opt/alfresco-search-services/solrhome'
SOLR_HOST='localhost'

DEBUG=${DEBUG:-'false'}
ALFRESCO_SSL=${ALFRESCO_SSL:-'https'}
JETTY_PORT=${JETTY_PORT:-'8080'}
JETTY_PORT_SSL=${JETTY_PORT_SSL:-'8443'}
JMX_ENABLED=${JMX_ENABLED:-'false'}
JMX_RMI_HOST=${JMX_RMI_HOST:-'0.0.0.0'}
CORES_TO_TRACK=${CORES_TO_TRACK:-"alfresco;archive"}
IFS=';' read -r -a DEFAULT_CORES <<< "$CORES_TO_TRACK"

if [ $ALFRESCO_SSL != none ]
then
    PORT=$JETTY_PORT_SSL
else
    PORT=$JETTY_PORT
fi    

SHARDING=${SHARDING:-'false'}
NUM_SHARDS=${NUM_SHARDS:-'3'}
NUM_NODES=${NUM_NODES:-'2'}
NODE_INSTANCE=${NODE_INSTANCE:-'1'}
TEMPLATE=${TEMPLATE:-'rerank'}
REPLICATION_FACTOR=${REPLICATION_FACTOR:-'1'}
SHARD_IDS=${SHARD_IDS:-'0,1'}

ALFRESCO_SOLR_SUGGESTER_ENABLED=${ALFRESCO_SOLR_SUGGESTER_ENABLED:-'true'}
ALFRESCO_SOLR_FACETABLE_CATEGORIES_ENABLED=${ALFRESCO_SOLR_FACETABLE_CATEGORIES_ENABLED:-'false'}

JAVA_XMS=${JAVA_XMS:-'512M'}
JAVA_XMX=${JAVA_XMX:-'2048M'}

CONFIG_FILE_SOLR_START="$SOLR_INSTALL_HOME/solr.in.sh"

sed -i 's/log4j.rootLogger=INFO, file, CONSOLE/log4j.rootLogger=ERROR, CONSOLE/' /opt/alfresco-search-services/logs/log4j.properties

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

function escapeFile {
    sed -i "s#:#\:#g" $1
}

function createCoreStatically {
    coreName="$1"
    solrCoreName="$2"
    newCore="$3"

    echo "Creating Alfresco core=$coreName, solrCore=$solrCoreName in $newCore"
    CONFIG_FILE_CORE=$newCore/conf/solrcore.properties
    if [ ! -f  "$newCore" ]
    then
	cp -r ${SOLR_DIR_ROOT}/templates/$TEMPLATE $newCore
	FILE_CORE=$newCore/core.properties
	touch $FILE_CORE
	setOption 'name' "$solrCoreName" "$FILE_CORE"	
    fi
    setOption 'data.dir.root' "${SOLR_DATA_DIR:-/opt/alfresco-search-services/data/index}" "$CONFIG_FILE_CORE"
    setOption 'data.dir.store' "$coreName" "$CONFIG_FILE_CORE"
    setOption 'alfresco.template' "${TEMPLATE}" "$CONFIG_FILE_CORE"
    setOption 'alfresco.host' "${ALFRESCO_HOST:-localhost}" "$CONFIG_FILE_CORE"
    setOption 'alfresco.port' "${ALFRESCO_PORT:-8080}" "$CONFIG_FILE_CORE"
    setOption 'alfresco.port.ssl' "${ALFRESCO_PORT_SSL:-8443}" "$CONFIG_FILE_CORE"
    setOption 'alfresco.secureComms' "$ALFRESCO_SSL" "$CONFIG_FILE_CORE"
}

function makeConfigs {

    for coreName in "${DEFAULT_CORES[@]}"
    do
	newCore=${SOLR_DIR_ROOT}/$coreName
	CONFIG_FILE_CORE=$newCore/conf/solrcore.properties
	
	if [ $coreName = alfresco ]
	then
	    # for sharding - dynamic registration of shards
	    if [ $SHARDING = true ]
	    then
		# assuming we shard the workspace store
		rm -rf ${SOLR_DIR_ROOT}/workspace-SpacesStore
		collectionName=${TEMPLATE}--workspace-SpacesStore--shards--$NUM_SHARDS-x-$REPLICATION_FACTOR--node--$NODE_INSTANCE-of-$NUM_NODES
		echo "collectionName=$collectionName for SHARD_IDS=$SHARD_IDS"
		mkdir -p ${SOLR_DIR_ROOT}/$collectionName
		for i in $(echo $SHARD_IDS | tr "," "\n")
		do
		    coreName=workspace-SpacesStore-$i
		    solrCoreName=alfresco-$i
		    SHARED_PROPERTIES=${SOLR_DIR_ROOT}/conf/shared.properties
		    newCore=${SOLR_DIR_ROOT}/$collectionName/$coreName
		    CONFIG_FILE_CORE=$newCore/conf/solrcore.properties
		    
		    createCoreStatically "$coreName" "$solrCoreName" "$newCore"
		    
		    setOption 'enable.alfresco.tracking' "${ALFRESCO_ENABLE_TRACKING:-true}" "$CONFIG_FILE_CORE"
		    setOption 'alfresco.index.transformContent' "${ALFRESCO_INDEX_CONTENT:-true}" "$CONFIG_FILE_CORE"
		    setOption 'alfresco.corePoolSize' "${ALFRESCO_CORE_POOL_SIZE:-8}" "$CONFIG_FILE_CORE"
		    setOption 'alfresco.doPermissionChecks' "${ALFRESCO_DO_PERMISSION_CHECKS:-true}" "$CONFIG_FILE_CORE"
		    setOption 'solr.suggester.enabled' "$ALFRESCO_SOLR_SUGGESTER_ENABLED" "$CONFIG_FILE_CORE"
		    setOption 'shard.method' "${SHARD_METHOD:-DB_ID}" "$CONFIG_FILE_CORE"
		    setOption 'shard.key' "${SHARD_KEY:-cm:creator}" "$CONFIG_FILE_CORE"
		    setOption 'shard.count' "$NUM_SHARDS" "$CONFIG_FILE_CORE"
		    setOption 'shard.instance' "$i" "$CONFIG_FILE_CORE"         

		    CONFIG_FILE_SOLR_SCHEMA=$newCore/conf/schema.xml
		    if [ $ALFRESCO_SOLR_SUGGESTER_ENABLED = true ]
		    then
		    	sed -i 's/.*\(<copyField source="suggest_\*" dest="suggest" \/>\).*/\1/g' "$CONFIG_FILE_SOLR_SCHEMA"
		    else
			    sed -i 's/.*\(<copyField source="suggest_\*" dest="suggest" \/>\).*/<!--\1-->/g' "$CONFIG_FILE_SOLR_SCHEMA"
		    fi
		    if [ $ALFRESCO_SOLR_FACETABLE_CATEGORIES_ENABLED = true ]
		    then
			    sed -i 's/\(.*<dynamicField.*name="\(category\|noderef\)@m_.*type="\)\(oldStandardAnalysis\)\(".*\)\(\/\)\(.*\)/\1identifier\4docValues="true" \/\6/g' "$CONFIG_FILE_SOLR_SCHEMA"
			    sed -i 's/\(.*<dynamicField.*name="\(category\|noderef\)@s_.*type="\)\(oldStandardAnalysis\)\(".*\)\(sortMissingLast="true"\)\(.*\)/\1identifier\4docValues="true"\6/g' "$CONFIG_FILE_SOLR_SCHEMA"
		    fi
		    
		    setGlobalOptions "$CONFIG_FILE_CORE" alfresco
		    
		    setOption 'solr.host' "$SOLR_HOST" "$SHARED_PROPERTIES"
		    setOption 'solr.port' "$PORT" "$SHARED_PROPERTIES"
		    
		    escapeFile "$CONFIG_FILE_CORE"
		done
	    else
		createCoreStatically "alfresco" "alfresco" "$newCore"
		
		setOption 'alfresco.stores' "workspace://SpacesStore" "$CONFIG_FILE_CORE"
		setOption 'enable.alfresco.tracking' "${ALFRESCO_ENABLE_TRACKING:-true}" "$CONFIG_FILE_CORE"
		setOption 'alfresco.index.transformContent' "${ALFRESCO_INDEX_CONTENT:-true}" "$CONFIG_FILE_CORE"
		setOption 'alfresco.corePoolSize' "${ALFRESCO_CORE_POOL_SIZE:-8}" "$CONFIG_FILE_CORE"
		setOption 'alfresco.doPermissionChecks' "${ALFRESCO_DO_PERMISSION_CHECKS:-true}" "$CONFIG_FILE_CORE"
		setOption 'solr.suggester.enabled' "$ALFRESCO_SOLR_SUGGESTER_ENABLED" "$CONFIG_FILE_CORE"

		CONFIG_FILE_SOLR_SCHEMA=$newCore/conf/schema.xml
		if [ $ALFRESCO_SOLR_SUGGESTER_ENABLED = true ]
		then
		    sed -i 's/.*\(<copyField source="suggest_\*" dest="suggest" \/>\).*/\1/g' "$CONFIG_FILE_SOLR_SCHEMA"
		else
			sed -i 's/.*\(<copyField source="suggest_\*" dest="suggest" \/>\).*/<!--\1-->/g' "$CONFIG_FILE_SOLR_SCHEMA"
		fi
		if [ $ALFRESCO_SOLR_FACETABLE_CATEGORIES_ENABLED = true ]
		then
			sed -i 's/\(.*<dynamicField.*name="\(category\|noderef\)@m_.*type="\)\(oldStandardAnalysis\)\(".*\)\(\/\)\(.*\)/\1identifier\4docValues="true" \/\6/g' "$CONFIG_FILE_SOLR_SCHEMA"
			sed -i 's/\(.*<dynamicField.*name="\(category\|noderef\)@s_.*type="\)\(oldStandardAnalysis\)\(".*\)\(sortMissingLast="true"\)\(.*\)/\1identifier\4docValues="true"\6/g' "$CONFIG_FILE_SOLR_SCHEMA"
		fi

		    setGlobalOptions "$CONFIG_FILE_CORE" alfresco
		    escapeFile "$CONFIG_FILE_CORE"
		fi
		elif [ $coreName = archive ]
		then
		    createCoreStatically "archive" "archive" "$newCore"
		    
		    setOption 'alfresco.stores' "archive://SpacesStore" "$CONFIG_FILE_CORE"
		    setOption 'enable.alfresco.tracking' "${ARCHIVE_ENABLE_TRACKING:-true}" "$CONFIG_FILE_CORE"
		    setOption 'alfresco.index.transformContent' "${ARCHIVE_INDEX_CONTENT:-true}" "$CONFIG_FILE_CORE"

		    setGlobalOptions "$CONFIG_FILE_CORE" archive
		    escapeFile "$CONFIG_FILE_CORE"	
		    elif [ $coreName = version ]
		    then
		    createCoreStatically "version" "version" "$newCore"
		    
		    setOption 'alfresco.stores' "workspace://version2Store" "$CONFIG_FILE_CORE"

		    setGlobalOptions "$CONFIG_FILE_CORE" version
		    escapeFile "$CONFIG_FILE_CORE"
		    else
			"Core $coreName not found"
		fi
		done
		
		if [ $JMX_ENABLED = true ]
		then
		    JAVA_OPTS="${JAVA_OPTS} -Dcom.sun.management.jmxremote.authenticate=false -Dcom.sun.management.jmxremote.local.only=false -Dcom.sun.management.jmxremote.ssl=false -Dcom.sun.management.jmxremote -Dcom.sun.management.jmxremote.rmi.port=5001 -Dcom.sun.management.jmxremote.port=5001 -Djava.rmi.server.hostname=${JMX_RMI_HOST}"
		fi
		if [ $DEBUG = true ]
		then
		    JAVA_OPTS="${JAVA_OPTS} -Xdebug -Xrunjdwp:transport=dt_socket,address=8000,server=y,suspend=n"
		fi
}

#follow http://docs.alfresco.com/5.2/tasks/solr6-install.html
echo "export SOLR_SOLR_DATA_DIR=${SOLR_DATA_DIR:-/opt/alfresco-search-services/data/index}" >>"$CONFIG_FILE_SOLR_START"
echo "export SOLR_SOLR_MODEL_DIR=${SOLR_MODEL_DIR:-/opt/alfresco-search-services/data/model}" >>"$CONFIG_FILE_SOLR_START"
echo "export SOLR_SOLR_CONTENT_DIR=${SOLR_CONTENT_DIR:-/opt/alfresco-search-services/data/contentstore}" >>"$CONFIG_FILE_SOLR_START"

if [ $ALFRESCO_SSL != none ]
then
    cp -r ${SOLR_DIR_ROOT}/keystore/* ${SOLR_DIR_ROOT}/templates/${TEMPLATE}/conf/
    
    setOption 'SOLR_SSL_KEY_STORE' "${SOLR_DIR_ROOT}/keystore/ssl.repo.client.keystore" "$CONFIG_FILE_SOLR_START"
    setOption 'SOLR_SSL_KEY_STORE_PASSWORD' "kT9X6oe68t" "$CONFIG_FILE_SOLR_START"
    setOption 'SOLR_SSL_TRUST_STORE' "${SOLR_DIR_ROOT}/keystore/ssl.repo.client.truststore" "$CONFIG_FILE_SOLR_START"
    setOption 'SOLR_SSL_TRUST_STORE_PASSWORD' "kT9X6oe68t" "$CONFIG_FILE_SOLR_START"
    setOption 'SOLR_SSL_NEED_CLIENT_AUTH' "true" "$CONFIG_FILE_SOLR_START"
    setOption 'SOLR_SSL_WANT_CLIENT_AUTH' "false" "$CONFIG_FILE_SOLR_START"
    setOption 'SOLR_SOLR_HOST' "$SOLR_HOST" "$CONFIG_FILE_SOLR_START"
    setOption 'SOLR_SOLR_PORT' "$PORT" "$CONFIG_FILE_SOLR_START"
    
    setJavaOption 'javax.net.ssl.keyStoreType' '-Djavax.net.ssl.keyStoreType=JCEKS'
    setJavaOption 'javax.net.ssl.trustStoreType' '-Djavax.net.ssl.trustStoreType=JCEKS'
    setJavaOption 'solr.ssl.checkPeerName' '-Dsolr.ssl.checkPeerName=false'        
fi



appStart () {
    mkdir -p /opt/alfresco-search-services/data/
    setJavaOptions
    makeConfigs
    echo "${SOLR_INSTALL_HOME}/solr/bin/solr start -f -m ${JAVA_XMX} -p ${PORT} -h ${SOLR_HOST} -s ${SOLR_DIR_ROOT} -a ${JAVA_OPTS}"
    ${SOLR_INSTALL_HOME}/solr/bin/solr start -f -m ${JAVA_XMX} -p ${PORT} -h ${SOLR_HOST} -s ${SOLR_DIR_ROOT} -a "${JAVA_OPTS}"
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
