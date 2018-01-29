#!/bin/bash
OCP_VERSION="v3.6";
LOCALPATH=$PWD
# create project
oc login -u developer
oc new-project cicd --display-name="CI/CD"
oc new-project stage --display-name="Shopping - Stage"
oc new-project prod --display-name="Shopping - Prod"

# import xpaas images and fix permissions 

oc login -u system:admin
git clone https://github.com/openshift/openshift-ansible 
cd openshift-ansible/roles/openshift_examples/files/examples/$OCP_VERSION/
cd xpaas-streams
for json in `ls -1 *.json`; do oc create -n openshift -f $json; done
cd ../xpaas-templates
for json in `ls -1`; do oc create -n openshift -f $json; done
cd $LOCALPATH

oc policy add-role-to-user admin system:serviceaccount:cicd:default
oc tag openshift/jboss-eap70-openshift:1.6 openshift/jboss-eap70-openshift:latest
oc adm policy add-role-to-user cluster-admin developer
oc adm policy add-role-to-user admin developer -n cicd
oc adm policy add-role-to-user admin developer -n stage
oc adm policy add-role-to-user admin developer -n prod

# CI/CD creation steps
oc login -u developer
#oc new-app -f http://bit.ly/openshift-gogs-persistent-template --param=HOSTNAME=gogs-cicd.cloud.redhat.int -n cicd
oc new-app -f ./gogs-persistent-template.yaml -n cicd
oc new-app jenkins-ephemeral -l app=jenkins -p MEMORY_LIMIT=1Gi -n cicd
oc create -f ./pipelines.yaml  -n cicd
oc create -f  https://raw.githubusercontent.com/OpenShiftDemos/nexus/master/nexus2-persistent-template.yaml -n cicd
oc new-app nexus2-persistent -n cicd

# Stage Project creation steps
oc policy add-role-to-user edit system:serviceaccount:cicd:jenkins -n stage

# Prod Project creation steps

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
oc login -u system:admin
GOGSROUTE=$(oc get route gogs -n cicd -o=custom-columns=HOST:.spec.host | grep -v "HOST")
oc login -u developer
oc project cicd
curl -sL --post302 -w "%{http_code}"  $GOGSROUTE -d user_name=gogs -d email=admin@gogs.com -d password=password -d retype=password
curl -sL -w "%{http_code}" -H "Content-Type: application/json" -u gogs:password -X POST http://$GOGSROUTE/api/v1/repos/migrate -d @./clone_repo.json
