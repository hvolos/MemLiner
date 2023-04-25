#! /bin/bash

###
# Macro define
OS_DISTRO=$( awk -F= '/^NAME/{print $2}' /etc/os-release | sed -e 's/^"//' -e 's/"$//' )
echo "$OS_DISTRO"

# The swap file/partition size should be equal to the whole size of remote memory
SWAP_PARTITION_SIZE="1G"

# Cause of sudo, NOT use ${HOME}

if [ -z "$HOME" ]
then
    home_dir="/home/haoran"
else
    home_dir="$HOME"
fi

swap_file="${home_dir}/swapfile"

##
# Do the action

action=$1
if [ -z "${action}" ]
then
	echo "This shellscipt for Infiniswap pre-configuration."
	echo "Run it with sudo or root"
	echo ""
	echo "Pleaes slect what to do: [install | uninstall]"

	read action
fi

if [ -z "${home_dir}"  ]
then
	echo " Warning : home_dir is null."
fi

function convert_size_to_bytes () {
	local size=$1
	size=$(echo ${size} | sed s/G/*1024*1024*1024/)
	size=$(echo ${size} | sed s/M/*1024*1024/)
	size=$(echo ${size} | sed s/K/*1024/)
	echo ${size} | bc
}

function fallocate_using_dd () {
	local size_bytes=$(convert_size_to_bytes $1)
	local size_kilobytes=$(echo "${size_bytes}/1024" | bc)
	local swapfile=$2

	sudo dd if=/dev/zero of=${swapfile} bs=1024 count=${size_kilobytes}
}

## self defined function
function close_swap_partition () {
	if [[ ${OS_DISTRO} == "CentOS Linux" ]]
	# For CentOS, usually a block device is used as swap space
	then
		swap_bd=$(swapon -s | grep "dev" | cut -d " " -f 1 )
	elif [[ ${OS_DISTRO} == "Ubuntu" ]]
	then
	# For ubuntu, usually a file is used as swap space
		swap_bd=$(swapon -s | grep "swap.img" | cut -d " " -f 1 )

		# the name can also be swapfile
		if [ -z "${swap_bd}" ]
		then
			swap_bd=$(swapon -s | grep "swapfile" | cut -d " " -f 1 )
		fi
	fi

	if [[ -z "${swap_bd}" ]]
	then
		echo "Nothing to close."
	else
		echo "Swap Partition to close :${swap_bd} "
		sudo swapoff "${swap_bd}"
	fi

	#check
	echo "Current swap partition:"
	swapon -s
}


function create_swap_file () {
	if [ -e ${swap_file} ]
	then
		echo "Please confirm the size of swapfile match the expected ${SWAP_PARTITION_SIZE}"
		local cur_size=$(du -sh ${swap_file} | awk '{print $1;}' )
		local cur_size_bytes=$(du -sb ${swap_file} | awk '{print $1;}' )
		local swap_partition_size_bytes=$(convert_size_to_bytes ${SWAP_PARTITION_SIZE})
		if [ "${cur_size_bytes}" != "${swap_partition_size_bytes}" ]
		then
			echo "Current ${swap_file} : ${cur_size} NOT equal to expected ${SWAP_PARTITION_SIZE}"
			echo "Delete it"
			sudo rm ${swap_file}

			echo "Create a file, ~/swapfile, with size ${SWAP_PARTITION_SIZE} as swap device."
			fallocate_using_dd ${SWAP_PARTITION_SIZE} ${swap_file}
			sudo chmod 600 ${swap_file}
		fi
	else
		# not exit, create a swapfile
		echo "Create a file, ~/swapfile, with size ${SWAP_PARTITION_SIZE} as swap device."
		fallocate_using_dd ${SWAP_PARTITION_SIZE} ${swap_file}
		sudo chmod 600 ${swap_file}
		du -sh ${swap_file}
	fi

	sleep 1
	echo "Mount the ${swap_file} as swap device"
	sudo mkswap ${swap_file}
	sudo swapon ${swap_file}

	# check
	swapon -s
}


if [ "${action}" = "install" ]
then
	echo "Close current swap partition && Create swap file"
	close_swap_partition

	create_swap_file

	echo "insmod ./rswap-client.ko"
	sudo insmod ./rswap-client.ko

elif [ "${action}" = "uninstall" ]
then
	echo "Close current swap partition"
	close_swap_partition

	echo "rmmod rswap-client"
	sudo rmmod rswap-client

else
	echo "!! Wrong choice : ${action}"
fi
