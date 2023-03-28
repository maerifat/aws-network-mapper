import boto3
from prettytable import PrettyTable
import os
from datetime import datetime
from markupsafe import Markup
import html

# set up the AWS sessions for dev and prod

prod_session = boto3.Session(profile_name='prod')
dev_session = boto3.Session(profile_name='dev')

# get the list of AWS regions


#regions = prod_session.get_available_regions('ec2')
#regions= ['af-south-1', 'ap-east-1', 'ap-northeast-1', 'ap-northeast-2', 'ap-northeast-3', 'ap-south-1', 'ap-south-2', 'ap-southeast-1', 'ap-southeast-2', 'ap-southeast-3', 'ap-southeast-4', 'ca-central-1', 'eu-central-1', 'eu-central-2', 'eu-north-1', 'eu-south-1', 'eu-south-2', 'eu-west-1', 'eu-west-2', 'eu-west-3', 'me-central-1', 'me-south-1', 'sa-east-1', 'us-east-1', 'us-east-2', 'us-west-1', 'us-west-2']
#print(regions)
regions=['ap-south-1']

#regions= ['ap-south-1']
# set up the HTML table
table = PrettyTable(['S. No.', 'Account', 'Region', 'SecurityGroupId', 'Security Group Name', 'Protocol', 'Port Range', 'Source'], escape=False)
table.align = "l"

# initialize row count
row_count = 0

# iterate through the dev and prod sessions

for session in [ dev_session,prod_session]:
    # iterate through the regions
    for region in regions:
        try:
            ec2 = session.client('ec2', region_name=region)
            security_groups = ec2.describe_security_groups()['SecurityGroups']
            
            # iterate through the security groups and add to the table
            for sg in security_groups:
                for permission in sg['IpPermissions']:
                    protocol = permission['IpProtocol']
                    if protocol == '-1':
                        protocol = 'All Traffic'

                    if  permission.get('FromPort', '') == permission.get('ToPort', '') : 
                        portRange=   permission.get('FromPort', '')
                    else:
                        portRange =   f"{permission.get('FromPort', '')}-{permission.get('FromPort', '')}" 

                    for ip_range in permission.get('IpRanges', []):
                        # print(ip_range['CidrIp'])
                        # print(permission.get('FromPort', ''))
                        # print(permission.get('ToPort', ''))



                        row_count += 1
                        if (not ip_range['CidrIp'].startswith("sg-") and permission.get('FromPort', '') not in [443,80,8080] and not ip_range['CidrIp'].startswith("10." or "172." or "198.") and not ip_range['CidrIp'].endswith("/32") ):

                            table.add_row([f"<font color='red'>{row_count}</font>", f"<font color='red'>{session.profile_name}</font>", f"<font color='red'>{region}</font>", f"<font color='red'>{sg['GroupId']}</font>", f"<font color='red'>{sg['GroupName']}</font>", f"<font color='red'>{protocol}</font>", f"<font color='red'>{portRange}</font>", f"<font color='red'>{ip_range['CidrIp']}</font>"])
                            print(permission.get('FromPort', ''))
                            
                        else:
                            table.add_row([row_count, session.profile_name, region, sg['GroupId'], sg['GroupName'], protocol, portRange, ip_range['CidrIp']])
                    for ipv6_range in permission.get('Ipv6Ranges', []):
                        row_count += 1
                        if (not ip_range['CidrIp'].startswith("sg-") and permission.get('FromPort', '') not in [80,443,8080] and not ip_range['CidrIp'].startswith("10." or "172." or "198.") and not ip_range['CidrIp'].endswith("/32") ):
                            
                            table.add_row([f"<font color='red'>{row_count}</font>", f"<font color='red'>{session.profile_name}</font>", f"<font color='red'>{region}</font>", f"<font color='red'>{sg['GroupId']}</font>", f"<font color='red'>{sg['GroupName']}</font>", f"<font color='red'>{protocol}</font>", f"<font color='red'>{portRange}</font>", f"<font color='red'>{ip_range['CidrIp']}</font>"])
                        else:
                            table.add_row([row_count, session.profile_name, region, sg['GroupId'], sg['GroupName'], protocol, portRange, ipv6_range['CidrIpv6']])
                    for group_pair in permission.get('UserIdGroupPairs', []):
                        print(group_pair)
                        row_count += 1
                        table.add_row([row_count, session.profile_name, region, sg['GroupId'], sg['GroupName'], protocol, portRange, group_pair['GroupId']])
        except:
            print({region})

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
