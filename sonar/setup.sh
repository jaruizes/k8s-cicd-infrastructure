#!/bin/bash

sonarqube_namespace="ci"
sonarqube_admin_user="admin"
sonarqube_admin_password="admin123"
sonarqube_port="9003"


applyDeploymentToCluster() {
  kubectl apply -f postgresql.yaml
  while [[ $(kubectl get pods -l 'app in (sonarqube-postgres-pvc)' -n "$sonarqube_namespace" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    echo "---> Waiting for Postgresql pods be ready..." && sleep 10;
  done

  kubectl apply -f sonarqube.yaml
  while [[ $(kubectl get pods -l 'app in (sonarqube-pvc)' -n "$sonarqube_namespace" -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do
    echo "---> Waiting for Sonarqube pods be ready..." && sleep 10;
  done
}


getExternalIP() {
  sonarqube_external_ip=""
  while [ -z $sonarqube_external_ip ]; do
    echo "---> Waiting for Sonarqube API External IP be assigned..."
    sonarqube_external_ip=$(kubectl get services sonarqube-pvc -n "$sonarqube_namespace" -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    [ -z "$sonarqube_external_ip" ] && sleep 10
  done
  echo "---> External IP assigned: $sonarqube_external_ip"

  sonarqube_api_base_url="http://$sonarqube_external_ip:$sonarqube_port/api"
}

waitForAPIAvailable() {
  echo "---> Waiting till API be available ("$sonarqube_api_base_url/system/health")...."
  attempts=0
  until [ $(curl --user "$sonarqube_admin_user:$sonarqube_admin_pwd" --output /dev/null --max-time 4 --silent --head --fail "$sonarqube_api_base_url/system/health") ] || [ $attempts -gt 5 ]; do
      sleep 5
      ((attempts=attempts+1))
      echo "$attempts"
  done

  if [ "$attempts" -ge 5 ]; then
    echo "ERROR: Sonarqube API isn't available...exiting"
    exit 1
  fi

  echo "---> Sonarqube API ready to listen to request...."
}


createNewUserToken() {
  curl --data-urlencode 'name=ada_token' -H "Content-Type: application/x-www-form-urlencoded" \
  -X POST "$sonarqube_api_base_url/user_tokens/generate" \
  --user "$sonarqube_admin_user:$sonarqube_admin_pwd"
}

updatePassword() {
  curl --data-urlencode 'login=admin,password=admin123,previousPassword=admin' -H "Content-Type: application/x-www-form-urlencoded" \
  -X POST "$sonarqube_api_base_url/users/change_passworde" \
  --user "$sonarqube_admin_user:$sonarqube_admin_pwd"
}

echo "Deploying and configuring Sonarqube....Starting"
applyDeploymentToCluster
getExternalIP
createNewUserToken
updatePassword
echo "Deploying and configuring Sonarqube....Finished"
echo "sonarqube URL: http://$sonarqube_external_ip:$sonarqube_port"













