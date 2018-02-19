#!/bin/bash
OCP_VERSION="v3.7";
PREFIX="aarrichi"
LOCALPATH=$PWD
# create project
oc new-project ${PREFIX}-cicd --display-name="CI/CD"
oc new-project ${PREFIX}-stage --display-name="Shopping - Stage"
oc new-project ${PREFIX}-prod --display-name="Shopping - Prod"

## import xpaas images for oc cluster up
#oc login -u system:admin
#git clone https://github.com/openshift/openshift-ansible
#cd openshift-ansible/roles/openshift_examples/files/examples/$OCP_VERSION/
#cd xpaas-streams
#for json in `ls -1 *.json`; do oc create -n openshift  -f $json; done
#cd ../xpaas-templates
#for json in `ls -1`; do oc create -n openshift -f $json; done
#cd $LOCALPATH


# CI/CD creation steps
#oc new-app -f http://bit.ly/openshift-gogs-persistent-template --param=HOSTNAME=gogs-cicd.cloud.redhat.int -n cicd
oc new-app -f ./gogs-persistent-template.yaml -n ${PREFIX}-cicd
oc new-app jenkins-ephemeral -l app=jenkins -p MEMORY_LIMIT=1Gi -n ${PREFIX}-cicd
oc create -f ./pipelines.yaml  -n ${PREFIX}-cicd
oc new-app -n ${PREFIX}-cicd -f https://raw.githubusercontent.com/OpenShiftDemos/nexus/master/nexus3-persistent-template.yaml --param=NEXUS_VERSION=3.6.1 --param=MAX_MEMORY=2Gi

# Stage Project creation steps
oc policy add-role-to-user edit system:serviceaccount:cicd:jenkins -n ${PREFIX}-stage

# Prod Project creation steps

oc policy add-role-to-user edit system:serviceaccount:cicd:jenkins -n ${PREFIX}-prod
oc create -f ./shopping-bluegreen.yaml  -n ${PREFIX}-prod
oc new-app shopping-bluegreen -l app=shopping -n ${PREFIX}-prod

#Optional
oc new-app docker.io/openshiftdemos/sonarqube:6.0 -e SONARQUBE_JDBC_USERNAME=sonar -e SONARQUBE_JDBC_PASSWORD=sonar -e SONARQUBE_JDBC_URL=jdbc:postgresql://postgresql/sonar -n ${PREFIX}-cicd
oc expose service sonarqube -n ${PREFIX}-cicd

# now we wait for gogs to be ready
x=1
oc get ep gogs -n ${PREFIX}-cicd -o yaml | grep "\- addresses:"
while [ ! $? -eq 0 ]
do
  sleep 10
  x=$(( $x + 1 ))
  if [ $x -gt 100 ]
  then
    exit 255
  fi
  oc get ep gogs -n ${PREFIX}-cicd -o yaml | grep "\- addresses:"
done

# we might catch the router before it's been updated, so wait just a touch more
sleep 10
GOGSROUTE=$(oc get route gogs -n ${PREFIX}-cicd -o=custom-columns=HOST:.spec.host | grep -v "HOST")
oc project ${PREFIX}-cicd
curl -sL --post302 -w "%{http_code}"  $GOGSROUTE/user/sign_up -d user_name=gogs -d email=admin@gogs.com -d password=password -d retype=password
curl -sL -w "%{http_code}" -H "Content-Type: application/json" -u gogs:password -X POST http://$GOGSROUTE/api/v1/repos/migrate -d @./clone_repo.json
