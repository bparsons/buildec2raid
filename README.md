# Build RAID 10 array in Amazon EC2

Creates EBS volumes in Amazon EC2 and associates them with an EC2 instance for use as a RAID array

##  Requirements

### ec2-api-tools - http://aws.amazon.com/developertools/351

ec2-api-tools must be working and your environment variables set up:

* AWS_ACCESS_KEY
* AWS_SECRET_KEY

##  Usage

     $ buildec2raid.sh -s <size> -z <zone> -i <instance> [-d drive letter] [-n number of disks] [-o iops] -v 

* size - the usable size of the raid array (in GB)
* zone - the availability zone
* instance - the ec2 instance id to attach to
* drive letter (optional) - the drive letter to use in association with the instance (defaults to h)
* number of disks (optional) - the number of disks to create for the array (defaults to 8, minimum 4)
* iops (optional) - the requested number of I/O operations per second that the volume can support
* -v to specify HVM instances (HVM uses a different drive assignment scheme)

##  Example

     $ ./buildec2raid.sh -s 1024 -z us-east-1a -i i-9i8u7y7y

This would create a 1TB array in us-east-1a attached to i-918u7y7y

      $ ./buildec2raid.sh -s 1024 -z us-east-1a -i i-9i8u7y7y -n 6 -o 100 -d j

This would create a 1TB array in us-east-1a attached to i-9i8u7y7y using 6 drives provisioned with 100 IOPS per second and using j as the drive letter
(/dev/sdj and /dev/xvdj)

## More information

After completing the creation of the EBS volumes using this script, you can log into the instance and initialize the raid array. For example:

     $ mdadm --create -l10 -n8 /dev/md0 /dev/xvdh*

This creates a RAID 10 volume from the 8 disks. For more information on software raid, see https://raid.wiki.kernel.org/index.php/Linux_Raid

## License

This script is distributed under the MIT License (see LICENSE)

## Migrating a RAID array to another instance

Typically if you want to migrate data between hosts within the same availability zone, you would create a new array on the destination instance and copy or rsync the data over. 

However the <strong>moveec2raid.sh</strong> script in this repository will migrate a RAID array to another instance. 

The syntax is:

     $  ./moveec2raid.sh -f <from instance> -t <to instance> -d <drive letter>

All three fields are required. The drive letter is the drive identifier of the origin instance. ie. /dev/xvdh*.

<em>The script assumes that all volumes mounted with that drive letter are part of your RAID array and they will be migrated in place.</em> If you used the <strong>buildec2raid.sh</strong> script, that is how the array is set up. 

Make note of your <em>/etc/mdadm.conf</em> file as it contains the identification information for your array. 


[![Analytics](https://ga-beacon.appspot.com/UA-24846718-5/buildec2raid/README.md)](https://github.com/igrigorik/ga-beacon)
