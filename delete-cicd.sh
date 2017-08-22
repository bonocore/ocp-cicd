#!/bin/bash
oc project cicd
oc delete all -l app=jenkins -n cicd --now=true
oc delete all -l app=shopping -n stage --now=true
oc delete all -l app=shopping -n prod --now=true
oc delete routes/jenkins
oc delete serviceaccount jenkins
oc delete rolebinding jenkins_edit
oc delete serviceaccount gogs
oc delete bc/shopping-pipeline is/gogs is/nexus dc/gogs dc/gogs-postgresql dc/nexus routes/gogs routes/nexus svc/gogs svc/gogs-postgresql svc/nexus
oc delete is/sonarqube dc/sonarqube routes/sonarqube svc/sonarqube
oc delete pvc/gogs-data pvc/gogs-postgres-data
oc delete pvc/nexus-pv
oc delete cm/gogs-config
oc project prod
oc delete is/shopping
oc delete template shopping-bluegreen -n prod
