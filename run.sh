#!/bin/bash

#variables
dbName="networks.db"
tableName="NETWORKMAP"
profileName="brightchamps"
accountId=$(aws sts get-caller-identity --profile $profileName --query "Account" --output text)

#Get an array of all the regions
getRegions() {
    regionArray=($(aws ec2 describe-regions --query "Regions[].RegionName" --output text))
}

#create table function
createTable() {
    sqlite3 $dbName "CREATE TABLE  $tableName (ID INTEGER PRIMARY KEY AUTOINCREMENT, AccountId text, \
    RegionName text, InstanceId text ,InstanceName text, State text, IpAddress text, SecurityGroups text, \
    PortsUsed text, PortsOpen text, Services text);"
}

#Create new database 
if [  -f $dbName ]; then
    echo "There is alreay database with same name, so deleting and creating new one as $dbName"
    rm -f $dbName
    createTable;
else
    echo "Creating database as $dbName"
    createTable;
fi

#Insert into table function
insertTable () {
    sqlite3 $dbName "INSERT INTO $tableName (AccountId , RegionName , InstanceId, InstanceName, State , IpAddress , SecurityGroups, PortsUsed, PortsOpen, Services) \
    Values ('$accountId', '$regionName', '$instanceId', '$tagName' , 'running', '$ip', '$sgsString', '$portsToScanString' ,'$openPortsString', '$servicesString' )"
}

#Fetch from table function
fetchData(){
    sqlite3 $dbName "SELECT * FROM $tableName"
}

#Fetch Ips  and scan function
fetchIps(){
    getRegions;

    #Get Ips and their instances across all the regions
    for regionName in "${regionArray[@]}";do 
        instancesArray=($(aws ec2 describe-instances --profile $profileName \
        --query "Reservations[].Instances[].InstanceId[]"  \
        --output text ))
        ipsArray=($(aws ec2 describe-instances --profile $profileName --region $regionName \
        --query 'Reservations[*].Instances[?State.Name==`running`].PublicIpAddress[]' \
        --output text))
        if [ -z "$ipsArray" ]; then
            echo "[+] There are no instances in $regionName region."
        else
            echo "[+] These are the instances in $regionName region :"
            echo
            echo "${instancesArray[@]}"
            echo
            for ip in "${ipsArray[@]}";do 
               echo "Fetching details of $ip : "

               #Security Groups
               sgsArray=($(aws ec2 describe-instances --profile $profileName \
               --query 'Reservations[*].Instances[?PublicIpAddress==`'$ip'`][].SecurityGroups[].GroupId' \
               --output text))
                sgsString=$(echo "${sgsArray[@]}" | tr ' ' ',')

                #instanceIds
                instanceId=$(aws ec2 describe-instances \
                --profile $profileName --query 'Reservations[].Instances[?PublicIpAddress==`'$ip'`][].InstanceId' \
                --output text)

                #Name of the instance
                tagName=$(aws ec2 describe-instances --profile $profileName \
                --query 'Reservations[*].Instances[?PublicIpAddress==`'$ip'`][].Tags[?Key==`Name`][].Value' \
                --output text)
                portsToScanArray=();
                for sgName in "${sgsArray[@]}";do

                    #Save Security group data in text format
                    aws ec2 describe-security-groups --output text --profile $profileName --region $regionName \
                    --group-ids $sgName | grep -i permission| grep -vi egress > tempsg.txt
                    while read -r line;
                    do
                    c2=$(echo "$line"| awk '{print $2}');
                    c3=$(echo "$line"| awk '{print $3}');
                    c4=$(echo "$line"| awk '{print $4}') ;
                    if [ "$c2" == "-1" ];then
                            portsToScanArray+=("1-65535")
                        fi
                        if [ "$c4" != "" ]; then
                            if [ "$c2" == "$c4" ];then
                                portsToScanArray+=("$c2")
                            else
                                portsToScanArray+=("$c2-$c4")
                            fi
                        fi
                    done < tempsg.txt
                    portsToScanString=$(echo "${portsToScanArray[@]}" | tr ' ' ',')
                    echo "[+] Ports used for $sgName : $portsToScanString"
                done
                echo "Total Ports Used : $portsToScanString"
                if [ "$portsToScanString" != "" ]; then 
                    if ! grep "-" <<< "$portsToScanString" ;then 
                        echo "[+] nmap command : nmap '$ip' -p '$portsToScanString' -Pn --open |grep -i open > nmapresults.txt"

                        #scan for ports used
                        nmapCmd=$(nmap "$ip" -p "$portsToScanString" -Pn --open |grep -i open > nmapresults.txt)
                        if [ $(wc -l nmapresults.txt |awk '{print $1}') -gt 0 ] ; then
                            openPortsArray=();
                            servicesArray=();
                            while read -r line;
                            do
                                openPort=$(echo "$line"| awk '{print $1}'| cut -d "/" -f1);
                                openPortsArray+=("$openPort")
                                service=$(echo "$line"| awk '{print $3}');
                                servicesArray+=("$service")
                                openPortsString=$(echo "${openPortsArray[@]}" | tr ' ' ',')
                                servicesString=$(echo "${servicesArray[@]}" | tr ' ' ',')
                            done < nmapresults.txt
                        else
                            openPortsString="None"
                            servicesString="None"
                        fi
                    else
                        openPortsString="Ignored"
                        servicesString="Ignored"
                    fi
                else
                    openPortsString="None"
                    servicesString="None"
                    portsToScanString="None"
                fi
                echo "[+] Open Ports : $openPortsString"
                echo "[+] Services Running : $servicesString"
                echo "[+] Data is being inserted into the table $tableName"
                insertTable
            #    echo "${sgsArray[@]}"
            #    echo "$regionName"
            #    echo "$accountId"
            #    echo "$instanceId"
                echo "[+] Fetching data from table $tableName"
                fetchData
            done
        fi
    done
   # for ip in ${ipsArray[@]};do echo $ip ;done  
}

#save data from NETWORKMAP table 
saveData(){
    fetchData > rawsqlite3output.txt
}
fetchIps
echo "[+] We are formating data for you"
sqlite3 $dbName "select * from $tableName" > rawdata.txt

cat rawdata.txt| awk -F "|" 'BEGIN{ print "\
<style style='text/css'> \
.hoverTable{ width:100%\; border-collapse:collapse\; } \
.hoverTable td{ padding:7px\; border:#030e4f 1px solid\; } \
.hoverTable tr{ background: white\; } \
.hoverTable tr:hover { background-color: #ffff99\; } \
#myInput {\
  background-image: url('https://i.ibb.co/tH3t5T2/search.png'\)\;\
  background-size: 28px 30px \;\
  background-position: 10px 10px\;\
  background-repeat: no-repeat\;\
  width: 25%\;\
  color: #f49f1c\;\
  font-size: 16px\;\
  padding: 12px 20px 12px 40px\;\
  border: 3px solid #030e4f\;\
  border-radius: 25px\;\
  margin-bottom: 12px\;\}\
</style>\
<input type=\"text\" id=\"myInput\" onkeyup='myFunction\(\)' placeholder=\"Search Here\">\
<a>&emsp;</a>\
<a style=\"color:#030e4f\;\ font-weight: bold\; font-size: large;\"  id=\"totalRows\"></a>\
<a style=\"color:#030e4f\;\ font-weight: bold\; font-size: large;\"  id=\"rowCount\"></a>\
<a>&emsp;</a>\
<a style=\"color:#030e4f\;\ font-weight: bold\; font-size: large;\"  id=\"results\"></a>\
<a style=\"color:#030e4f\;\ font-weight: bold\; font-size: large;\"  id=\"resultCount\"></a>\
<table id=\"myTable\" class=\"hoverTable\" style='width:100%\;border-color:#f49f1c\;border-collapse:collapse' border='2'><tbody>\
<tr>\
<th style='height:30px\;width:3%\;background-color:#030e4f\;color:#f49f1c' scope='row'>S.No</th>\
<th style='width:4%\;background-color:#030e4f\;color:#f49f1c' scope='row'>Account Id</th>\
<th  style='width:7%\;background-color:#030e4f\;color:#f49f1c' scope='row'>Region Name</th>\
<th  style='width:10%\;background-color:#030e4f\;color:#f49f1c' scope='row'>Instance Id</th>\
<th  style='width:10%\;background-color:#030e4f\;color:#f49f1c' scope='row'>Instance Name</th>\
<th  style='width:5%\;background-color:#030e4f\;color:#f49f1c' scope='row'>State</th>\
<th  style='width:8%\;background-color:#030e4f\;color:#f49f1c' scope='row'>Ip Address</th>\
<th  style='width:20%\;background-color:#030e4f\;color:#f49f1c' scope='row'>Security Groups</th>\
<th  style='width:10%\;background-color:#030e4f\;color:#f49f1c' scope='row'>Ports Used</th>\
<th  style='width:10%\;background-color:#030e4f\;color:#f49f1c' scope='row'>Ports Open</th>\
<th  style='width:12%\;background-color:#030e4f\;color:#f49f1c' scope='row'>Services</th>\
</tr>\
"\
}{\
c1 = "<tr><td style='background-color:#030e4f\;color:#f49f1c\;border-color:#f49f1c'>"$1"</td>"; \
c2 = "<td style='border-color:#f49f1c'>"$2"</td>";\
c3 = "<td style='border-color:#f49f1c'>"$3"</td>";\
c4 = "<td style='border-color:#f49f1c'>"$4"</td>";\
c5 = "<td style='border-color:#f49f1c'>"$5"</td>";\
c6 = "<td style='border-color:#f49f1c'>"$6"</td>";\
c7 = "<td style='border-color:#f49f1c'>"$7"</td>";\
c8 = "<td style='border-color:#f49f1c'>"$8"</td>";\
c9 = "<td style='border-color:#f49f1c'>"$9"</td>";\
c10 = "<td style='border-color:#f49f1c'>"$10"</td>";\
c11 = "<td style='border-color:#f49f1c'>"$11"</td></tr>";\

print  c1 c2 c3 c4 c5 c6 c7 c8 c9 c10 c11}END \
\
\
\
{print "</tr></tbody></table>\
<script>\
 function myFunction\(\) \{\
 const rowCountSet = new Set\(\)\;\
  var input, filter, table, tr, th, td, i\;\
  input = document.getElementById\(\"myInput\"\)\;\
  filter = input.value.toUpperCase\(\)\;\
  table = document.getElementById\(\"myTable\"\)\;\
  var totalResults = 0\;\
  var rows = table.getElementsByTagName\(\"tr\"\)\;\
  for \(i = 0; i < rows.length; i++\) \{\
  	rowCount++\;\
    var cells = rows[i].getElementsByTagName\(\"td\"\)\;\
    var j\;\
    const myArr = [];\
    var rowContainsFilter = false\;\
    for \(j = 0\; j < cells.length\; j++\) \{\
      if \(cells[j]\) \{\
        if \(cells[j].innerHTML.toUpperCase\(\).indexOf\(filter\) > -1\) \{\
          rowCountSet.add\(i)\;\
          rowContainsFilter = true\;\
          totalResults++\;\
          continue\;\
        \}\
      \}\
    \}\
    if \(! rowContainsFilter\) \{\
      rows[i].style.display = \"none\"\;\
          rows[0].style.display = \"\"\;\
    \} else \{\
      rows[i].style.display = \"\"\;\
           rows[0].style.display = \"\"\;\
            \}\}\
                       document.getElementById(\"rowCount\").innerHTML = rowCountSet.size\;\
                       document.getElementById(\"totalRows\").innerHTML = \"Rows: \"\;\
                       document.getElementById(\"resultCount\").innerHTML = totalResults\;\
                       document.getElementById(\"results\").innerHTML = \"Results: \"\;\
            \}\
</script>\
\
\
\
"}' > output.html
echo "[+] Data has been saved in output.html"

