#!/bin/bash
#AWS_DEFAULT_AVAILABILITY_ZONE=us-east-1c
GRAFANA_DEFAULT_VERSION=4.5.1
PROMETHEUS_DEFAULT_VERSION=v2.0.0-beta.5
ALERT_MANAGER_DEFAULT_VERSION=v0.8.0
NODE_EXPORTER_DEFAULT_VERSION=v0.14.0
KUBE_STATE_METRICS_DEFAULT_VERSION=v1.0.1
DOCKER_REGISTRY_DEFAULT=docker.io
DOCKER_USER_DEFAULT=$(docker info|grep Username:|awk '{print $2}')
RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'

#Ask for AWS availability zone
#read -p "Enter your desired availability zone to deploy Prometheus StatefulSet [$AWS_DEFAULT_AVAILABILITY_ZONE]: " AWS_AVAILABILITY_ZONE
#AWS_AVAILABILITY_ZONE=${AWS_AVAILABILITY_ZONE:-$AWS_DEFAULT_AVAILABILITY_ZONE}

#Ask for grafana version or apply default
echo
read -p "Enter Grafana version [$GRAFANA_DEFAULT_VERSION]: " GRAFANA_VERSION
GRAFANA_VERSION=${GRAFANA_VERSION:-$GRAFANA_DEFAULT_VERSION}

#Ask for prometheus version or apply default
read -p "Enter Prometheus version [$PROMETHEUS_DEFAULT_VERSION]: " PROMETHEUS_VERSION
PROMETHEUS_VERSION=${PROMETHEUS_VERSION:-$PROMETHEUS_DEFAULT_VERSION}

#Ask for alertmanager version or apply default
read -p "Enter Alert Manager version [$ALERT_MANAGER_DEFAULT_VERSION]: " ALERT_MANAGER_VERSION
ALERT_MANAGER_VERSION=${ALERT_MANAGER_VERSION:-$ALERT_MANAGER_DEFAULT_VERSION}


#Ask for node exporter version or apply default
read -p "Enter Node Exporter version [$NODE_EXPORTER_DEFAULT_VERSION]: " NODE_EXPORTER_VERSION
NODE_EXPORTER_VERSION=${NODE_EXPORTER_VERSION:-$NODE_EXPORTER_DEFAULT_VERSION}

#Ask for kube-state-metrics version or apply default
read -p "Enter Kube State Metrics version [$KUBE_STATE_METRICS_DEFAULT_VERSION]: " KUBE_STATE_METRICS_VERSION
KUBE_STATE_METRICS_VERSION=${KUBE_STATE_METRICS_VERSION:-$KUBE_STATE_METRICS_DEFAULT_VERSION}

#Ask for docker registry
read -p "Enter your Docker registry [$DOCKER_REGISTRY_DEFAULT]: " DOCKER_REGISTRY
DOCKER_REGISTRY=${DOCKER_REGISTRY:-$DOCKER_REGISTRY_DEFAULT}

#Ask for dockerhub user or apply default of the current logged-in username
read -p "Enter your Docker Registry username [$DOCKER_USER_DEFAULT]: " DOCKER_USER
DOCKER_USER=${DOCKER_USER:-$DOCKER_USER_DEFAULT}

#Replace Dockerhub username in grafana deployment.
if [[ $DOCKER_REGISTRY != "docker.io" ]]; then
  sed -i -e 's/DOCKER_USER/'"$DOCKER_REGISTRY\/$DOCKER_USER"'/g' k8s/grafana/grafana.svc.de.yaml
else
  sed -i -e 's/DOCKER_USER/'"$DOCKER_USER"'/g' k8s/grafana/grafana.svc.de.yaml
fi

#Do you want to set up an SMTP relay?
echo
echo -e "${BLUE}Do you want to set up an SMTP relay?"
tput sgr0
read -p "Y/N [N]: " use_smtp

#if so, fill out this form...
if [[ $use_smtp =~ ^([yY][eE][sS]|[yY])$ ]]; then
  #smtp smarthost
  read -p "SMTP smarthost: " smtp_smarthost
  #smtp from address
  read -p "SMTP from (user@domain.com): " smtp_from
  #smtp to address
  read -p "Email address to send alerts to (user@domain.com): " alert_email_address
  #smtp username
  read -p "SMTP auth username: " smtp_user
  #smtp password
  prompt="SMTP auth password: "
  while IFS= read -p "$prompt" -r -s -n 1 char
  do
      if [[ $char == $'\0' ]]
      then
          break
      fi
      prompt='*'
      smtp_password+="$char"
  done

  #update configmap with SMTP relay info
  sed -i -e 's/your_smtp_smarthost/'"$smtp_smarthost"'/g' k8s/prometheus/alertmanager.cm.yaml
  sed -i -e 's/your_smtp_from/'"$smtp_from"'/g' k8s/prometheus/alertmanager.cm.yaml
  sed -i -e 's/your_smtp_user/'"$smtp_user"'/g' k8s/prometheus/alertmanager.cm.yaml
  sed -i -e 's,your_smtp_pass,'"$smtp_password"',g' k8s/prometheus/alertmanager.cm.yaml
  sed -i -e 's/your_alert_email_address/'"$alert_email_address"'/g' k8s/prometheus/alertmanager.cm.yaml
fi

#Do you want to set up slack?
echo
echo -e "${BLUE}Do you want to set up slack alerts?"
tput sgr0
read -p "Y/N [N]: " use_slack

#if so, fill out this form...
if [[ $use_slack =~ ^([yY][eE][sS]|[yY])$ ]]; then

  read -p "Slack api token: " slack_api_token
  read -p "Slack channel: " slack_channel

  #again, our sed is funky due to slashes appearing in slack api tokens
  sed -i -e 's,your_slack_api_token,'"$slack_api_token"',g' k8s/prometheus/alertmanager.cm.yaml
  sed -i -e 's/your_slack_channel/'"$slack_channel"'/g' k8s/prometheus/alertmanager.cm.yaml
fi


#Do you want to monitor EC2 instances in your AWS account?
echo
echo -e "${BLUE}Do you want to monitor EC2 instances in your AWS account?"
tput sgr0
read -p "Y/N [N]: " monitor_aws

#if so, fill out this form...
if [[ $monitor_aws =~ ^([yY][eE][sS]|[yY])$ ]]; then

  #try to figure out AWS credentials for EC2 monitoring, if not...ask.
  echo
  echo -e "${BLUE}Detecting AWS access keys."
  tput sgr0
  if [ ! -z $AWS_ACCESS_KEY_ID ] && [ ! -z $AWS_SECRET_ACCESS_KEY ]; then
    aws_access_key=$AWS_ACCESS_KEY_ID
    aws_secret_key=$AWS_SECRET_ACCESS_KEY
    echo -e "${ORANGE}AWS_ACCESS_KEY_ID found, using $aws_access_key."
    tput sgr0
  elif [ ! -z $AWS_ACCESS_KEY ] && [ ! -z $AWS_SECRET_KEY ]; then
    aws_access_key=$AWS_ACCESS_KEY
    aws_secret_key=$AWS_SECRET_KEY
    echo -e "${ORANGE}AWS_ACCESS_KEY found, using $aws_access_key."
    tput sgr0
  else
    echo -e "${RED}Unable to determine AWS credetials from environment variables."
    tput sgr0
    #aws access key
    read -p "AWS Access Key ID: " aws_access_key
    #aws secret access key
    read -p "AWS Secret Access Key: " aws_secret_key
  fi

  #sed in the AWS credentials. this looks odd because aws secret access keys can have '/' as a valid character
  #so we use ',' as a delimiter for sed, since that won't appear in the secret key
  sed -i -e 's/aws_access_key/'"$aws_access_key"'/g' k8s/prometheus/prometheus.cm.yaml
  sed -i -e 's,aws_secret_key,'"$aws_secret_key"',g' k8s/prometheus/prometheus.cm.yaml

else
  rm grafana/grafana-dashboards/ec2-instances.json
fi

echo
echo -e "${BLUE}Creating ${ORANGE}'monitoring' ${BLUE}namespace."
tput sgr0
#create a separate namespace for monitoring
kubectl create namespace monitoring

echo
echo -e "${BLUE}Using RBAC?"
tput sgr0
read -p "[y/N]: " response
if [[ $response =~ ^([yY][eE][sS]|[yY])$ ]]
then
    kubectl apply -f ./k8s/rbac
    sed -i -e 's/default/'prometheus'/g' k8s/prometheus/prometheus.svc.ss.yaml
    sed -i -e 's/default/'kube-state-metrics'/g' k8s/kube-state-metrics/ksm.de.yaml
else
    echo -e "${GREEN}Skipping RBAC configuration"
fi
tput sgr0

#aws availability zone
#sed -i -e 's/AWS_AVAILABILITY_ZONE/'"$AWS_AVAILABILITY_ZONE"'/g' k8s/prometheus/prometheus.svc.ss.yaml

#set prometheus version
sed -i -e 's/PROMETHEUS_VERSION/'"$PROMETHEUS_VERSION"'/g' k8s/prometheus/prometheus.svc.ss.yaml

#set grafana version
sed -i -e 's/GRAFANA_VERSION/'"$GRAFANA_VERSION"'/g' grafana/Dockerfile
sed -i -e 's/GRAFANA_VERSION/'"$GRAFANA_VERSION"'/g' k8s/grafana/grafana.svc.de.yaml

#set alertmanager version
sed -i -e 's/ALERT_MANAGER_VERSION/'"$ALERT_MANAGER_VERSION"'/g' k8s/prometheus/alertmanager.svc.de.yaml

#set node-exporter version
sed -i -e 's/NODE_EXPORTER_VERSION/'"$NODE_EXPORTER_VERSION"'/g' k8s/prometheus/node-exporter.svc.ds.yaml

#set node-exporter version
sed -i -e 's/KUBE_STATE_METRICS_VERSION/'"$KUBE_STATE_METRICS_VERSION"'/g' k8s/kube-state-metrics/ksm.de.yaml

#build grafana image, push to dockerhub
echo
echo -e "${BLUE}Building Grafana Docker image and pushing to dockerhub"
tput sgr0
docker build -t $DOCKER_REGISTRY/$DOCKER_USER/grafana:$GRAFANA_VERSION ./grafana --no-cache
docker push $DOCKER_REGISTRY/$DOCKER_USER/grafana:$GRAFANA_VERSION
#upon failure, run docker login
if [ $? -eq 1 ];then
  echo -e "${RED}docker push failed! perhaps you need to login \"${DOCKER_USER}\" to dockerhub?"
  tput sgr0
  docker login -u $DOCKER_USER $DOCKER_REGISTRY
  #try again
  docker push $DOCKER_REGISTRY/$DOCKER_USER/grafana:$GRAFANA_VERSION
  if [ $? -eq 1 ];then
    echo -e "${RED}docker push failed a second time! exiting."
    ./cleanup.sh
    exit 1
  fi
fi


#deploy grafana
echo
echo -e "${ORANGE}Deploying Grafana"
tput sgr0
kubectl apply -f k8s/grafana

#Fix for kubernetes v1.7 < v1.7.2

KUBERNETES_VERSION=$(kubectl version --short | grep Server)
if [[ $KUBERNETES_VERSION == "Server Version: v1.7.0" ]] || [[ $KUBERNETES_VERSION == "Server Version: v1.7.0" ]] || [[ $KUBERNETES_VERSION == "Server Version: v1.7.1" ]] ; then
sed -i -e 's/\/api\/v1\/nodes\/\${1}\/proxy\/metrics\/cadvisor/\/api\/v1\/nodes\/\$\{1\}\:4194\/proxy\/metrics/g' k8s/prometheus/prometheus.cm.yaml
fi

#remove Cadvisor configuration from Prometheus configmap for older kubernetes versions.
KUBERNETES_VERSION=$(kubectl version | grep Server | grep Minor | cut -d "," -f 2 | cut -d ":" -f 2 | tr -d '"')
if [ $KUBERNETES_VERSION -ge 7 ];
 then true;
else sed -i  -e '51,70d' ./k8s/prometheus/prometheus.cm.yaml;
fi

#deploy prometheus
echo
echo -e "${ORANGE}Deploying Prometheus"
tput sgr0
kubectl apply -R -f ./k8s/prometheus

#deploy kube-state-metrics
echo
echo -e "${ORANGE}Deploying Kube State Metrics exporter"
tput sgr0
kubectl apply -f ./k8s/kube-state-metrics
echo

echo
#cleanup
echo -e "${BLUE}Removing local changes"
echo
#remove  "sed" generated files
rm k8s/prometheus/*.yaml-e && rm k8s/grafana/*.yaml-e && rm grafana/*-e && rm k8s/kube-state-metrics/*.yaml-e 2> /dev/null
./cleanup.sh

echo -e "${BLUE}Done"
echo
tput sgr0

#Check if the Grafana pod is ready

while :
do
   echo -e "${BLUE}Waiting for Grafana pod to become ready"
   tput sgr0
   sleep 2
   echo
   if kubectl get pods -n monitoring | grep grafana | grep Running
   then
   break
else
   echo
   tput sgr0
   fi
done


GRAFANA_POD=$(kubectl get pods --namespace=monitoring | grep grafana | cut -d ' ' -f 1)

#import prometheus datasource in grafana using Grafana API.
#proxy grafana to localhost to import datasource using Grafana API.

kubectl port-forward $GRAFANA_POD --namespace=monitoring 3000:3000 > /dev/null 2>&1 &

echo
echo -e "${ORANGE}Importing Prometheus datasource."
tput sgr0
sleep 2
curl 'http://admin:admin@127.0.0.1:3000/api/datasources' -X POST -H 'Content-Type: application/json;charset=UTF-8' --data-binary '{"name":"prometheus.monitoring.svc.cluster.local","type":"prometheus","url":"http://prometheus.monitoring.svc.cluster.local:9090","access":"proxy","isDefault":true}' 2> /dev/null 2>&1
echo

#check datasources
echo
echo -e "${GREEN}Checking datasource"
tput sgr0
curl 'http://admin:admin@127.0.0.1:3000/api/datasources' 2> /dev/null 2>&1
echo
# kill the backgrounded proxy process
kill $!

# set up proxy for the user
echo
echo -e "${GREEN}Done"
tput sgr0
