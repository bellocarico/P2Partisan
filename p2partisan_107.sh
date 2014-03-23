#!/bin/sh
#
# p2partisan v1.7 (24/03/2014)
#
# <CONFIGURATION> ###########################################
# Adjust location where the files are kept
cd /cifs1/p2partisan
#
# Edit the file "blacklists" to customise if needed
# Edit the "whitelist" to overwrite the blacklist if needed
#
#
# Enable logging? Use only for troubleshooting. 0=off 1=on
syslogs=0
#Maximum number of logs to be recorded in a given 60 sec
maxloghour=120
# to troubleshoot blocked connection close all the secondary
# traffic e.g. p2p and try a connection to the blocked
# site/port you should find a reference in the logs.
#
# ports to be whitelisted. Whitelisted ports will never be 
# blocked no matter what the source/destination IP is.
# This is very important if you're running a service like 
# e.g. SMTP/HTTP/IMAP/else. Separate value in the list below 
# with commas - NOTE: Leave 80 and 443 untouched, add custom ports only
# you might want to add remote admin and VPN ports here if any
whiteports="80,443,993,25,21"
#
# Fastrouting will process the IP classes very quickly but use
# Lot of resources. If you disable the effect is transparent
# but the full process will take minutes rather than seconds
# 0=disabled 1=enabled
fastroutine=1
#
# </CONFIGURATION> ###########################################

    [ -f iptables-add ] && rm iptables-add
    [ -f iptables-del ] && rm iptables-del
    [ -f ipset-del ] && rm ipset-del
     
echo "### PREPARATION ###"
echo "loading modules"
# Loading ipset modules
lsmod | grep "ipt_set" > /dev/null 2>&1 || \
for module in ip_set ip_set_iptreemap ipt_set
        do
        insmod $module
        done

counter=0
pos=1

echo "loading ports $whiteports exemption"

# set iptables to log blacklisted related drops
logging=`iptables -L | grep "Chain P2PARTISAN" | wc -l`
if [ $logging = 0 ]; then
iptables -N P2PARTISAN 
fi
echo "iptables -F P2PARTISAN" >> iptables-add

# set iptables to log blacklisted related drops
logging=`iptables -L | grep "Chain P2PARTISAN-DROP" | wc -l`
if [ $logging = 0 ]; then
iptables -N P2PARTISAN-DROP
fi
echo "iptables -F P2PARTISAN-DROP" >> iptables-add
echo "iptables -D INPUT -m state --state NEW -j P2PARTISAN" >> iptables-del


echo "iptables -A P2PARTISAN -p tcp --match multiport --sports $whiteports -j ACCEPT" >> iptables-add
echo "iptables -A P2PARTISAN -p udp --match multiport --sports $whiteports -j ACCEPT" >> iptables-add
echo "iptables -A P2PARTISAN -p tcp --match multiport --dports $whiteports -j ACCEPT" >> iptables-add
echo "iptables -A P2PARTISAN -p udp --match multiport --dports $whiteports -j ACCEPT" >> iptables-add

echo "### WHITELIST ###"
echo "loading the whitelist"
#Load the whitelist
if [ "$(ipset --swap whitelist whitelist 2>&1 | grep 'Unknown set')" != "" ]
    then
    ipset --create whitelist iptreemap
    cat whitelist |
    (
    while read IP
    do
            echo "$IP" | grep "^#" >/dev/null 2>&1 && continue
            echo "$IP" | grep "^$" >/dev/null 2>&1 && continue
                    ipset -A whitelist $IP
            done
    )
fi
echo "ipset -X whitelist" >> ipset-del

    echo "Preparing the whitelist for the iptables"
    echo "iptables -A P2PARTISAN -m set --set whitelist src,dst -j ACCEPT" >> iptables-add

if [ $syslogs = 1 ]; then         
	echo "iptables -A P2PARTISAN-DROP -m limit --limit $maxloghour/hour -j LOG --log-prefix "Blacklist-Dropped: " --log-level 1" >> iptables-add
fi
echo "iptables -A P2PARTISAN-DROP -j DROP"  >> iptables-add


echo "### BLACKLISTs ###"
cat blacklists |
   (
    while read line
    do
            echo "$line" | grep "^#" >/dev/null 2>&1 && continue
            echo "$line" | grep "^$" >/dev/null 2>&1 && continue
            counter=`expr $counter + 1`
            name=`echo $line |cut -d ' ' -f1`
            url=`echo $line |cut -d ' ' -f2`
            echo "loading blacklist #$counter --> ***$name***"
     
    if [[ $fastroutine -eq 1 ]]; then
     
    if [ "$(ipset --swap $name $name 2>&1 | grep 'Unknown set')" != "" ]
      then
      [ -e $name.gz ] || wget -q -O $name.gz "$url"
      { echo "-N $name iptreemap"
        gunzip -c  $name.gz | \
        sed -e "/^[\t ]*#.*\|^[\t ]*$/d;s/^.*:/-A $name /"
        echo COMMIT
      } | ipset -R
    fi
     
    else
     
		if [ "$(ipset --swap $name $name 2>&1 | grep 'Unknown set')" != "" ]
            then
            ipset --create $name iptreemap
            [ -e $name.lst ] || wget -q -O - "$url" | gunzip | cut -d: -f2 | grep -E "^[-0-9.]+$" > $name.lst
            for IP in $(cat $name.lst)
                    do
                    ipset -A $name $IP
                    done
			fi
			 
	fi

		echo "ipset -X $name " >> ipset-del
		echo "Preparing blacklist ***$name*** into the P2PARTISAN iptables"	
		echo "iptables -A P2PARTISAN -m set --set $name src,dst -j P2PARTISAN-DROP" >> iptables-add
	done
    )

echo "iptables -F P2PARTISAN-DROP " >> iptables-del
echo "iptables -F P2PARTISAN " >> iptables-del
echo "iptables -X P2PARTISAN-DROP " >> iptables-del
echo "iptables -X P2PARTISAN " >> iptables-del

input=`iptables -L INPUT | grep "P2PARTISAN" | wc -l`
if [ $input = 0 ]; then
echo "iptables -I INPUT $pos -m state --state NEW -j P2PARTISAN" >> iptables-add 
fi

chmod 777 ./iptables-*
chmod 777 ./ipset-*
echo "### NOTEs ###"
echo "Tomato is now running the script: iptables-add"
echo "If you wish to remove p2partisan from your system"
echo "run the command ./iptables-del ; ./ipset-del"
./iptables-add  #protecting the LAN
echo "### DONE ###"