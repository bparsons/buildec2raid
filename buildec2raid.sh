#!/bin/bash

########
##
##  Build RAID 10 array in Amazon EC2
## -----------------------------------
##
##  Brian Parsons <brian@pmex.com>
##
##  Creates EBS volumes in Amazon EC2 and associates them with an EC2 instance for use as a RAID array
##

##  Requirements
## --------------
##
##  ec2-api-tools - http://aws.amazon.com/developertools/351
##
##  !!!!!!!!        !!!!!!!!
##  !!!!!!!! NOTICE !!!!!!!!  BEFORE CALLING THIS SCRIPT:
##  !!!!!!!!        !!!!!!!!
##
##  ec2-api-tools must be working and your environment variables set up:
##
##    AWS_USER_ID
##    AWS_ACCESS_KEY_ID
##    AWS_SECRET_ACCESS_KEY
##    EC2_PRIVATE_KEY
##    EC2_CERT
#

##  Usage
## -------
##
##  buildec2raid.sh -s <size> -z <zone> -i <instance> [-d drive id] [-o iops]
##
##       size - the usable size of the raid array (in GB)
##       zone - the availability zone
##       instance - the ec2 instance id to attach to
##       drive id (optional) - the drive id to use in association with the instance (defaults to sdh)
##       iops (optional) - the requested number of I/O operations per second that the volume can support
#

##  Examples
## ----------
##
##  ./buildec2raid.sh -s 1024 -z us-east-1a -i i-9i8u7y7y
##
##      - this would create a 1TB array in us-east-1a attached to i-918u7y7y
##
##  ./buildec2raid.sh -s 128 -z us-east-1d -i i-715e8e8v -o 100
##
##      - this would create a 128GB array in us-east-1d attached to i-715e8e8v with 100 IOPS per second provisioned for each volume in the array.
#

##
## The MIT License (MIT)
## Copyright (c) 2012-2013 Brian Parsons
##
## Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"),
## to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense,
## and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
##
## The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
## WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
##
#

##
## VARIABLES
#

# List of valid AWS Zones
AWSZONES=" us-east-1a us-east-1b us-east-1d us-east-1e us-west-1a us-west-1b us-west-1c us-west-2a us-west-2b us-west-2c eu-west-1a eu-west-1b eu-west-1c ap-southeast-1a ap-southeast-1b ap-northeast-1a ap-northeast-1b sa-east-1a sa-east-1b "

# Default Number of Disks for the array (8 is considered ideal)
DISKS=8

# Default Drive ID
DRIVEID="sdh"

##
## END VARIABILE DEFINITIONS
#

##
## FUNCTIONS
#

# Confirmation Prompt
#
confirm () {

    read -r -p "${1:-Continue? [y/N]} " response
    case $response in
        [yY][eE][sS]|[yY]) true
        ;;
        *) false
        ;;
    esac
}

# Print Usage
#
usage() {

    echo -e "\nUsage: $0 -s <size> -z <availability zone> -i <instance> [-d <drive id>] [-n <disks>] [-o <iops>] (-h for help)"

}

# Check for AWS Environment Vars as we can't do much without them
[[ $AWS_USER_ID && ${AWS_USER_ID-x} ]] || { echo  "AWS_USER_ID not defined. Please set up your AWS credentials. See http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/index.html?SettingUp_CommandLine.html for more information."; exit 1; }
[[ $AWS_ACCESS_KEY_ID && ${AWS_ACCESS_KEY_ID-x} ]] || { echo  "AWS_ACCESS_KEY_ID not defined. Please set up your AWS credentials. See http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/index.html?SettingUp_CommandLine.html for more information."; exit 1; }
[[ $AWS_SECRET_ACCESS_KEY && ${AWS_SECRET_ACCESS_KEY-x} ]] || { echo  "AWS_SECRET_ACCESS_KEY not defined. Please set up your AWS credentials. See http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/index.html?SettingUp_CommandLine.html for more information."; exit 1; }
[[ $EC2_PRIVATE_KEY && ${EC2_PRIVATE_KEY-x} ]] || { echo  "EC2_PRIVATE_KEY not defined. Please set up your AWS credentials. See http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/index.html?SettingUp_CommandLine.html for more information."; exit 1; }
[[ $EC2_CERT && ${EC2_CERT-x} ]] || { echo  "AWS_USER_ID not defined. Please set up your AWS credentials. See http://docs.amazonwebservices.com/AWSEC2/latest/UserGuide/index.html?SettingUp_CommandLine.html for more information."; exit 1; }

# Process Command Line Args

while getopts ":d:s:z:i:n:o:h" optname
do

    case ${optname} in
         h|H) usage
              echo -e "\n\tRequired Arguments:\n"
              echo -e "\t-s <size> - the usable size of the raid array (in GB)"
              echo -e "\t-z <zone> - the AWS availability zone"
              echo -e "\t-i <instance> - the EC2 instance id to attach to"
              echo -e "\n\tOptional Arguments:\n"
              echo -e "\t-d <drive> - the drive identifier to use (defaults to sdh)"
              echo -e "\t-n <number of disks> - the number of disks to create in the array (defaults to 8)"
              echo -e "\t-o <iops> - the requested number of I/O operations per second that the volume can support"
              echo -e "\n"
              exit 0
              ;;
         s|S) TOTALSIZE=${OPTARG}
              ;;
         z|Z) AWSZONE=${OPTARG}
              ;;
         i|I) EC2INSTANCE=${OPTARG}
              ;;
         n|N) DISKS=${OPTARG}
              ;;
         o|O) IOPS=${OPTARG}
              PROVIOPS=1
              ;;
         d|D) DRIVEID=${OPTARG}
              ;;
         * )  echo "No such option ${optname}."
              usage
              exit 1
              ;;
     esac
done

# Do we have values for required arguments?

[[ $TOTALSIZE && ${TOTALSIZE-x} ]] || { echo "No size given"; usage; exit 1; }
[[ $AWSZONE && ${AWSZONE-x} ]] || { echo "No AWS Zone given"; usage; exit 1; }
[[ $EC2INSTANCE && ${EC2INSTANCE-x} ]] || { echo "No EC2 Instance given"; usage; exit 1; }

# Check AWS Zone and Instance for validity

[[ "${AWSZONES}" =~ " ${AWSZONE} " ]] || { echo -e "$AWSZONE is not a valid AWS zone.\n\nValid Zones: $AWSZONES\n"; exit 1; }

AWSINSTANCECHECK=`ec2-describe-instances | grep INSTANCE | awk '{printf " %s ",$2}' | grep $EC2INSTANCE | wc -c`
[[ $AWSINSTANCECHECK -gt 3 ]] || { echo -e "Instance ID: $EC2INSTANCE not found. Check your credentials and the instance id.\n\n"; exit 1; }

echo -n "Creating a $TOTALSIZE GB array in $AWSZONE for instance $EC2INSTANCE"

[[ $PROVIOPS -eq 1 ]] && { echo -e " with $IOPS I/O operations per second"; IOPSARGS="--type io1 --iops ${IOPS}"; }

echo "."

# Do the Math
#
# 2X total capacity, each disk 2*(capacity)/(number of disks)

CAPACITY=`expr $TOTALSIZE \* 2`
EACHDISK=`expr $CAPACITY / $DISKS`

echo "This means a total of $CAPACITY GB in $DISKS disks of $EACHDISK GB each."

# Error check: IOPS volumes must be at least 10GB in size
[[ $PROVIOPS -eq 1 ]] && [[ $EACHDISK -lt 10 ]] && { echo -e "** IOPS Volumes must be at least 10GB in size. Increase the array size or reduce the number of disks (-n <disks>)\n\n"; exit 1; }

confirm && {

   echo "Creating EBS Volumes...";

   for (( disk=1; disk<=$DISKS; disk++));
   do

     echo -en "\tCreating volume $disk of $DISKS...";

     # Create Volume
     createvolume=`ec2-create-volume --size ${EACHDISK} --availability-zone ${AWSZONE} ${IOPSARGS}`
     # Did it work?
     [[ $createvolume && ${createvolume-x} ]] || { echo "Volume Creation Unsuccessful. Exiting." exit 1; }

         echo -en "Associating with instance...\n\t";

         # Associate with Instance
         volume=`echo $createvolume | awk '{print$2}'`;
         ec2-attach-volume $volume -i ${EC2INSTANCE} -d /dev/${DRIVEID}${disk} || { echo "Association of volume $volume to instance ${EC2INSTANCE} failed! Exiting..."; exit 1; };

   done;

   echo -e "EC2 volumes creation is complete. You can now log into the instance and create the raid array:\n\tmdadm --create -l10 -n$DISKS /dev/md0 /dev/xvdh*\n";

}


