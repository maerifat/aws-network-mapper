import boto3
import webbrowser

# create session for each environment
sessions = {
    'prod': boto3.session.Session(profile_name='prod'),
    'dev': boto3.session.Session(profile_name='dev')
}

# iterate over sessions
for env, session in sessions.items():
    print(f"Environment: {env}")
    ec2_client = session.client('ec2')

    # get all regions for the session
    regions = [region['RegionName'] for region in ec2_client.describe_regions()['Regions']]

    sg_data = []
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
                        'region': region,
                        'env': env,
                        'sg_id': sg_id,
                        'sg_name': sg_name,
                        'protocol': protocol,
                        'port_range': f"{from_port}-{to_port}",
                        'source': source_cidr
                    })

                for source in rule['UserIdGroupPairs']:
                    source_sg_id = source.get('GroupId')

                    # add data to list
                    sg_data.append({
                        'region': region,
                        'env': env,
                        'sg_id': sg_id,
                        'sg_name': sg_name,
                        'protocol': protocol,
                        'port_range': f"{from_port}-{to_port}",
                        'source': source_sg_id
                    })

                # add data to list if all traffic is allowed from any source
                if len(rule['IpRanges']) == 1 and '0.0.0.0/0' in rule['IpRanges'][0]['CidrIp']:
                    sg_data.append({
                        'region': region,
                        'env': env,
                        'sg_id': sg_id,
                        'sg_name': sg_name,
                        'protocol': protocol,
                        'port_range': f"{from_port}-{to_port}",
                        'source': 'All Traffic'
                    })

                # check if all traffic is allowed


# generate HTML table
html = f'''
<html>
<head>
<style>
table {{
    font-family: arial, sans-serif;
    border-collapse: collapse;
    width: 100%;
}}

td, th {{
    border: 1px solid #dddddd;
    text-align: left;
    padding: 8px;
}}

th {{
    background-color: #dddddd;
}}

table tr:nth-child(even) {{
    background-color: #f2f2f2;
}}

#search {{
    float: right;
}}
</style>
</head>
<body>
<h2>Environment: {env}</h2>
<input type="text" id="search" onkeyup="searchTable()" placeholder="Search...">
<table id="security-table">
<thead>
<tr>
<th>Region</th>
<th>Security Group ID</th>
<th>Security Group Name</th>
<th>Protocol</th>
<th>Port Range</th>
<th>Source</th>
</tr>
</thead>
<tbody>
'''

for data in sg_data:
    sg_link = f'https://{data["region"]}.console.aws.amazon.com/ec2/v2/home?region={data["region"]}#SecurityGroup:groupId={data["sg_id"]}'
    html += f'<tr><td>{data["env"]}</td><td>{data["region"]}</td><td><a href="{sg_link}" target="_blank">{data["sg_id"]}</a></td><td>{data["sg_name"]}</td><td>{data["protocol"]}</td><td>{data["port_range"]}</td><td>{data["source"]}</td></tr>'

html += '''
</tbody>
</table>
<script>
function searchTable() {{
  // Declare variables
  var input, filter, table, tr, td, i, j, txtValue;
  input = document.getElementById("search");
  filter = input.value.toUpperCase();
  table = document.getElementById("security-table");
  tr = table.getElementsByTagName("tr");

  // Loop through all table rows, and hide those that don't match the search query
  for (i = 0; i < tr.length; i++) {{
    for (j = 0; j < tr[i].getElementsByTagName("td").length; j++) {{
      td = tr[i].getElementsByTagName("td")[j];
      if (td) {{
        txtValue = td.textContent || td.innerText;
        if (txtValue.toUpperCase().indexOf(filter) > -1) {{
          tr[i].style.display = "";
          break;
        }} else {{
          tr[i].style.display = "none";
        }}
      }}
    }}
  }}
}}
</script>
</body>
</html>
'''


# write html to file
with open('securitygroups.html', 'w') as f:
    f.write(html)

# open file in web browser
webbrowser.open('securitygroups.html')
