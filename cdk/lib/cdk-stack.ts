import cdk = require('@aws-cdk/core');
import events = require('@aws-cdk/aws-events');
import eventTargets = require('@aws-cdk/aws-events-targets');
import ec2 = require('@aws-cdk/aws-ec2');
import ecs = require('@aws-cdk/aws-ecs');
import logs = require('@aws-cdk/aws-logs');
import iam = require('@aws-cdk/aws-iam');
import path = require('path');

export class CloudWatchScheduledEventsFargateTask extends cdk.Stack {
  constructor(scope: cdk.Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const vpc = this.node.tryGetContext('use_default_vpc') == "true" ? ec2.Vpc.fromLookup(this, 'Vpc', { isDefault: true }) : new ec2.Vpc(this, 'Vpc', {
      maxAzs: 3,
      natGateways: 1
    })

    const cluster = new ecs.Cluster(this, 'Cluster', {
      vpc
    })

    const fargatecounttaskrole = new iam.Role(this, 'Role', {
      assumedBy: new iam.ServicePrincipal('ecs-tasks.amazonaws.com')
    })
    
    new cdk.CfnOutput(this, 'TaskRole', { value: fargatecounttaskrole.roleArn });

    fargatecounttaskrole.addToPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      resources: ["*"],
      actions: ['ecs:DescribeClusters', 'ecs:ListClusters', 'eks:DescribeCluster', 'eks:ListClusters', 'cloudwatch:PutMetricData']
    }))
    
    const taskDefinition = new ecs.FargateTaskDefinition(this, 'Task', {
      memoryLimitMiB: 512,
      cpu: 256,
      taskRole: fargatecounttaskrole
    })

    const fargatecount = taskDefinition.addContainer('fargatecount', {
      image: ecs.ContainerImage.fromAsset(path.join('__dirname', '../../', 'dockerAssets.d')),
      environment: {
        'REGION': this.region,
        'ARMED': this.node.tryGetContext('armed')
      },
      logging: new ecs.AwsLogDriver({
        logRetention: logs.RetentionDays.ONE_MONTH,
        streamPrefix: 'fargatecount'
      }) 
    })

    const ecsTaskTarget = new eventTargets.EcsTask({ cluster, taskDefinition });

    new events.Rule(this, 'ScheduleRule', {
      // schedule: Schedule.cron({ minute: '0', hour: '4' }),
      schedule: events.Schedule.rate(cdk.Duration.minutes(10)),
      targets: [ecsTaskTarget],
    })
  }
}

