import boto3

# Create a session with the "security" profile
session = boto3.Session(profile_name='security')

# Create a Boto3 client for EC2 using the session
ec2 = session.client('ec2', region_name='ap-south-1')

# Rest of the code remains the same as the previous example




# Get a list of all security groups in the region
sg_response = ec2.describe_security_groups()

# Create an empty list to hold our results
sg_table = []

# Loop through each security group and find the resources attached


# Loop through each security group and find the resources attached


# Loop through each security group and find the resources attached
for sg in sg_response['SecurityGroups']:
    # Create a list of resource types to check
    resource_types = ['instances', 'network_interfaces', 'volumes']

    # Create an empty list to hold the attached resources
    attached_resources = []

    # Loop through each resource type and find the attached resources
    for resource_type in resource_types:
        if resource_type == 'instances':
            response = ec2.describe_instances(Filters=[{'Name': 'instance.group-id', 'Values': [sg['GroupId']]}])
            if 'Reservations' in response:
                for reservation in response['Reservations']:
                    for instance in reservation['Instances']:
                        attached_resources.append(instance)
        elif resource_type == 'volumes':
            response = ec2.describe_volumes(Filters=[{'Name': 'attachment.instance-id', 'Values': [i['InstanceId'] for i in attached_resources]}])
        elif resource_type == 'network_interfaces':
            response = ec2.describe_network_interfaces(Filters=[{'Name': 'group-id', 'Values': [sg['GroupId']]}])
            for resource in response['NetworkInterfaces']:
                if resource.get('Attachment') and resource['Attachment'].get('GroupId') == sg['GroupId']:
                    attached_resources.append(resource['NetworkInterfaceId'])
        else:
            response = getattr(ec2, 'describe_{0}'.format(resource_type))(Filters=[{'Name': 'group-id', 'Values': [sg['GroupId']]}])
            for resource in response['{0}s'.format(resource_type[:-1])]:
                attached_resources.append(resource['{0}Id'.format(resource_type[:-1].title())])

    # Add the security group and attached resources to the table
    sg_table.append({'SecurityGroup': sg['GroupName'], 'AttachedResources': ', '.join([resource['InstanceId'] for resource in attached_resources if 'InstanceId' in resource])})

# Print the table
print('{:<30} {}'.format('Security Group', 'Attached Resources'))
for row in sg_table:
    print('{:<30} {}'.format(row['SecurityGroup'], row['AttachedResources']))
