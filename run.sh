#!/bin/bash

#variables
dbName="networks.db"
tableName="NETWORKMAP"
staticPath="/security/STAGE/aws/networkmapper"
profileName="tmp"
tempSecurityGroupFile="tempsg.txt"
nmapResultsFile="nmapresults.txt"
tableDataFile="tabledata.txt"
uiHtmlFile=Network_Mapper_${RANDOM}_`date +"%Y-%m-%d"`.html
bucketName="appsec"
screenshotsFile=Screenshots_${RANDOM}_`date +"%Y-%m-%d"`.pdf
niktoResultsFile=Nikto_Results_${RANDOM}_`date +"%Y-%m-%d"`.txt
nmapFile=Nmap_Results_${RANDOM}_`date +"%Y-%m-%d"`.txt

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
    Values ('$accountId', '$regionName', '$instanceId', '$tagName' , 'running', '$ip', '$sgsString', '$portsWithProtocolString' ,'$openPortsString', '$servicesString' )"
}

#Fetch from table function
fetchData(){
    sqlite3 $dbName "SELECT * FROM $tableName"
}

#Fetch Ips  and scan function
fetchAndScan(){
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
                portsWithProtocolArray=();
                for sgName in "${sgsArray[@]}";do

                    #Save Security group data in text format
                    aws ec2 describe-security-groups --output text --profile $profileName --region $regionName \
                    --group-ids $sgName | grep -i permission| grep -vi egress > $staticPath/$tempSecurityGroupFile
                    while read -r line;
                    do
                    c2=$(echo "$line"| awk '{print $2}');
                    c3=$(echo "$line"| awk '{print $3}');
                    c4=$(echo "$line"| awk '{print $4}') ;

                    #When all ports are used
                    if [ "$c2" == "-1" ];then
                            portsToScanArray+=("1-65535")
                            portsWithProtocolArray+=("All_Traffic")
                    fi

                    #When 
                    if [ "$c4" != "" ] && [ "$c2" != "-1" ]; then
                        if [ "$c2" == "$c4" ];then
                            portsToScanArray+=("$c2")
                            portsWithProtocolArray+=("$c2/$c3")
                        else
                            portsToScanArray+=("$c2-$c4")
                            portsWithProtocolArray+=("$c2-$c4/$c3")
                        fi
                    fi
                    done < $staticPath/$tempSecurityGroupFile
                    portsToScanString=$(echo "${portsToScanArray[@]}" | tr ' ' ',')
                    portsWithProtocolString=$(echo "${portsWithProtocolArray[@]}" | tr ' ' ',')
                    echo "[+] Ports used for $sgName : $portsToScanString"
                done
                echo "Total Ports Used : $portsToScanString"
                if [ "$portsToScanString" != "" ]; then 
                    if ! grep "-" <<< "$portsToScanString" ;then 
                        echo "[+] nmap command : nmap '$ip' -p '$portsToScanString' -Pn --open |grep -i open > $staticPath/$nmapResultsFile"

                        #scan for ports used
                        nmapCmd=$(nmap "$ip" -p "$portsToScanString" -Pn --open |grep -i open > $staticPath/$nmapResultsFile)
                        if [ $(wc -l $staticPath/$nmapResultsFile |awk '{print $1}') -gt 0 ] ; then
                            openPortsArray=();
                            servicesArray=();
                            while read -r line;
                            do
                                openPort=$(echo "$line"| awk '{print $1}');
                                openPortsArray+=("$openPort")
                                service=$(echo "$line"| awk '{print $3}');
                                servicesArray+=("$service")
                                openPortsString=$(echo "${openPortsArray[@]}" | tr ' ' ',')
                                servicesString=$(echo "${servicesArray[@]}" | tr ' ' ',')
                            done < $staticPath/$nmapResultsFile
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
    fetchData > $staticPath/rawsqlite3output.txt
}

fetchAndScan

echo "[+] We are formating data for you"
sqlite3 $dbName "select * from $tableName" | awk -F "|" 'BEGIN{ print "\
<style style='text/css'> \
.hoverTable{ width:100%\; border-collapse:collapse\; } \
.hoverTable td{ padding:7px\; border:#030e4f 1px solid\; } \
.hoverTable tr{ background: white\; } \
.hoverTable tr:hover { background-color: #ffff99\; } \
#myInput {\
  background-image: url('https://srv2.imgonline.com.ua/result_img/imgonline-com-ua-ReplaceColor-kQAKWoJYh9mvz.jpg'\)\;\
  background-size: 28px 30px \;\
  background-position: 10px 10px\;\
  background-repeat: no-repeat\;\
  width: 25%\;\
  color: #030e4f\;\
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
gsub("All_Traffic","<font color='red'>All_Traffic</font>",c9);\
gsub("0-65535","<font color='red'>0-65535</font>",c9);\
gsub("Ignored","<font color='red'>Ignored</font>",c11);\
gsub("Ignored","<font color='red'>Ignored</font>",c10);\
gsub("udp","<font color='magenta'>udp</font>",c9);\
gsub(","," , ",c8);\
gsub(","," , ",c9);\
gsub(","," , ",c10);\
gsub(","," , ",c11);\
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
"}' >  $staticPath/$outputDir/$uiHtmlFile


echo "[+] Data has been saved in output.html"
aws s3 cp  $staticPath/$outputDir/$uiHtmlFile s3://$bucketName/networkmapper/$uiHtmlFile --profile $profileName
uiHtmlFileUrl=$(aws s3 presign s3://$bucketName/networkmapper/$uiHtmlFile --expires-in 604800 --profile $profileName)
echo "$uiHtmlFileUrl"

#SCREEN SHOT TAKER

#!/bin/bash

#Dependencies

#https://github.com/maaaaz/webscreenshot
#https://github.com/ajaxray/merge2pdf
#phantomjs
#imagemagick


#variables
urlsFile="workingurls.txt"
outputDir="output"
screenshotsDir="myscreenshots"

#create Directories

if [ -d "$staticPath/$outputDir" ] ;then 
    rm -r $staticPath/$outputDir
    mkdir $staticPath/$outputDir
else
    mkdir $staticPath/$outputDir
fi

if [ ! -d "$staticPath/$screenshotsDir" ] ;then 
    mkdir $staticPath/$screenshotsDir
fi

#Tatal number of rows in db
totalRows=$(sqlite3 $staticPath/$dbName "select count(*) from $tableName")

echo "[+] Total Rows: $totalRows"
echo

#Through all the ip addresses
for id in `seq 1 $totalRows`;do

    ipaddress=$(sqlite3 $staticPath/$dbName "select IpAddress from $tableName where id=$id")
    #echo "[+] IpAddress: $ipaddress"
    portsopen=$(sqlite3 $staticPath/$dbName "select portsopen from $tableName where id=$id")
    portsused=$(sqlite3 $staticPath/$dbName "select portsused from $tableName where id=$id")
    #echo "[+] Open Ports: $portsopen"
    openPortsArray=( $(echo $portsopen| tr ',' ' '|tr -d "_"|tr -d "/"| sed -e 's/[[:alpha:]]//g'))
    usedPortsArray=( $(echo $portsused| tr '-' ','|tr ',' ' ' | tr -d "_"|tr -d "/"| sed -e 's/[[:alpha:]]//g'))

    #merge ports incase large ranges are not used for port scanning
    portToTryOver=("${openPortsArray[@]}" "${usedPortsArray[@]}")

    #unique ports 
    portToTryOver=($(printf "%s\n" "${portToTryOver[@]}" | sort -u))
    echo " Total ports to try over ${portToTryOver[*]}"

    #Through all the ports of an ipaddress
    for port in "${portToTryOver[@]}";do
        url="http://$ipaddress:$port"

        #check whether we can get the http status code or not on these ports
        statusCode=$(curl -s -o /dev/null -I -w "%{http_code}" $url --max-time 5)

        #only take forward working http urls
        if [ $statusCode -gt 99 ] && [ $statusCode -lt 600 ] ;then
            echo "[+] status code: $statusCode for $url"
            echo "$url" >> $staticPath/$outputDir/$urlsFile 
        fi
    done
    echo 
done

#take screenshots in png format of all urls inside $outputDir/$urlsFile
webscreenshot -i $staticPath/$outputDir/$urlsFile -f png -o $outputDir --label

#Merge all png files into one pdf 
cd $staticPath/$outputDir && merge2pdf $staticPath/$screenshotsDir/$screenshotsFile $(ls | grep -i label) 

aws s3 cp  $staticPath/$screenshotsDir/$screenshotsFile  s3://$bucketName/screenshots/$screenshotsFile --profile $profileName
screenshotsFileUrl=$(aws s3 presign s3://$bucketName/screenshots/$screenshotsFile --expires-in 604800 --profile $profileName)
echo $screenshotsFileUrl
#NIKTO SCANNER

echo "STARTING NIKTO SCANNER"


for host in $(cat $staticPath/$outputDir/$urlsFile);do
	nikto -host $host | tee -a $staticPath/$outputDir/$niktoResultsFile
done  


aws s3 cp $staticPath/$outputDir/$niktoResultsFile  s3://$bucketName/nikto/$niktoResultsFile --profile $profileName
niktoResultsFileUrl=$(aws s3 presign s3://$bucketName/nikto/$niktoResultsFile --expires-in 604800 --profile $profileName)

echo $niktoResultsFileUrl



## NMAP SCANNER

totalRows=$(sqlite3 $staticPath/$dbName "select count(*) from $tableName")

echo "[+] Total Rows: $totalRows"
echo
for id in `seq 1 $totalRows`;do

    ipaddress=$(sqlite3 $staticPath/$dbName "select IpAddress from $tableName where id=$id")
    #echo "[+] IpAddress: $ipaddress"
    portsopen=$(sqlite3 $staticPath/$dbName "select portsopen from $tableName where id=$id")
    portsused=$(sqlite3 $staticPath/$dbName "select portsused from $tableName where id=$id")
    #echo "[+] Open Ports: $portsopen"
    openPortsArray=( $(echo $portsopen| tr ',' ' '|tr -d "_"|tr -d "/"| sed -e 's/[[:alpha:]]//g'))
    usedPortsArray=( $(echo $portsused| tr '-' ','|tr ',' ' ' | tr -d "_"|tr -d "/"| sed -e 's/[[:alpha:]]//g'))

    #merge ports incase large ranges are not used for port scanning
    portToTryOver=("${openPortsArray[@]}" "${usedPortsArray[@]}")
    

    #unique ports 
    portToTryOver=($(printf "%s\n" "${portToTryOver[@]}" | sort -u))
    nmapPortsToTryOver=$(echo "${portToTryOver[@]}"|tr " " ",")
    echo "[+] Target = $ipaddress:$nmapPortsToTryOver"

    #Through all the ports of an ipaddress
    
    nmap $ipaddress  -A -T4 -Pn -p $nmapPortsToTryOver --script vulners,vuln   --open | tee -a  $staticPath/$outputDir/$nmapFile

    #--script-args mincvss=7.0

    echo
    echo

    
done

aws s3 cp $staticPath/$outputDir/$nmapFile  s3://$bucketName/portscan/$nmapFile --profile $profileName
nmapResultsFileUrl=$(aws s3 presign s3://$bucketName/portscan/$nmapFile --expires-in 604800 --profile $profileName)

echo $nmapResultsFileUrl
