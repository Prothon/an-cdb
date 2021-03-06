#!/bin/bash
# 
# TODO: Make sure this in an EL6 release.
# TODO: Make this less stupid.
# TODO: Sign our repo and RPMs.
# TODO: Remove the 'apache' user SSH stuff once the new SSH system is better
#       tested.

# Change the following variables to suit your setup.
PASSWORD=""
HOSTNAME=$(hostname)
CUSTOMER=""
VERSION="1.0.4"

clear;
echo ""
echo "##############################################################################"
echo "# AN!CDB - Alteeve's Niche! - Cluster Dashboard                              #"
echo "#                                                          Install Beginning #"
echo "##############################################################################"
echo ""
echo "What is the host name of this dashboard?"
echo -n "[$HOSTNAME] "
read NEWHOSTNAME
if [ "$NEWHOSTNAME" != "" ]; then
	HOSTNAME=$NEWHOSTNAME
fi
echo ""
echo "NOTE: The password you enter will be echoed back to you."
echo "What password do you want for the local 'alteeve' user and for the dashboard's"
echo "'admin' user? "
echo -n "[] "
read PASSWORD
echo ""
echo "What is the company or organization to use for the Dashboard password prompt?"
echo -n "[] "
read CUSTOMER
echo ""
echo "Using the following values:"
echo " - Host name: [$HOSTNAME]"
echo " - Customer:  [$CUSTOMER]"
echo " - Password:  [$PASSWORD]"
echo ""
echo "Shall I proceed? [y/N]"
read proceed
# Lower-case the answer.
proceed=${proceed,,}
if [ "$proceed" == "y" ] || [ "$proceed" == "yes" ]; then
	echo " - Beginning now.";
else
	echo " - Please re-run this script. Exiting."
	exit;
fi

echo "Adding AN!Repo."
if [ -e "/etc/yum.repo.d/an.conf" ]
then
	echo " - Already exists"
else
	curl https://alteeve.ca/repo/el6/an.repo > /etc/yum.repos.d/an.repo
	if [ -e "/etc/yum.repo.d/an.conf" ]
	then
		echo " - Added."
	else
		echo " - Failed to write: [/etc/yum.repo.d/an.conf]."
		exit
	fi
fi
# Install the EPEL repo
rpm -ivh http://download.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm

yum clean all
yum -y update
yum -y install cpan perl-YAML-Tiny perl-Net-SSLeay perl-CGI fence-agents \
               syslinux openssl-devel httpd screen ccs vim mlocate wget man \
               qemu-kvm libvirt perl-Test-Simple policycoreutils-python \
               perl-Net-SSH-Perl 

# Stuff from our repo
yum -y install perl-Net-SSH2

               # Stuff for a GUI
yum -y groupinstall basic-desktop development x11 fonts
yum -y install virt-manager firefox gedit 

export PERL_MM_USE_DEFAULT=1
perl -MCPAN -e 'install("YAML")'
if [ ! -e "/usr/local/share/perl5/YAML.pm" ]
then
	echo "The perl module 'YAML' didn't install, trying again."
	perl -MCPAN -e 'install("YAML")'
	if [ ! -e "/usr/local/share/perl5/YAML.pm" ]
	then
		echo "The perl module 'YAML' failed to install."
		echo "Do you have an Internet connection? Unable to proceed."
		exit;
	fi
fi	
perl -MCPAN -e 'install Moose::Role'
if [ ! -e "/usr/local/lib64/perl5/Moose/Role.pm" ]
then
	echo "The perl module 'Moose::Role' didn't install, trying again."
	perl -MCPAN -e 'install Moose::Role'
	if [ ! -e "/usr/local/lib64/perl5/Moose/Role.pm" ]
	then
		echo "The perl module 'Moose::Role' failed to install.Unable to proceed."
		exit;
	fi
fi	
perl -MCPAN -e 'install Throwable::Error'
if [ ! -e "/usr/local/share/perl5/Throwable/Error.pm" ]
then
	echo "The perl module 'Throwable::Error' didn't install, trying again."
	perl -MCPAN -e 'install Throwable::Error'
	if [ ! -e "/usr/local/share/perl5/Throwable/Error.pm" ]
	then
		echo "The perl module 'Throwable::Error' failed to install.Unable to proceed."
		exit;
	fi
fi	
perl -MCPAN -e 'install Email::Sender::Transport::SMTP::TLS'
if [ ! -e "/usr/local/share/perl5/Email/Sender/Transport/SMTP/TLS.pm" ]
then
	echo "The perl module 'Email::Sender::Transport::SMTP::TLS' didn't install, trying again."
	perl -MCPAN -e 'install Email::Sender::Transport::SMTP::TLS'
	if [ ! -e "/usr/local/share/perl5/Email/Sender/Transport/SMTP/TLS.pm" ]
	then
		echo "The perl module 'Email::Sender::Transport::SMTP::TLS' failed to install.Unable to proceed."
		exit;
	fi
fi	

cat /dev/null > /etc/libvirt/qemu/networks/default.xml

if [ ! -e "/var/www/home" ]
then
	mkdir /var/www/home
fi
chown apache:apache /var/www/home/

### TODO: Remove this and get selinux working ASAP.
if [ ! -e "/etc/selinux/config.anvil" ]
then
	sed -i.anvil 's/SELINUX=enforcing/SELINUX=disabled/' /etc/selinux/config
fi
if [ ! -e "/etc/inittab.anvil" ]
then
	sed -i.anvil 's/id:3:initdefault/id:5:initdefault/' /etc/inittab
fi
# If there is already a backup, keep it as it will be the original version.
if [ -e "/etc/sysconfig/network.anvil" ]
then
	sed -i "s/HOSTNAME=.*/HOSTNAME=$HOSTNAME/" /etc/sysconfig/network
else
	sed -i.anvil "s/HOSTNAME=.*/HOSTNAME=$HOSTNAME/" /etc/sysconfig/network
fi
if [ ! -e "/etc/passwd.anvil" ]
then
	sed -i.anvil 's/apache\(.*\)www:\/sbin\/nologin/apache\1www\/home:\/bin\/bash/g' /etc/passwd	
fi
# If there is already a backup, just edit the customer's name
if [ -e "/etc/httpd/conf/httpd.conf.anvil" ]
then
	sed -i.anvil 's/Cluster Dashboard - .*/Cluster Dashboard - $CUSTOMER/' /etc/httpd/conf/httpd.conf
else
	cp /etc/httpd/conf/httpd.conf /etc/httpd/conf/httpd.conf.anvil
	sed -i 's/Timeout 60/Timeout 60000/' /etc/httpd/conf/httpd.conf
	sed -i "/Directory \"\/var\/www\/cgi-bin\"/ a\    # Password login\n    AuthType Basic\n    AuthName \"AN!Cluster Dashboard - $CUSTOMER\"\n    AuthUserFile /var/www/home/htpasswd\n    Require user admin" /etc/httpd/conf/httpd.conf
fi

if [ ! -e "/etc/ssh/sshd_config.anvil" ]
then
	# This prevents long delays logging in when the net is down.
	sed -i.anvil 's/#GSSAPIAuthentication no/GSSAPIAuthentication no/'   /etc/ssh/sshd_config
	sed -i       's/GSSAPIAuthentication yes/#GSSAPIAuthentication yes/' /etc/ssh/sshd_config
	sed -i       's/#UseDNS yes/UseDNS no/'                              /etc/ssh/sshd_config
	/etc/init.d/sshd restart
fi


hostname $HOSTNAME

### TODO: Enable iptables support ASAP
chkconfig iptables off
chkconfig ip6tables off
chkconfig firstboot off
chkconfig iptables on
chkconfig httpd on

setenforce 0
#/etc/init.d/iptables stop
/etc/init.d/ip6tables stop
/etc/init.d/httpd start

### TODO: This fails if the user was created by kickstart, so break out the 
###       individual components.
# I always reset the password in case the user re-ran this script
if [ ! -e "/home/alteeve" ]
then
	useradd alteeve
	su alteeve -c "mkdir /home/alteeve/Desktop"

	#cd /root/
	#wget -c https://alteeve.ca/files/alteeve.an-cdb.home.tar.bz2
	#tar -xvjf /root/alteeve.an-cdb.home.tar.bz2
	#rsync -av --delete /root/alteeve /home/
	#chown -R alteeve:alteeve /root/alteeve
	su alteeve -c "cp /usr/share/applications/mozilla-firefox.desktop /home/alteeve/Desktop/"
	su alteeve -c "cp /usr/share/applications/virt-manager.desktop /home/alteeve/Desktop/"
	su alteeve -c "ssh-keygen -t rsa -N \"\" -b 4095 -f ~/.ssh/id_rsa"
	chmod +x /home/alteeve/Desktop/mozilla-firefox.desktop
	chmod +x /home/alteeve/Desktop/virt-manager.desktop
	
	# This disables virt-manager's autoconnect to localhost.
	VMFILE="/home/alteeve/.gconf/apps/virt-manager/connections/%gconf.xml"
	mkdir -p /home/alteeve/.gconf/apps/virt-manager/connections
	touch $VMFILE
	echo '<?xml version="1.0"?>' > $VMFILE
	echo '<gconf>' >> $VMFILE
	echo '	<entry name="autoconnect" mtime="1375139570" type="list" ltype="string">' >> $VMFILE
	echo '	</entry>' >> $VMFILE
	echo '	<entry name="uris" mtime="1375139415" type="list" ltype="string">' >> $VMFILE
	echo '		<li type="string">' >> $VMFILE
	echo '			<stringvalue>qemu:///system</stringvalue>' >> $VMFILE
	echo '		</li>' >> $VMFILE
	echo '	</entry>' >> $VMFILE
	echo '</gconf>' >> $VMFILE
	chown -R alteeve:alteeve /home/alteeve/.gconf
	chmod go-rwx -R /home/alteeve/.gconf
fi
echo $PASSWORD | passwd --stdin alteeve

if [ ! -e "/root/.ssh/id_rsa" ]
then
	ssh-keygen -t rsa -N "" -b 4095 -f ~/.ssh/id_rsa
fi
if [ ! -e "/var/www/home/.ssh/id_rsa" ]
then
	su apache -c "ssh-keygen -t rsa -N \"\" -b 4095 -f ~/.ssh/id_rsa"
fi

if [ ! -e "/var/www/home/media" ]
then
	mkdir /var/www/home/media
fi
if [ ! -e "/var/www/home/status" ]
then
	mkdir /var/www/home/status
fi
if [ ! -e "/etc/an" ]
then
	mkdir /etc/an
fi
if [ ! -e "/var/log/an-cdb.log" ]
then
	touch /var/log/an-cdb.log
fi
if [ ! -e "/var/log/an-mc.log" ]
then
	touch /var/log/an-mc.log
fi

# Remove the old file and recreate it in case the use changed the password.
if [ -e /var/www/home/htpasswd ]
then
	rm -f /var/www/home/htpasswd
fi
su apache -c "htpasswd -cdb /var/www/home/htpasswd admin '$PASSWORD'"
if [ ! -e "/var/www/tools" ]
then
	cd /tmp/
	wget -c https://github.com/digimer/an-cdb/archive/v${VERSION}.tar.gz
	tar -xvzf v${VERSION}.tar.gz
	rsync -av ./an-cdb-${VERSION}/html /var/www/
	rsync -av ./an-cdb-${VERSION}/cgi-bin /var/www/
	rsync -av ./an-cdb-${VERSION}/tools /var/www/
	rsync -av ./an-cdb-${VERSION}/an.conf /etc/an/
	rsync -av ./an-cdb-${VERSION}/guacamole-install.sh /var/www/tools/
fi

# Install Guacamole
if [ -e "/etc/guacamole/noauth-config.xml" ]
then
	echo "Guacamole already installed."
else
	echo "Calling Guacamole installed."
	/var/www/tools/guacamole-install.sh
fi

chown -R apache:apache /var/www/*
chown apache:apache /var/log/an-cdb.log
chown apache:apache /var/log/an-*
chown root:apache -R /etc
chown root:apache -R /etc/an
chown root:apache -R /etc/ssh/ssh_config
chown root:apache -R /etc/hosts
chown root:root /var/www/tools/restart_tomcat6
chown root:root /var/www/tools/check_dvd
chown root:root /var/www/tools/do_dd
chmod 6755 /var/www/tools/check_dvd
chmod 6755 /var/www/tools/do_dd
chmod 6755 /var/www/tools/restart_tomcat6
chmod 770 /etc/an
chmod 660 /etc/an/*
chmod 664 /etc/ssh/ssh_config
chmod 664 /etc/hosts

# I always run this because a missing key bit have been added.
echo "# Keys for the $HOSTNAME dashboard" > /home/alteeve/Desktop/public_keys.txt
cat /root/.ssh/id_rsa.pub /home/alteeve/.ssh/id_rsa.pub /var/www/home/.ssh/id_rsa.pub >> /home/alteeve/Desktop/public_keys.txt
echo "" >> /home/alteeve/Desktop/public_keys.txt
chown alteeve:alteeve /home/alteeve/Desktop/public_keys.txt

echo ""
echo "##############################################################################"
echo "#                                                                            #"
echo "#                       Dashboard install is complete.                       #"
echo "#                                                                            #"
echo "# When you reboot and log in, you should see a file called:                  #"
echo "# [public_keys.txt] on the desktop. Copy the contents of that file and add   #"
echo "# them to: [/root/.ssh/authorized_keys] on each cluster node you wish this   #"
echo "# dashboard to access.                                                       #"
echo "#                                                                            #"
echo "# Once the keys are added, switch to the: [apache] user and use ssh to       #"
echo "# connect to each node for the first time. This is needed to add the node's  #"
echo "# SSH fingerprint to the apache user's: [~/.ssh/known_hosts] file. You only  #"
echo "# need to do this once per node.                                             #"
echo "#                                                                            #"
echo "# Please reboot to ensure the latest kernel is being used.                   #"
echo "#                                                                            #"
echo "# Remember to update: [/etc/an/an.conf] and then copy it to each node!       #"
echo "#                                                                            #"
echo "##############################################################################"
echo ""

