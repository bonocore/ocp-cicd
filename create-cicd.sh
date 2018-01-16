#!/bin/bash

#Should not be needed
oc policy add-role-to-user admin system:serviceaccount:cicd:default

# CI/CD creation steps
oc new-project cicd --display-name="CI/CD"
oc new-app -f http://bit.ly/openshift-gogs-persistent-template --param=HOSTNAME=gogs-cicd.cloud.redhat.int -n cicd
oc new-app jenkins-ephemeral -l app=jenkins -p MEMORY_LIMIT=1Gi -n cicd
oc create -f ./pipelines.yaml  -n cicd
oc create -f  https://raw.githubusercontent.com/OpenShiftDemos/nexus/master/nexus2-persistent-template.yaml -n cicd
oc new-app nexus2-persistent -n cicd

# Stage Project creation steps
oc new-project stage --display-name="Shopping - Stage"
oc policy add-role-to-user edit system:serviceaccount:cicd:jenkins -n stage

# Prod Project creation steps
oc new-project prod --display-name="Shopping - Prod"
oc policy add-role-to-user edit system:serviceaccount:cicd:jenkins -n prod
oc create -f ./shopping-bluegreen.yaml  -n prod
oc new-app shopping-bluegreen -l app=shopping -n prod

#Optional
oc new-app docker.io/openshiftdemos/sonarqube:6.0 -e SONARQUBE_JDBC_USERNAME=sonar,SONARQUBE_JDBC_PASSWORD=sonar,SONARQUBE_JDBC_URL=jdbc:postgresql://postgresql/sonar -n cicd
oc expose service sonarqube -n cicd

# now we wait for gogs to be ready
x=1
oc get ep gogs -n cicd -o yaml | grep "\- addresses:"
while [ ! $? -eq 0 ]
do
  sleep 10
  x=$(( $x + 1 ))
  if [ $x -gt 100 ]
  then
    exit 255
  fi
  oc get ep gogs -n cicd -o yaml | grep "\- addresses:"
done

# we might catch the router before it's been updated, so wait just a touch more
sleep 10

curl -sL --post302 -w "%{http_code}"  http://gogs-cicd.cloud.redhat.int/user/sign_up -d user_name=gogs -d email=admin@gogs.com -d password=password -d retype=password

curl -sL -w "%{http_code}" -H "Content-Type: application/json" -u gogs:password -X POST http://gogs-cicd.cloud.redhat.int/api/v1/repos/migrate -d @./clone_repo.json
