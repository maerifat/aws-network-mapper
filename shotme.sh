#!/bin/bash

#Dependencies

#https://github.com/maaaaz/webscreenshot
#https://github.com/ajaxray/merge2pdf
#phantomjs
#imagemagick


#variables
staticPath="/security/tools/nmapAutomator"
dbName="networks.db"
tableName="networkmap"
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
    openPortsArray=( $(echo $portsopen| tr ',' ' '))
    usedPortsArray=( $(echo $portsused| tr '-' ','|tr ',' ' ' ))

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
cd $staticPath/$outputDir && merge2pdf $staticPath/$screenshotsDir/screenshot_${RANDOM}.pdf $(ls | grep -i label) 
