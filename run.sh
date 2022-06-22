#!/bin/bash

#variables
dbName="networks.db"
tableName="NETWORKMAP"
profileName="brightchamps"


accountId=$(aws sts get-caller-identity --profile $profileName --query "Account" --output text)

getRegions() {

    regionArray=($(aws ec2 describe-regions --query "Regions[].RegionName" --output text))

}


#create table function
createTable() {
    sqlite3 $dbName "CREATE TABLE  $tableName (ID INTEGER PRIMARY KEY AUTOINCREMENT, AccountId text, \
    RegionName text, InstanceId text , State text, IpAddress text, SecurityGroups text, OpenPorts text);"
}



if [  -f $dbName ]; then
    echo "There is alreay database with same name, so deleting and creating new one as $dbName"
    rm -f $dbName
    createTable;
else
    echo "Creating database as $dbName"
    createTable;
fi

insertTable () {

    sqlite3 $dbName "INSERT INTO $tableName (AccountId , RegionName , InstanceId, State , IpAddress , SecurityGroups, OpenPorts) \
    Values ('$accountId', '$regionName', '$instanceId', 'running', '$ip', '$sgsString', ' ' )"
}

fetchData(){
    sqlite3 $dbName "SELECT * FROM $tableName"
}

fetchIps(){


    getRegions;
    

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
               sgsArray=($(aws ec2 describe-instances --profile $profileName \
               --query 'Reservations[*].Instances[?PublicIpAddress==`'$ip'`][].SecurityGroups[].GroupId' \
               --output text))


                sgsString=$(echo "${sgsArray[@]}" | tr ' ' ',')



                instanceId=$(aws ec2 describe-instances \
                --profile $profileName --query 'Reservations[].Instances[?PublicIpAddress==`'$ip'`][].InstanceId' \
                --output text)

                portsToScanArray=();

                for sgName in "${sgsArray[@]}";do


                    aws ec2 describe-security-groups --output text --profile $profileName --region $regionName \
                    --group-ids $sgName | grep -i permission| grep -vi egress > tempsg.txt
                    while read -r line;
                    do
                        c2=$(echo "$line"| cut -f2);
                        c3=$(echo "$line"| cut -f3);
                        c4=$(echo "$line"| cut -f4) ;
                        if [ "$c3" == "-1" ];then
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
                    echo "pors for $sgName : $portsToScanString"

                done

                echo "$portsToScanString"



               insertTable

            #    echo "${sgsArray[@]}"
            #    echo "$regionName"
            #    echo "$accountId"
            #    echo "$instanceId"

               #fetchData



               

            done

        fi

    done

   # for ip in ${ipsArray[@]};do echo $ip ;done

    
}


#fetch data from NETWORKMAP table
fetchData(){
    sqlite3 $dbName "SELECT * FROM $tableName"
}






fetchData
fetchIps
