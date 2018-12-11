# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/)
and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [v0.0.5] - 2018-10-26
### Added
* [DOCKER-112] Integration with vault

### Fixed
* [DOCKER-135] Remove file appender, the only logs are on stdout and stderr which can be externalized

## [v0.0.4] - 2018-09-25
### Added
* [DOCKER-115] Move healthchecks to Dockerfiles
* [DOCKER-119] Generic mechanism to set variables via JAVA_OPTS_<variable>
* [DOCKER-121] Options for suggester and facetable categories for solr6
* [DOCKER-118] Generic mechanism to set variables via GLOBAL_WORKSPACE_, GLOBAL_ARCHIVE_, GLOBAL_ environment variables

### Fixed
* [DOCKER-91] Redirect port was not parametrized in server.xml, therefore it was not possible to change it
* [DOCKER-116] Change ports via variables JETTY_PORT and JETTY_PORT_SSL
* [DOCKER-122] Solr1, solr4 and solr6 run with the same uid+gid

### Changed
* [DOCKER-109] Adapt all solr images to start from Xenit base images

### Removed
* [DOCKER-120] Removed variables SOLR_PORT, SOLR_PORT_SSL = they are set with TOMCAT_PORT, TOMCAT_PORT_SSL and JETTY_PORT, JETTY_PORT_SSL
* [DOCKER-117] Removed custom variables for caches. They can be set via GLOBAL_WORKSPACE_, GLOBAL_ARCHIVE_, GLOBAL_ options

## [v0.0.3] - 2018-09-10
### Added
* [DOCKER-77] Smoke tests: search + status for shards (if testsSharded = true)
* [DOCKER-104] Alfresco search services 1.2.0

### Changed
* [DOCKER-90] Restructuring: global + local resources, single build
 
## [v0.0.2] - 2018-09-04
### Added
* [DOCKER-106] Parameter CORES_TO_TRACK as a ; separated list: e.g. CORES_TO_TRACK=alfresco;archive;version 
* [DOCKER-103] Parameters SOLR_DATA_DIR, SOLR_MODEL_DIR, SOLR_CONTENT_DIR to changed default locations
* [DOCKER-88] Solr1
* [DOCKER-56] Alfresco search services 1.1.1

### Changed
* [DOCKER-105] Refactored core creation: use static creation for default cores, same mechanism as for shards
* [DOCKER-66] Naming images 	
	
## [v0.0.1] - 2018-05-23
### Added
* [DOCKER-39] Support for JAVA_OPTS_<variable> variables, allowing for overrides in different docker-compose files.
* [DOCKER-41] Support for SSL in Alfresco search services 1.0.0 (solr6)

