#!/bin/bash

# Massimo Re Ferre' massimo@it20.info

###########################################################
###########                README               ###########
###########################################################
# This script tracks the number of Fargate pods and Fargate
# tasks deployed across all of your EKS and ECS clusters
###########################################################
###########            End of  README           ###########
###########################################################

###########################################################
###########              USER INPUTS            ###########
###########################################################
: ${METRICNAME:="fargate-count"}
: ${CWNAMESPACE:="Fargate Stats"}
: ${ARMED:="false"}
###########################################################
###########           END OF USER INPUTS        ###########
###########################################################
if [ -z ${REGION} ]; then echo "ERROR: REGION not set - exiting" && exit; fi
echo
echo Region                  : $REGION
echo IAM Role Arn            : $(aws sts get-caller-identity | jq .Arn)
echo Metric Name             : $METRICNAME
echo CloudWatch Namespace    : $CWNAMESPACE
echo CloudWatch armed        : $ARMED 
echo Start run               : $(date)
echo
echo "Beginning of the loop for ECS clusters"
# ECS Clusters discovery
ECSCLUSTERLIST=$(aws ecs list-clusters --region $REGION) 
RAWECSCLUSTERARNS=$(jq --raw-output '.clusterArns[]' <<< "$ECSCLUSTERLIST")
# Loop for every ECS cluster discovered
while read -r ECSCLUSTERARN; do
    CLUSTERDESCRIPTION=$(aws ecs describe-clusters --cluster $ECSCLUSTERARN --region $REGION --include STATISTICS)
    FARGATETASKSCOUNT=$(jq --raw-output '.clusters[].statistics[] | select(.name == "runningFargateTasksCount") | .value' <<< "$CLUSTERDESCRIPTION")
    ECSCLUSTERNAME=$(jq --raw-output .clusters[].clusterName <<< "$CLUSTERDESCRIPTION")
    if [ $ARMED == "true" ] 
        then 
            echo aws cloudwatch put-metric-data --metric-name "$METRICNAME" --dimensions cluster=ECS-$ECSCLUSTERNAME --namespace "$CWNAMESPACE" --value $FARGATETASKSCOUNT --region $REGION
            aws cloudwatch put-metric-data --metric-name "$METRICNAME" --dimensions cluster=ECS-$ECSCLUSTERNAME --namespace "$CWNAMESPACE" --value $FARGATETASKSCOUNT --region $REGION
    fi 
    echo cluster $ECSCLUSTERNAME has $FARGATETASKSCOUNT fargate tasks 
done <<< "$RAWECSCLUSTERARNS"

echo 

echo "Beginning of the loop for EKS clusters"
# EKS Clusters discovery
EKSCLUSTERLIST=$(aws eks list-clusters --region $REGION) 
RAWEKSCLUSTERNAMES=$(jq --raw-output '.clusters[]' <<< "$EKSCLUSTERLIST")
# Loop for every EKS cluster discovered
while read -r EKSCLUSTERNAME; do
    aws eks update-kubeconfig --name $EKSCLUSTERNAME --region $REGION # This updates the config file in the .kube directory 
    RAWEKSPODNAMES=$(kubectl get --all-namespaces  --output json  pods | jq '.items[] | select(.spec.schedulerName=="fargate-scheduler")' | jq --raw-output .spec.containers[].name)
    FARGATETASKSCOUNT=$(echo "$RAWEKSPODNAMES" | grep . | wc -l)
    if [ $ARMED == "true" ] 
        then aws cloudwatch put-metric-data --metric-name "$METRICNAME" --dimensions cluster=EKS-$EKSCLUSTERNAME --namespace "$CWNAMESPACE" --value $FARGATETASKSCOUNT --region $REGION
    fi
    echo $(date)  cluster $EKSCLUSTERNAME has $FARGATETASKSCOUNT fargate pods 
done <<< "$RAWEKSCLUSTERNAMES"

echo
echo End run: $(date)  
echo 
