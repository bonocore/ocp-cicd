#!/bin/bash
oc new-project stage --display-name="Shopping - Stage"
oc new-project prod --display-name="Shopping - Prod"
oc new-project cicd --display-name="CI/CD"


oc policy add-role-to-user edit system:serviceaccount:cicd:jenkins -n stage
oc policy add-role-to-user edit system:serviceaccount:cicd:jenkins -n prod

#Should not be needed
#oc policy add-role-to-user admin system:serviceaccount:cicd:default

oc new-app -f http://bit.ly/openshift-gogs-persistent-template --param=HOSTNAME=gogs-cicd.apps.rhpds.openshift.opentlc.com -n cicd

oc new-app jenkins-ephemeral -l app=jenkins -p MEMORY_LIMIT=1Gi -n cicd

oc create -f ./pipelines.yaml  -n cicd

oc create -f ./shopping-bluegreen.yaml  -n prod

oc create -f  https://raw.githubusercontent.com/OpenShiftDemos/nexus/master/nexus2-persistent-template.yaml -n cicd

oc new-app nexus2-persistent -n cicd

oc new-app shopping-bluegreen -l app=shopping -n prod

#Optional
oc new-app docker.io/openshiftdemos/sonarqube:6.0 \
-e SONARQUBE_JDBC_USERNAME=sonar,SONARQUBE_JDBC_PASSWORD=sonar,SONARQUBE_JDBC_URL=jdbc:postgresql://postgresql/sonar -n cicd
oc expose service sonarqube -n cicd

curl -sL --post302 -w "%{http_code}"  \ http://gogs-cicd.apps.rhpds.openshift.opentlc.com/user/sign_up --form user_name=gogs --form email=admin@gogs.com --form password=password --form retype=password

curl -sL -w "%{http_code}" -H "Content-Type: application/json" -u gogs:password -X POST http://gogs-cicd.apps.rhpds.openshift.opentlc.com/api/v1/repos/migrate -d @./clone_repo.json
