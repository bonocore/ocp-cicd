# ocp-cicd demo


1) edit OCP_VERSION="v3.6"; on create-cicd.sh in order to install correct xpaas images from https://github.com/openshift/openshift-ansible

2) execute create-cicd.sh


NOTE

fixed user permission for OCP 3.6/3.7 
reference local file for jenkins/nexus templates
implemented import of xpaas images with latest tag for EAP
implemented default route subdomain for gogs avoiding manual change to hosts file




