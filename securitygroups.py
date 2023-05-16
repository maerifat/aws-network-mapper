import boto3
from prettytable import PrettyTable
import os
from datetime import datetime
from markupsafe import Markup
import html

# set up the AWS sessions for dev and prod

prod_session = boto3.Session(profile_name='prod')
security_session = boto3.Session(profile_name='sec')
staging_session= boto3.Session(profile_name='staging')
logging_session = boto3.Session(profile_name='logging')
infra_session = boto3.Session(profile_name='infra')
dev_session = boto3.Session(profile_name='dev')
sandbox_session = boto3.Session(profile_name='sandbox')

# get the list of AWS regions
#regions = prod_session.get_available_regions('ec2')
regions = security_session.get_available_regions('ec2')
regions= ['af-south-1', 'ap-east-1', 'ap-northeast-1', 'ap-northeast-2', 'ap-northeast-3', 'ap-south-1', 'ap-south-2', 'ap-southeast-1', 'ap-southeast-2', 'ap-southeast-3', 'ap-southeast-4', 'ca-central-1', 'eu-central-1', 'eu-central-2', 'eu-north-1', 'eu-south-1', 'eu-south-2', 'eu-west-1', 'eu-west-2', 'eu-west-3', 'me-central-1', 'me-south-1', 'sa-east-1', 'us-east-1', 'us-east-2', 'us-west-1', 'us-west-2']
#print(regions)

#regions= ['ap-south-1']
# set up the HTML table
table = PrettyTable(['S. No.', 'Account', 'Region', 'SecurityGroupId', 'Security Group Name', 'Resource Used','Protocol', 'Port Range', 'Source'], escape=False)
table.align = "l"

# initialize row count
row_count = 0


from botocore.exceptions import ClientError

def find_ec2_instances(sg):
    ec2 = session.client('ec2', region_name=region)
    try:
        response = ec2.describe_instances(Filters=[
                {'Name': 'instance.group-id', 'Values': [sg]}
            ]) 
        if not response['Reservations']:
            instances = ""
        else:
            instances = []
            for reservation in response['Reservations']:
                for instance in reservation['Instances']:
                    instances.append(f"ec2:{instance['InstanceId']}")
        instance_ids = ' , '.join(instances)
        
        return instance_ids
    except ClientError as ex:
        print(ex)



def find_vpn(sg):
    vpn_endpoints=[]
    try:
        client_vpn = session.client('ec2',region_name=region)
        response = client_vpn.describe_client_vpn_endpoints()
        for endpoint in response['ClientVpnEndpoints']:
            security_group_ids = endpoint['SecurityGroupIds']
            if sg in security_group_ids:
                vpn_endpoints.append(f"vpn:{endpoint['ClientVpnEndpointId']}")
    except Exception as e:
        print(e)

    if not vpn_endpoints:
        vpn_endpoints=""
    else:
        vpn_endpoints = ' , '.join(vpn_endpoints)
    print(vpn_endpoints)
    return vpn_endpoints



def find_beanstalk_envs(sg):
    beanstalk_envs=set()
    try: 
        eb_client = session.client('elasticbeanstalk',region_name=region)
        environments = eb_client.describe_environments()['Environments']
        # Loop through each environment and retrieve its security groups
        for env in environments:
            env_name = env['EnvironmentName']
            env_id = env['EnvironmentId']
            env_resources = eb_client.describe_environment_resources(EnvironmentId=env_id)['EnvironmentResources']
            beanstalkinstances = [instance['Id'] for instance in env_resources['Instances']]
            for beanstalkinstance in beanstalkinstances:
                instance_ids= find_ec2_instances(sg)
                if beanstalkinstance in instance_ids:
                    print("yes it is there.")
                    beanstalk_envs.add(f"ebs:env/{env_name}")
        print(f"{sg} is in {beanstalk_envs}")
        
    except Exception as e:
        print(e)
    if not beanstalk_envs:
        beanstalk_envs=""
    else:
        beanstalk_envs = ' , '.join(beanstalk_envs)
    return beanstalk_envs




def find_rds(sg):
    rds_client = session.client('rds', region_name=region)
    # Get all RDS instances
    response = rds_client.describe_db_instances()

    # Loop through each RDS instance
    rds_instances=[]
    for db_instance in response['DBInstances']:
        try:
            print()
            # Get the security groups associated with the RDS instance
            security_groups = db_instance['VpcSecurityGroups']

            # Print the security group IDs
            for security_group in security_groups:
                if sg in security_group['VpcSecurityGroupId']:
                    rds_instances.append(f"rds:{db_instance['DBInstanceIdentifier']}")
                else:
                    print("rds not found")
                #print(f"Security Group ID for RDS instance {db_instance['DBInstanceIdentifier']}: {security_group['VpcSecurityGroupId']}")
        except Exception as e:
            print(e)
    if not rds_instances:
        rds_instances=""
    else:
        rds_instances = ' , '.join(rds_instances)
    return rds_instances




def find_ecs(sg):
    ecs_client=session.client('ecs', region_name=region)
    # List all clusters
    clusters = ecs_client.list_clusters()
    # Loop through each cluster
    ecs_services=[]
    for cluster in clusters['clusterArns']:
        
        try:
            # List all services in the cluster
            
            services = ecs_client.list_services(cluster=cluster)

            for service in services['serviceArns']:
                # Get the details of the service
                response = ecs_client.describe_services(cluster=cluster, services=[service])
                
                security_groups = response['services'][0]['networkConfiguration']['awsvpcConfiguration']['securityGroups']
                if sg in security_groups:
                    ecs_services.append(f"ecs:{cluster.split(':')[-1]};service/{response['services'][0]['serviceName']}")

        except:
            print("fault in find_ecs")
    if not ecs_services:
        ecs_services=""
    else:
        ecs_services = ' , '.join(ecs_services)
    return ecs_services



def find_eks(sg):
    eks =session.client('eks',region_name=region)
    # List the names of all EKS clusters in the account
    cluster_names = eks.list_clusters()['clusters']
    eks_clusters=[]
    # Loop through each cluster and print its security group IDs
    for cluster_name in cluster_names:
        try:
            response = eks.describe_cluster(name=cluster_name)

            security_group_ids = response['cluster']['resourcesVpcConfig']['securityGroupIds']
            clusterSecurityGroupId = response['cluster']['resourcesVpcConfig']['clusterSecurityGroupId']
            if sg in security_group_ids or sg in clusterSecurityGroupId:
                eks_clusters.append(f"eks:cluster/{cluster_name}")
        except Exception as e:
            print(e)

    if not eks_clusters:
        eks_clusters=""
    else:
        eks_clusters = ' , '.join(eks_clusters)

    return eks_clusters



def find_codebuild(sg):
    cb_projects=[]
    try:
        cb_client = session.client('codebuild',region_name=region) 
        response = cb_client.list_projects()
        for project_name in response['projects']:
            response = cb_client.batch_get_projects(names=[project_name])
            security_group_ids = response['projects'][0]['vpcConfig']['securityGroupIds'][0]
            print(f"{project_name}: {security_group_ids}")
            if security_group_ids:
                if sg in security_group_ids:
                    print(f"yes {sg} is in {project_name}")
                    cb_projects.append(f"cb:project/{project_name}")
    except Exception as e:
        print(f"Error message: {e}")
    if not cb_projects:
        cb_projects=""
    else:
        cb_projects = ' , '.join(cb_projects)
    print(f"Here are cb_projects {cb_projects} for sg {sg}")
    return cb_projects




def find_ecache(sg):
    # Create a session using your AWS credentials
    ecache_clusters = set()
    try:
    # Create an ElastiCache client using the session
        ecache_client = session.client('elasticache', region_name=region)

        # Retrieve a list of ElastiCache clusters
        response = ecache_client.describe_cache_clusters()

        # Loop through each cluster and check if the security group is attached
        ecache_clusters = set()
        for cluster in response['CacheClusters']:
            cluster_id = cluster['CacheClusterId']
            security_groups = cluster['SecurityGroups']
            for group in security_groups:
                group_id = group['SecurityGroupId']
                if group_id == sg:
                    ecache_clusters.add(f"ecache:cluster/{cluster_id}")
                    break
    except Exception as e:
        print(f"Error message: {e}")
    if not ecache_clusters:
        ecache_clusters=""
    else:
        ecache_clusters = ' , '.join(ecache_clusters)
    return ecache_clusters


def find_elbs(sg):
    elb_names = []
    elbv2 = session.client('elbv2', region_name=region)
    try:
        
        response = elbv2.describe_load_balancers()
        for lb in response['LoadBalancers']:
            try:
                if sg in lb['SecurityGroups']:
                    elb_names.append(f"elb:{lb['LoadBalancerName']}")
                    print("yes, it was found in this alb")
            except:
                print("security group not found in this alb")

    except Exception as ex:
        print(ex)

    if not elb_names:
        elb_names=""
    else:
        elb_names = ' , '.join(elb_names)
    
    return elb_names






# iterate through the dev and prod sessions

for session in [ prod_session , staging_session, sandbox_session, dev_session, infra_session, security_session, logging_session ]:
#for session in [prod_session]:
#for session in [security_session]:
    # iterate through the regions
    for region in regions:
        try:
            ec2 = session.client('ec2', region_name=region)

            security_groups = ec2.describe_security_groups()['SecurityGroups']
            
            # iterate through the security groups and add to the table
            for sg in security_groups:
                #print(sg)
                resources =[]
                ec2_resources= find_ec2_instances(str(sg['GroupId']))
                rds_resources= find_rds(str(sg['GroupId']))
                elb_resources= find_elbs(str(sg['GroupId']))
                ecs_resources= find_ecs(str(sg['GroupId']))
                eks_resources= find_eks(str(sg['GroupId']))
                vpn_resources= find_vpn(str(sg['GroupId']))
                bs_resources = find_beanstalk_envs(str(sg['GroupId']))
                cb_resources = find_codebuild(str(sg['GroupId']))
                ecache_resources= find_ecache(str(sg['GroupId']))
                resources.append(ec2_resources)
                resources.append(rds_resources)
                resources.append(elb_resources)
                resources.append(ecs_resources)
                resources.append(eks_resources)
                resources.append(bs_resources)
                resources.append(vpn_resources)
                resources.append(cb_resources)
                resources.append(ecache_resources)

                while('' in resources):
                    resources.remove('')
                resources = ' , '.join(map(str, resources))

                print(f"this is my {resources}")
                for permission in sg['IpPermissions']:
                    protocol = permission['IpProtocol']
                    if protocol == '-1':
                        protocol = 'All Traffic'

                    if  permission.get('FromPort', '') == permission.get('ToPort', '') : 
                        portRange=   permission.get('FromPort', '')
                    else:
                        portRange =   f"{permission.get('FromPort', '')}-{permission.get('FromPort', '')}" 

                    for ip_range in permission.get('IpRanges', []):

                        row_count += 1
                        if (not ip_range['CidrIp'].startswith("sg-") and permission.get('FromPort', '') not in [443,80,8080] and not ip_range['CidrIp'].startswith("10." or "172." or "198.") and not ip_range['CidrIp'].endswith("/32") ):

                            table.add_row([f"<font color='red'>{row_count}</font>", f"<font color='red'>{session.profile_name}</font>", f"<font color='red'>{region}</font>", f"<font color='red'>{sg['GroupId']}</font>", f"<font color='red'>{sg['GroupName']}</font>",f"<font color='red'>{resources}</font>", f"<font color='red'>{protocol}</font>", f"<font color='red'>{portRange}</font>", f"<font color='red'>{ip_range['CidrIp']}</font>"])
                            print(permission.get('FromPort', ''))
                            
                        else:
                            table.add_row([row_count, session.profile_name, region, sg['GroupId'], sg['GroupName'],resources, protocol, portRange, ip_range['CidrIp']])
                    for ipv6_range in permission.get('Ipv6Ranges', []):
                        row_count += 1
                        if (not ip_range['CidrIp'].startswith("sg-") and permission.get('FromPort', '') not in [80,443,8080] and not ip_range['CidrIp'].startswith("10." or "172." or "198.") and not ip_range['CidrIp'].endswith("/32") ):
                            
                            table.add_row([f"<font color='red'>{row_count}</font>", f"<font color='red'>{session.profile_name}</font>", f"<font color='red'>{region}</font>", f"<font color='red'>{sg['GroupId']}</font>", f"<font color='red'>{sg['GroupName']}</font>", f"<font color='red'>{resources}</font>", f"<font color='red'>{protocol}</font>", f"<font color='red'>{portRange}</font>", f"<font color='red'>{ip_range['CidrIp']}</font>"])
                        else:
                            table.add_row([row_count, session.profile_name, region, sg['GroupId'], sg['GroupName'], resources, protocol, portRange, ipv6_range['CidrIpv6']])
                    for group_pair in permission.get('UserIdGroupPairs', []):
                        print(group_pair)
                        row_count += 1
                        table.add_row([row_count, session.profile_name, region, sg['GroupId'], sg['GroupName'],resources, protocol, portRange, group_pair['GroupId']])
        except ClientError as e:
            print(e)
        # except:
        #     print(region)

# get the HTML code for the table
html_string = html.unescape(table.get_html_string(attributes={"id": "network-table"}))
#.replace("&gt;",">").replace("&lt;","<").replace("&#x27;","'")

# add CSS style to the table
html_string = """
<body>
    <h2>AWS Security Groups</h2>
    <div class="search-box">
        <input type="text" id="search" onkeyup="searchTable()" placeholder="Search...">
        <input type="button" value="Search">
    </div>
<body>
 <style>
        table {
            border-collapse: collapse;
            width: 100%;
        }@keyframes changeColor {
        0% {
            color: gree;
        }
        16.7% {
            color: blue;
        }
        33.3% {
            color: rgb(91, 36, 180);
        }
        50% {
            color: orange;
        }
        66.7% {
            color: purple;
        }
        83.3% {
            color: pink;
        }
        100% {
            color: blue;
        }
    }

        h2 {
            animation: changeColor 15s ease-in-out infinite;text-align: center;
    }
        th{
        background-color: #065972;
        color: white;
    } td {
            text-align: left;
            padding: 8px;
            border: 1px solid #065972;
        }
        tr:nth-child(even) {
            background-color: #f2f2f2;
        }
        .search-box {
            margin-bottom: 10px;
        }
        .search-box input[type="text"] {
            padding: 8px;
            width: 100%;
            border: 1px solid #065972;
            border-radius: 4px;
        }
        .search-box input[type="button"] {
            margin-left: 10px;
            padding: 8px;
            border: none;
            background-color: #065972;
            color: #fff;
            border-radius: 4px;
            cursor: pointer;
        }
        .search-box input[type="button"]:hover {
            background-color: #44b4a6;
        }
        body {
  background: linear-gradient(to bottom, #d2ffce, #a2dbfa);
}
    </style>

        <script>
        function searchTable() {
            var input, filter, table, tr, td, i, txtValue;
            input = document.getElementById("search");
            filter = input.value.toUpperCase();
            table = document.getElementById("network-table");
            tr = table.getElementsByTagName("tr");
            for (i = 0; i < tr.length; i++) {
                td = tr[i].getElementsByTagName("td");
                for (j = 0; j < td.length; j++) {
                    txtValue = td[j].textContent || td[j].innerText;
                    if (txtValue.toUpperCase().indexOf(filter) > -1) {
                        tr[i].style.display = "";
                        break;
                    } else {
                        tr[i].style.display = "none";
                    }
                }
            }
        }
    </script>

""" + html_string

now = datetime.now()
dt_string = now.strftime("%d/%m/%Y %H:%M:%S")
html_string+= f'''<footer><p>Generated by Rupifi Security Team on {dt_string} as part of the ClearSky Security Project.</p></footer>'''

# write the modified HTML code to an HTML file
with open('securitygroups.html', 'w') as f:
    f.write(html_string)
    
# open the file in the default web browser
#os.system('open securitygroups.html')
#print(html_string)
