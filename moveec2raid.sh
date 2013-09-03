#!/bin/bash

##
## Move EC2 RAID array from a given instance to a given instance
##
## Brian Parsons <brian@pmex.com>
##
##

##
## The MIT License (MIT)
## Copyright (c) 2012-2013 Brian Parsons
##
## Permission is hereby granted, free of charge, to any person obtaining a
## copy of this software and associated documentation files (the "Software"),
## to deal in the Software without restriction, including without limitation
## the rights to use, copy, modify, merge, publish, distribute, sublicense,
## and/or sell copies of the Software, and to permit persons to whom the
## Software is furnished to do so, subject to the following conditions:
##  
## The above copyright notice and this permission notice shall be included
## in all copies or substantial portions of the Software.
##
## THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
## IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
## FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
## AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
## LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
## FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
## DEALINGS IN THE SOFTWARE.
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

    echo -e "\n*** This script will migrate a RAID array from one instance to another instance in the same availability zone. A safer way to do this is to build a new array on the destination instance and rsync everything over.\n"
    echo -e "\nUsage: $0 -f <from instance> -t <to instance> -d <drive letter> (-h for help)"

}

# Process Command Line Args
while getopts ":f:t:d:h" optname
do
    case ${optname} in
        h|H) usage
             echo -e "\n\tRequired Arguments:\n"
             echo -e "\t-f <from instance> - the instance id the array is currently attached to"
             echo -e "\t-t <to instance> - the instance id to copy the array to"
             echo -e "\t-d <drive> - the drive identifier (last letter), ie 'h' for /dev/xvdh*"
             echo -e "\n"
             exit 0
             ;;
        f|F) FROMINSTANCE=${OPTARG}
             ;;
        t|T) TOINSTANCE=${OPTARG}
             ;;
        d|D) DRIVEID=${OPTARG}
             ;;
          *) echo "No such option ${optname}."
             usage
             exit 1
             ;;
    esac 
done

# Do we have values for required arguments?
[[ $FROMINSTANCE && ${FROMINSTANCE-x} ]] || { echo "No From instance given"; usage; exit 1; }
[[ $TOINSTANCE && ${TOINSTANCE-x} ]] || { echo "No To instance given"; usage; exit 1; }
[[ $DRIVEID && ${DRIVEID-x} ]] || { echo "No Drive Letter given"; usage; exit 1; }

# Do we have a valid DRIVEID
driveidletters=`echo -n $DRIVEID | wc -c`
[[ $driveidletters -gt 1 ]] && { echo -e "Only specify one drive letter d-z."; exit 1; }
driveidcheck=`echo $DRIVEID | grep [d-z] | wc -c`
[[ $driveidcheck -gt 0 ]] || { echo -e "Drive Letter ${DRIVEID} is invalid. Please specify d-z."; exit 1; }


# Check to make sure instances are in the same availability zone
echo -n "Checking Availability Zone..."
FROMAZ=`ec2-describe-instances -v $FROMINSTANCE | grep "<availabilityZone>" | awk -F'<availabilityZone>' '{print$2}' | awk -F'<' '{print$1}'`
echo -n "$FROMINSTANCE is in $FROMAZ..."
TOAZ=`ec2-describe-instances -v $TOINSTANCE | grep "<availabilityZone>" | awk -F'<availabilityZone>' '{print$2}' | awk -F'<' '{print$1}'`
echo "$TOINSTANCE is in $TOAZ."
[[ $FROMAZ != $TOAZ ]] && { echo "Instances $FROMINSTANCE and $TOINSTANCE are not in the same availability zone."; exit 1; }

# Get Array Info
echo -n "Getting array info..."
SAVEIFS=$IFS
IFS=$'\n'
DRIVEARRAY=(`ec2-describe-volumes | grep $FROMINSTANCE | grep "/dev/sd${DRIVEID}"`)
IFS=$SAVEIFS
ARRAYSIZE=${#DRIVEARRAY[@]}  
# Check to make sure given drive letter exists on given from instance
[[ $ARRAYSIZE -gt 2 ]] || { echo -e "No array found as ${DRIVEID} on ${FROMINSTANCE}"; exit 1; }

echo -e "Moving an array of $ARRAYSIZE disks from $FROMINSTANCE to $TOINSTANCE in $FROMAZ.\n"

echo "Found $ARRAYSIZE volumes:"
for volume in "${DRIVEARRAY[@]}"
do
    VOL=`echo $volume | awk '{print$2}'`
    DEV=`echo $volume | awk '{print$4}'`
    echo "$VOL as $DEV"
    echo "$VOL:$DEV" >> /tmp/ec2raid-safetyfile.dat
done

echo ""

confirm && {

    echo "Moving EBS volumes...";
    for volume in "${DRIVEARRAY[@]}";
    do    
        VOL=`echo $volume | awk '{print$2}'`;
        DEV=`echo $volume | awk '{print$4}'`;
        echo -en "\nDetaching $VOL from ${FROMINSTANCE}...";
        ec2-detach-volume ${VOL};
        sleep 8;
        echo -en "\nAttaching ${VOL} to ${TOINSTANCE} as ${DEV}...";
        ec2-attach-volume ${VOL} -i ${TOINSTANCE} -d ${DEV};
    done;

    echo "Done. There is a backup file of the mapping in /tmp/ec2raid-safetyfile.dat.";

}
