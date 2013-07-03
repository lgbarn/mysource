#!/usr/bin/python

#############################################################
#
# Date: May 23, 2013
#
# Author: Luther Barnum
#
# Description: This script is used to perform a full snapshot of existing 
#   Lun by parsing configuration files. This script should normally be 
#   called by cron with options specifying source and destination.
#   This script is a reqrite of the previous Perl script.
# 
#############################################################

import sys
import os
import string
import re
import subprocess
from optparse import OptionParser

class Multipath:
    """
    This class is for operations related to /etc/multipath.conf file
    and multipathd command
    """
    def __init__(self):
        self.alias2wwid = dict()
        self.wwid2alias = dict()
        self.wwidregex = r'.*wwid\s+(\w+)'
        self.wwidregex_compile = re.compile(self.wwidregex)
        self.aliasregex = r'.*alias\s+(\w+)'
        self.aliasregex_compile = re.compile(self.aliasregex)
        self.mpsecregex = r'^multipaths\s+{'
        self.mpsecregex_compile = re.compile(self.mpsecregex)
        self.mpregex = r'\s+multipath\s+{'
        self.mpregex_compile = re.compile(self.mpregex)
        self.secclose = r'\s*}'
        self.seccloseregex_compile = re.compile(self.secclose)
        with open ("/etc/multipath.conf", "r") as self.myfile:
            self.data=self.myfile.readlines()
        self.level = 0
        for self.line in self.data:
            self.line = re.sub(r'#.*', r'', self.line)
            self.match_wwidregex = self.wwidregex_compile.match(self.line)
            self.match_aliasregex = self.aliasregex_compile.match(self.line)
            self.match_mpsecregex = self.mpsecregex_compile.match(self.line)
            self.match_mpregex = self.mpregex_compile.match(self.line)
            self.match_secclose = self.seccloseregex_compile.match(self.line)
            if self.match_wwidregex:
                self.wwid = self.match_wwidregex.group(1)
            if self.match_aliasregex:
                self.alias = self.match_aliasregex.group(1)
            if self.match_mpsecregex:
                self.level = self.level + 1
            if self.match_mpregex:
                self.level = self.level + 1
            if self.match_secclose and self.level > 0:
                self.level = self.level - 1
                if self.level == 1:
                     self.alias2wwid[self.alias] = self.wwid
                     self.wwid2alias[self.wwid] = self.alias

    def getalias(self, wwid):
        """ 
        This method returns alias of given wwid
        """
        return self.wwid2alias[wwid] 

    def getwwid(self, alias):
        """ 
        This method returns wwid of given alias
        """
        newwwid = re.sub(r'^35', r'5', self.alias2wwid[alias])
        return newwwid
  
    def getblkdevs(self, lun):
        """ 
        This method returns list of block devices
        """
        self.proc = subprocess.Popen('/sbin/multipath -ll ' + lun, 
                                     stdout=subprocess.PIPE, shell=True)
        self.output = self.proc.stdout.read()
        self.splitdata = self.output.split('\n')
        for line in self.splitdata:
            match_mpregex = self.mpregex_compile.match(line)
            if match_mpregex:
                blockdev = match_mpregex.group(2)
                scsidev = match_mpregex.group(1)
                self.blockdevs.append(blockdev)
                self.scsidevs.append(scsidev)
        return (self.blockdevs, self.scsidevs)

    
  

class THREEPAR:
    """
    This class is for operations related to 3par array
    """
    def __init__(self):
        self.hostname = os.uname()[1].split('.')[0]
        self.regex = r'.*(\d+)\s+(\w+)\s'+self.hostname+'.*host'
        self.regex_compile = re.compile(self.regex)
    
    def rmvlun(self, vlun):
        """
        This method removes vlun from array
        """
        proc = subprocess.Popen(['cli showvlun -t -host ' + \
                                     self.hostname + ' -v ' + vlun], 
                                     stdout=subprocess.PIPE, shell=True)
        cmds = []
        output = proc.stdout.read()
        splitdata = output.split('\n')
        for line in splitdata:
            match_regex = self.regex_compile.match(line)
            if match_regex:
                lunid = match_regex.group(1)
                vlun = match_regex.group(2)
                cmd = "cli removevlun -f %s %s %s" % (vlun, lunid, 
                                                     self.hostname)
                cmds.append(cmd)
                cmd = "cli removevv -f -snaponly -cascade %s" % vlun 
                cmds.append(cmd)
        return cmds
    

class Snapshot:
    """
    This class is for operations related to /etc/snapshots.conf file
    """
    def __init__(self, source, package):
        with open ('/etc/snapshots.conf',"r") as myfile:
            self.data = myfile.read() 
        self.vgpairs = []
        self.pkgluns = []
        self.srcluns = []
        self.rogrps = []
        self.rwgrps = []
        self.vgs = [] 
        self.regex = '^disk:(' + source + '_(vg.+)_d.+):(' + \
                      package + '_(vg.+)_d.+)'
        self.regex_compile = re.compile(self.regex)
        for line in self.data.split('\n'):
            match_regex = self.regex_compile.match(line)
            if match_regex:
                srclun = match_regex.group(1)
                pkglun = match_regex.group(3)
                pkgvolgrp = match_regex.group(4)
                srcvolgrp = match_regex.group(2)
                self.vgpairs.append(srcvolgrp + ':' + pkgvolgrp)
                self.srcluns.append(srclun)
                self.pkgluns.append(pkglun)
                self.vgs.append(pkgvolgrp)
                self.rogrps.append(srclun + ':' + pkglun + '.ro')
                self.rwgrps.append(pkglun + '.ro:' + pkglun)

    def getpkgluns(self):
        """
        This method returns all lun names of snapshot package
        """
        return self.pkgluns

    def getvgpairs(self):
        """
        This method returns pairs of volumegroups
        """
        return self.vgpairs

    def getpkgvgs(self):
        """
        This method returns all volume group names of snapshot package
        """
        return set(self.vgs)

    def getrogrps(self):
        """
        This method returns all RO vluns
        """
        return self.rogrps

    def getrwgrps(self):
        """
        This method returns all RW vluns
        """
        return self.rwgrps

def runprocess(cmd, test):
    """
    This function is used to run all commands and log them
    """
    if test != True:
        print cmd
        proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, 
                             stderr=subprocess.STDOUT, shell=True)
        (stdout, stderr) = proc.communicate()
        error_code = proc.returncode
        print 
        print "return code %s" % error_code
        print 
        print stdout
    else:
        error_code = 0
        print cmd
        print 
        print "return code %s" % error_code
        print 
        print "stdout goes here"
        print 
        print 
    return error_code

def getpkgmounts(package): 
    """
    This function gets all mounts related to snapshot package
    """
    fstabfile = '/etc/fstab'
    regex = r'/dev/vg.*/lv.*\s+(/pkg/'+package+r'/\w+)\s+'
    regex_compile = re.compile(regex)
    with open (fstabfile,"r") as myfile:
        data = myfile.read() 
    pkgmounts = []
    splitdata = data.split('\n')
    for line in splitdata:
        match_regex = regex_compile.match(line)
        if match_regex:
            mount = match_regex.group(1)
            pkgmounts.append(mount)
    return pkgmounts

def getcurrfilter():
    currpvs = []
    proc = subprocess.Popen('pvs --noheadings -o pv_name', 
                            stdout=subprocess.PIPE, shell=True)
    output = proc.stdout.read()
    pvs = output.split('\n')
    pvs = map(str.strip, pvs)
    pvs = filter(None, pvs)
    for i in pvs:
        currpvs.append("\"a|" + i + "|\"")
    pvs = ', '.join(currpvs)
    pvs = 'filter = [ ' + pvs + ', "r|.*|" ]'
    return pvs

def getfinalfilter(newpvs):
    currpvs = []
    proc = subprocess.Popen('pvs --noheadings -o pv_name', 
                            stdout=subprocess.PIPE, shell=True)
    output = proc.stdout.read()
    pvs = output.split('\n')
    pvs = map(str.strip, pvs)
    pvs = filter(None, pvs)
    for i in pvs:
        currpvs.append("\"a|" + i + "|\"")
    for i in newpvs:
        currpvs.append("\"a|" + i + "|\"")
    pvs = ', '.join(currpvs)
    pvs = 'filter = [ "a|/dev/sda$|", "a|/dev/sda1$|", "a|/dev/sda2$|", "a|/dev/sda3$|",' + pvs + ', "r|.*|" ]'
    return pvs

def restrictlvm(subst, lvmfile):
    subst = str(subst)
    newfilecontents = []
    pattern = "filter.*"
    # Read contents from file as a single string
    file_handle = open(lvmfile, 'r')
    file_string = file_handle.read()
    file_handle.close()

    # Use RE package to allow for replacement (also allowing for (multiline) REGEX)
    filedata = file_string.split("\n")
    for line in filedata:
        if re.search("#", line):
            newfilecontents.append(line)
        else:
            line = (re.sub(pattern, subst, line))
            newfilecontents.append(line)
    file_string = '\n'.join(newfilecontents)
    # Write contents to file.
    # Using mode 'w' truncates the file.
    file_handle = open(lvmfile, 'w')
    file_handle.write(file_string)
    file_handle.close()

def main():
    """ 
    This is just the main function call. Nothing special about it
    """
    # Options Section
    parser = OptionParser()
    parser.add_option("-p", "--package", dest="package",
                      help="package name to use for snapshot")
    parser.add_option("-s", "--source", dest="source",
                      help="package name to use for source")
    parser.add_option("-e", "--enable", action="store_true", dest="enable",
                      help="option used to create snapshot")
    parser.add_option("-d", "--disable", action="store_true", dest="disable",
                      help="option used to disable or remove snapshot")
    parser.add_option("-t", "--test", action="store_true", 
                     dest="test",
                     help="option used to print commands but not execute")
    (options, args) = parser.parse_args()
    if not options.enable and not options.disable:
        parser.print_help()
        sys.exit()
    if not options.package:
        parser.print_help()
        sys.exit()
    if not options.source:
        parser.print_help()
        sys.exit()
    if len(sys.argv) == 1:
        parser.print_help()
        sys.exit()
    # Initialization Section
#    mpconfregex = r'multipath {'
#    file_data = open("/etc/multipath.conf").read()
#    my_list = re.findall(mpconfregex, file_data, re.MULTILINE)
#    print my_list
    hostname = os.uname()[1].split('.')[0]
    mpath = Multipath()
    array = THREEPAR()
    hostname = os.uname()[1].split('.')[0]
    mounts = getpkgmounts(options.package)
    snap = Snapshot(options.source, options.package)
######## Start of Disable Section ##############
    if options.disable:
        for mount in mounts:
            if os.path.ismount(mount):
                cmd = "/sbin/fuser -km %s" % mount
                runprocess(cmd, options.test)
                cmd = "/bin/umount %s" % mount
                runprocess(cmd, options.test)
        vgs = snap.getpkgvgs()
        for vgrp in vgs:
            cmd = "/sbin/vgchange -a n %s" % vgrp
            runprocess(cmd, options.test)
        for vgrp in vgs:
            cmd = "/sbin/vgremove -ff %s" % vgrp
            runprocess(cmd, options.test)
        pkgluns = snap.getpkgluns()
        newpkgluns = []
        for line in pkgluns:
            line = (re.sub(r"(^)", "/dev/mapper/", line))
            newpkgluns.append(line)
        for lun in pkgluns:
            (blockdevs, scsidevs) = mpath.getblkdevs(lun)
            for blockdev in blockdevs:
                cmd = "blockdev --flushbufs /dev/%s" % blockdev
                runprocess(cmd, options.test)
            for scsidev in scsidevs:
                cmd = "echo 1 > /sys/class/scsi_device/%s/device/delete" % scsidev 
                runprocess(cmd, options.test)
            cmd = "multipath -f %s" % lun
            runprocess(cmd, options.test)
            cmds = array.rmvlun(lun)
            for cmd in cmds:
                runprocess(cmd, options.test)
######## End of Disable Section ##############
    cmd = "multipath -l"
    runprocess(cmd, options.test)
    cmd = "sleep 2"
    runprocess(cmd, options.test)
    cmd = "multipath -r"
    runprocess(cmd, options.test)
    cmd = "sleep 2"
    runprocess(cmd, options.test)
    cmd = "multipath -F"
    runprocess(cmd, options.test)
    cmd = "sleep 2"
    runprocess(cmd, options.test)
    cmd = "multipath -v2"
    runprocess(cmd, options.test)
    cmd = "sleep 2"
    runprocess(cmd, options.test)
    cmd = "multipath -l"
    runprocess(cmd, options.test)
    cmd = "sleep 2"
    runprocess(cmd, options.test)

######## Start of Enable Section ##############
    if options.enable:
        rogroup = snap.getrogrps()
        rwgroup = snap.getrwgrps()
        print "rogroup" % rogroup
        print "rwgroup" % rwgroup
        cmd = "cli creategroupsv -ro %s" % string.join(rogroup)
        runprocess(cmd, options.test)
        cmd = "cli creategroupsv %s" % string.join(rwgroup)
        runprocess(cmd, options.test)
        pkgluns = snap.getpkgluns()
        for lun in pkgluns:
            wwn = mpath.getwwid(lun)
            cmd = "cli setvv -wwn %s %s" % (wwn, lun)
            runprocess(cmd, options.test)
            cmd = "cli createvlun %s auto %s" % (lun, hostname)
            runprocess(cmd, options.test)
        cmd = "sleep 2"
        runprocess(cmd, options.test)
        cmd = "rescan-scsi-bus.sh -l"
        runprocess(cmd, options.test)
        cmd = "sleep 2"
        runprocess(cmd, options.test)
        cmd = "multipath -F"
        runprocess(cmd, options.test)
        cmd = "sleep 2"
        runprocess(cmd, options.test)
        cmd = "multipath -r"
        runprocess(cmd, options.test)
        cmd = "sleep 2"
        runprocess(cmd, options.test)
        cmd = "multipath -F"
        runprocess(cmd, options.test)
        cmd = "sleep 2"
        runprocess(cmd, options.test)
        cmd = "multipath -v2"
        runprocess(cmd, options.test)
        cmd = "sleep 2"
        runprocess(cmd, options.test)
        newlvmfilter =  getcurrfilter()
        restrictlvm(newlvmfilter, "/etc/lvm/lvm.conf")
        cmd = "mkdir /tmp/lvmtemp"
        runprocess(cmd, 0)
        cmd = "cp /etc/lvm/lvm.conf /tmp/lvmtemp/lvm.conf" 
        runprocess(cmd, 0)
        os.environ['LVM_SYSTEM_DIR'] = '/tmp/lvmtemp'
        pkgluns = snap.getpkgluns()
        newpkgluns = []
        for line in pkgluns:
            line = (re.sub(r"(^)", "/dev/mapper/", line))
            newpkgluns.append(line)
        pvs = newpkgluns
        pvs = filter(None, pvs)
        pvs = '|", "a|'.join(pvs)
        addfilter = 'filter = [ "a|' + pvs + '|", "r|.*|" ]'
        restrictlvm(addfilter, "/tmp/lvmtemp/lvm.conf")
        cmd = "pvscan -v"
        runprocess(cmd, options.test)
        cmd = "sleep 2"
        runprocess(cmd, options.test)
        pairs = set(snap.getvgpairs())
        pairs = list(pairs)
        for lun in pkgluns:
            cmd = "pvchange --uuid /dev/mapper/%s --config \'global{activation=0}\'" % lun
            runprocess(cmd, options.test)
        for line in pairs:
            (pkg, src) = line.split(':')
            cmd = "vgchange -a y %s --config \'global{activation=0}\'" % pkg
            runprocess(cmd, options.test)
            cmd = "vgrename %s %s --config \'global{activation=0}\'" % ( pkg, src)
            runprocess(cmd, options.test)
        vgs = snap.getpkgvgs()
        for vgrp in vgs:
            cmd = "vgcfgbackup %s" % vgrp
            runprocess(cmd, options.test)
        del os.environ['LVM_SYSTEM_DIR'] 
        cmd = "rm -rf /tmp/lvmtemp"
        runprocess(cmd, options.test)
        finalfilter =  getfinalfilter(newpkgluns)
        restrictlvm(finalfilter, "/etc/lvm/lvm.conf")
        cmd = "pvscan -v"
        runprocess(cmd, options.test)
        cmd = "sleep 2"
        runprocess(cmd, options.test)
        cmd = "vgscan -v"
        runprocess(cmd, options.test)
        cmd = "sleep 2"
        runprocess(cmd, options.test)
        cmd = "lvscan -v"
        runprocess(cmd, options.test)
        cmd = "sleep 2"
        runprocess(cmd, options.test)
        cmd = "vgmknodes -v"
        runprocess(cmd, options.test)
        cmd = "sleep 2"
        runprocess(cmd, options.test)
        for vgrp in vgs:
            proc = subprocess.Popen(['lvs --noheadings -o lv_name ' 
                                    + vgrp], stdout=subprocess.PIPE, shell=True)
            output = proc.stdout.read()
            lvs = output.split('\n')
            for lvol in lvs:
                lvol = lvol.strip()
                if lvol:
                    cmd = "fsck -y /dev/%s/%s" % (vgrp, lvol )
                    runprocess(cmd, options.test)
        mounts = getpkgmounts(options.package)
        for mount in mounts:
            cmd = "mount %s" % mount
            runprocess(cmd, options.test)
######## End of Enable Section ##############

        

if __name__ == "__main__":
    main()

