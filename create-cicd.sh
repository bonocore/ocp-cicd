#!/bin/bash
OCP_VERSION="v3.7";
LOCALPATH=$PWD
# create project
oc login -u developer
oc new-project cicd --display-name="CI/CD"
oc new-project stage --display-name="Shopping - Stage"
oc new-project prod --display-name="Shopping - Prod"

## import xpaas images for oc cluster up
#oc login -u system:admin
#git clone https://github.com/openshift/openshift-ansible
#cd openshift-ansible/roles/openshift_examples/files/examples/$OCP_VERSION/
#cd xpaas-streams
#for json in `ls -1 *.json`; do oc create -n openshift  -f $json; done
#cd ../xpaas-templates
#for json in `ls -1`; do oc create -n openshift -f $json; done
#cd $LOCALPATH

# import xpaas images for traditional setup
oc login -u system:admin
IMAGESTREAMDIR="/usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/$OCP_VERSION/image-streams"; \
XPAASSTREAMDIR="/usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/$OCP_VERSION/xpaas-streams"; \
XPAASTEMPLATES="/usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/$OCP_VERSION/xpaas-templates"; \
DBTEMPLATES="/usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/$OCP_VERSION/db-templates"; \
QSTEMPLATES="/usr/share/ansible/openshift-ansible/roles/openshift_examples/files/examples/$OCP_VERSION/quickstart-templates"
oc create -f $IMAGESTREAMDIR/image-streams-rhel7.json -n openshift
oc create -f $XPAASSTREAMDIR/jboss-image-streams.json -n openshift
oc create -f $DBTEMPLATES -n openshift
oc create -f $QSTEMPLATES -n openshift
oc create -f $XPAASTEMPLATES -n openshift
sleep 45

cd $LOCALPATH

# fixing user permission
oc policy add-role-to-user admin system:serviceaccount:cicd:default
oc adm policy add-role-to-user cluster-admin developer
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
oc new-app -f https://raw.githubusercontent.com/OpenShiftDemos/nexus/master/nexus3-persistent-template.yaml --param=NEXUS_VERSION=3.6.1 --param=MAX_MEMORY=2Gi

# Stage Project creation steps
oc policy add-role-to-user edit system:serviceaccount:cicd:jenkins -n stage

# Prod Project creation steps

oc policy add-role-to-user edit system:serviceaccount:cicd:jenkins -n prod
oc create -f ./shopping-bluegreen.yaml  -n prod
oc new-app shopping-bluegreen -l app=shopping -n prod

#Optional
oc new-app docker.io/openshiftdemos/sonarqube:6.0 -n cicd
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
curl -sL --post302 -w "%{http_code}"  $GOGSROUTE/user/sign_up -d user_name=gogs -d email=admin@gogs.com -d password=password -d retype=password
curl -sL -w "%{http_code}" -H "Content-Type: application/json" -u gogs:password -X POST http://$GOGSROUTE/api/v1/repos/migrate -d @./clone_repo.json
