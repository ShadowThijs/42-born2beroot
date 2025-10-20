LINUX=`uname -s`
VERSION=`uname -r`
ARCH=`uname -vmo`
ARCHITECTURE="$LINUX $USER $VERSION $ARCH"

PHYSICAL_PROC=`lscpu | grep -o 'Socket(s).*' | cut -d" " -f32`

VIRTUAL_PROC=`nproc`

MEM_USED=`free --mega | awk '/Mem:/ {printf "%.1f", $3/1048}'`
MEM_TOTAL=`free --mega | awk '/Mem:/ {printf "%.1f", $2/1048}'`
MEM_USED_PERC=`free | awk '/Mem:/ {printf "%.1f", $3 / $2 * 100'}`

STORAGE_TOTAL=`df --total -h | tail -1 | awk '{print $2}' | grep -Eo '[0-9]{1,9}'`
STORAGE_USED=`df --total -h | tail -1 | awk '{print $3}' | grep -Eo '[0-9]{1,9}'`
STORAGE_PERC=`df --total -h | tail -1 | awk '{print $5}'`

# CPU Usage = (time spent working) / (total time) * 100
# Retrieve information from /proc/stat which holds all cpu stats
CPU_USED=`{ grep 'cpu ' /proc/stat; sleep 1; grep 'cpu ' /proc/stat; } | awk -v RS="" '{printf "%.2f%%\n", ($13-$2+$15-$4)*100/($13-$2+$15-$4+$16-$5)}'`

LREBOOT_DATE=`who -b | awk '{print $3}'`
LREBOOT_TIME=`who -b | awk '{print $4}'`
LREBOOT="$LREBOOT_DATE $LREBOOT_TIME"

if lsblk -no TYPE | grep -q '^lvm$'; then
	LVM_USE="yes"
else
	LVM_USE="no"
fi

CON_AMOUNT=`ss -t -u | grep 'ESTAB' | wc -l`

USER_LOGGED=`uptime | awk '{print $4}'`

IPV4_ADDR=`hostname -I | awk '{print $1}'`
MAC_ADDR=`ip -o link show | grep -v loopback | awk '{print $17}'`
NETWORK="IP $IPV4_ADDR (${MAC_ADDR})"

SUDO_RAN=`cat /var/log/sudo/sudo.log | grep ':' | wc -l`

echo """	#Architecture: $ARCHITECTURE
	#CPU physical: $PHYSICAL_PROC
	#vCPU: $VIRTUAL_PROC
	#Memory Usage: $MEM_USED/${MEM_TOTAL}Gb (${MEM_USED_PERC}%)
	#Disk Usage: $STORAGE_USED/${STORAGE_TOTAL}Gb ($STORAGE_PERC)
	#CPU Load: $CPU_USED
	#Last Boot: $LREBOOT
	#LVM use: $LVM_USE
	#Connections TCP: $CON_AMOUNT
	#User log: $USER_LOGGED
	#Network: $NETWORK
	#Sudo: $SUDO_RAN"""
