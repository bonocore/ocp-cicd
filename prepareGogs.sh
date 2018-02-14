#!/bin/bash
curl -sL --post302 -w "%{http_code}" http://gogs-gbcicd.apps.rhpds.openshift.opentlc.com/user/sign_up --form user_name=gogs --form email=admin@gogs.com --form password=gogs --form retype=gogs
curl -sL -w "%{http_code}" -H "Content-Type: application/json" -u gogs:gogs -X POST http://gogs-gbcicd.apps.rhpds.openshift.opentlc.com/api/v1/repos/migrate -d @./clone_repo.json
