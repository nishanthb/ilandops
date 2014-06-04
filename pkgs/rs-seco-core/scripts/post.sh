#!/bin/sh

if [ ! -d /usr/local/rangestack/tools/conf ];then
	mkdir -p /usr/local/rangestack/tools/conf
fi

if [ ! -d /usr/local/rangestack/tools/conf/GROUPS ];then
	mkdir -p /usr/local/rangestack/tools/conf/GROUPS
fi

if [ ! -d /usr/local/rangestack/candy/whoismycluster ];then
	mkdir -p /usr/local/rangestack/candy/whoismycluster
fi

if [ ! -h /usr/local/rangestack/tools/conf/GROUPS/nodes.cf ];then
	rm -rf /usr/local/rangestack/tools/conf/GROUPS/nodes.cf
	#ln -sf /usr/local/gemclient/conf/groups.cf /usr/local/rangestack/tools/conf/GROUPS/nodes.cf
fi

if [ ! -d /usr/local/rangestack/tools/conf/HOSTS ];then
	mkdir -p /usr/local/rangestack/tools/conf/HOSTS
fi

if [ ! -h /usr/local/rangestack/tools/conf/HOSTS/nodes.cf ];then
	rm -rf /usr/local/rangestack/tools/conf/HOSTS/nodes.cf
	ln -sf /usr/local/gemclient/conf/hosts.cf /usr/local/rangestack/tools/conf/HOSTS/nodes.cf
fi


if [ ! -d  /usr/local/rangestack/candy/whoismycluster ];then
	mkdir -p /usr/local/rangestack/candy/whoismycluster
fi

