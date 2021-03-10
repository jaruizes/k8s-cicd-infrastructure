#!/bin/bash

nexus_namespace="ci"
nexus_admin_user="admin"
nexus_admin_password="admin123"
nexus_port="9002"

applyDeploymentToCluster() {
  kubectl apply -f nexus.yaml
  while [[ $(kubectl get pods -l 'app in (nexus-pvc)' -n "$nexus_namespace" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    echo "   ---> Waiting for Nexus pods be ready..." && sleep 10;
  done
}

waitForDefaultAdminPasswordBeGenerated() {
  nexus_pod_name=$(kubectl get pod -l app=nexus-pvc -n "$nexus_namespace" --template '{{range .items}}{{.metadata.name}}{{"\n"}}{{end}}')
  echo "   ---> Nexus pod name: $nexus_pod_name"

  while ! kubectl exec "$nexus_pod_name" -n "$nexus_namespace" -- cat /nexus-data/admin.password ;do
    echo "   ---> Waiting for the Nexus admin.password file to be generated" && sleep 10
  done

  nexus_admin_pwd=$(kubectl exec "$nexus_pod_name" -n "$nexus_namespace" -- cat /nexus-data/admin.password)
  echo "   ---> Admin pass: $nexus_admin_pwd"
}

getExternalIP() {
  nexus_external_ip=$(kubectl get services nexus-pvc -n "$nexus_namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  nexus_api_base_url="http://$nexus_external_ip:$nexus_port/service/rest/v1"
}

waitForNexusAPIAvailable() {
  echo "   ---> Waiting till Nexus API be available...."
  attemps=0
  until [ $(curl --output /dev/null --max-time 4 --silent --head --fail "$nexus_api_base_url/repositories") ] || [ $attemps -gt 3 ]; do
      sleep 5
      ((attemps=attemps+1))
  done

  if [ $attemps == 3 ]; then
    echo "ERROR: Nexus API isn't available...exiting"
    exit 1
  fi

  echo "   ---> Nexus API ready to listen to request...."
}

createNewUserForDeploy() {
  curl -d "@data/user_data.json" -H "Content-Type: application/json" -X POST "$nexus_api_base_url/security/users" --user "$nexus_admin_user:$nexus_admin_pwd"
  echo "   ---> User deploy created"
}

setAnonymousAccessAllowed() {
  curl -d "@data/anonymous_data.json" -H "Content-Type: application/json" -X PUT "$nexus_api_base_url/security/anonymous" --user "$nexus_admin_user:$nexus_admin_pwd"
  echo "   ---> Anonymous access allowed"
}

updateAdminPassword() {
  curl -d "$nexus_admin_password" -H "Content-Type: text/plain" -X PUT "$nexus_api_base_url/security/users/$nexus_admin_user/change-password" --user "$nexus_admin_user:$nexus_admin_pwd"
  echo "   ---> Admin password updated"
}

removeTemporalFiles() {
  kubectl exec "$nexus_pod_name" -n "$nexus_namespace" -- rm -rf /nexus-data/tmp
  echo "   ---> Removed tmp files"
}

echo "Deploying and configuring Nexus....Starting"
applyDeploymentToCluster
waitForDefaultAdminPasswordBeGenerated
getExternalIP
waitForNexusAPIAvailable
createNewUserForDeploy
setAnonymousAccessAllowed
updateAdminPassword
removeTemporalFiles
echo "Deploying and configuring Nexus....Finished"
echo "Nexus URL: http://$nexus_external_ip:$nexus_port"













