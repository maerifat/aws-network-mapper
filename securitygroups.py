import boto3
import webbrowser

# create session for each environment
sessions = {
    'prod': boto3.session.Session(profile_name='prod'),
    'dev': boto3.session.Session(profile_name='dev')
}

sg_data = []
# iterate over sessions
for env, session in sessions.items():
    print(f"Environment: {env}")
    ec2_client = session.client('ec2')

    # get all regions for the session
    regions = [region['RegionName'] for region in ec2_client.describe_regions()['Regions']]

    # iterate over regions
    for region in regions:
        print(f"Region: {region}")
        ec2 = session.resource('ec2', region_name=region)

        # get all security groups in the region
        security_groups = ec2.security_groups.all()

        # iterate over security groups
        for sg in security_groups:
            sg_id = sg.id
            sg_name = sg.group_name

            # iterate over ingress rules
            for rule in sg.ip_permissions:
                # get port range
                if 'FromPort' in rule:
                    from_port = rule['FromPort']
                else:
                    from_port = 'N/A'

                if 'ToPort' in rule:
                    to_port = rule['ToPort']
                else:
                    to_port = 'N/A'

                # get protocol
                protocol = rule['IpProtocol']

                # get source
                for source in rule['IpRanges']:
                    source_cidr = source['CidrIp']

                    # add data to list
                    sg_data.append({
                        'env': env,
                        'region': region,
                        'sg_id': sg_id,
                        'sg_name': sg_name,
                        'protocol': protocol,
                        'port_range': f"{from_port}-{to_port}",
                        'source': source_cidr
                    })

# generate HTML table
html = '<html><head></head><body>'
html += '<h1>Security Groups</h1>'
html += '<table border="1"><tr><th>Environment</th><th>Region</th><th>Security Group ID</th><th>Security Group Name</th><th>Protocol</th><th>Port Range</th><th>Source</th></tr>'

for data in sg_data:
    sg_link = f'https://{data["region"]}.console.aws.amazon.com/ec2/v2/home?region={data["region"]}#SecurityGroup:groupId={data["sg_id"]}'
    html += f'<tr><td>{data["env"]}</td><td>{data["region"]}</td><td><a href="{sg_link}" target="_blank">{data["sg_id"]}</a></td><td>{data["sg_name"]}</td><td>{data["protocol"]}</td><td>{data["port_range"]}</td><td>{data["source"]}</td></tr>'

html += '</table></body></html>'

# write html to file
with open('securitygroups.html', 'w') as f:
    f.write(html)

# open file in web browser
webbrowser.open('securitygroups.html')
