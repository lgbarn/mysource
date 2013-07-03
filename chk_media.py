#!/usr/local/bin/python

###################################################################
#
# Author: Luther Barnum
#
# Date: Decmber 20, 2004
#
# Description: This program is used to parse the bptm logs to get
# a better picture of what tapes are failing and when. If you have
# any questions or suggestions, please let me know.
#
###################################################################

# Import needed modules

import string
import glob
import re
import sys
from optparse import OptionParser
from operator import itemgetter


# Define regular expressions and compile

nolock_match = 'unable to lock media\s+\w+\s+\w+\s+\d+\s+\((\w+)\)'
mount_match = '(\d+:\d+:\d+)\..*media\s+id\s+(\w+).*drivepath\s+(/dev/rmt/\w+)\,'
unmount_match = '(\d+:\d+:\d+)\..*unmount.*/(\w+)$'

nolock_match_compile = re.compile(nolock_match)
mount_match_compile = re.compile(mount_match)
unmount_match_compile = re.compile(unmount_match)

# Define variables

nolocks = {}
mountstat = 0
mediaerrors_text = []
nolockerrors_text = []

# Define functions

def main():
  mountstat = 0
  usage = "usage: chk_media.py [options]"
  parser = OptionParser(usage)
  parser.add_option("-d", "--drive", dest="drive",
                    help="track DRIVE activity")
  parser.add_option("-l", "--logfile", dest="logfile",
                    help="use LOGFILE to get data")
  parser.add_option("-m", "--mediaerrors", action="store_true", dest="merrors",
                    help="get media errors from log data")
  parser.add_option("-n", "--nolock", action="store_true", dest="nolock",
                    help="get \"unable to lock\" errors from log data")
  parser.add_option("-t", "--tape", dest="tape",
                    help="get all log entries for TAPE")

  (options, args) = parser.parse_args()
  
  if len(sys.argv) < 2:
    parser.print_help()
    sys.exit(0)
  
  if options.drive:
    parser.print_help()
    print "ERR:option \"--drive\" is not implemented yet"
    sys.exit(0)
  
  if options.tape:
    tape_match = options.tape
    tape_match_compile = re.compile(tape_match)

  if options.merrors:
    mediaerror_match = '\d+:\d+:\d+\.\d+\s+\[(\d+)\]\s+.*log_media_error.*-\s+(\d+\/\d+\/\d+)\s+(\d+:\d+:\d+)\s+(\w+)\s'
    mediaerror_match_compile = re.compile(mediaerror_match)

  if options.logfile:
    files = []
    files.append(options.logfile)
  else:
    files = glob.glob('/usr/openv/netbackup/logs/bptm/log.*')
    files.sort()
  for logfile in files:
    print "Processing log: " + logfile
    fh = open(logfile)
    for line in fh:
      cleanline = string.strip(line)
      if options.drive:
        drivemount = re.search(mount_match_compile, line)
        if drivemount:
#          print drivemount.group(1), drivemount.group(2), drivemount.group(3)
          drive = drivemount.group(3)
          if ((options.drive == drive) & (mountstat == 0)):
            mount_time = drivemount.group(1)
            mounted_tape = drivemount.group(2)
            print ("%-10s%10s%20s%35s") % (mount_time, mounted_tape, "mounted on", drive)
            mountstat = 1
        driveunmount = re.search(unmount_match_compile, line)
        if driveunmount:
#          print driveunmount.group(1), driveunmount.group(2)
          unmount_time = driveunmount.group(1)
          unmounted_tape = driveunmount.group(2)
          if ((mounted_tape == unmounted_tape) & (mountstat == 1)):
            mountstat = 0
            print ("%-10s%10s%20s%35s") % (unmount_time, unmounted_tape, "unmounted from", options.drive)
      if options.tape:
        tapelog = re.search(tape_match_compile, line)
        if tapelog:
          print cleanline
      if options.merrors:
        mediaerror = re.search(mediaerror_match_compile, line)
        if mediaerror:
          backup_id = mediaerror.group(1)
          backup_date = mediaerror.group(2)
          backup_time = mediaerror.group(3)
          tape_id = mediaerror.group(4)
          mediaerrors_text.append(("%-15s%-15s%-15s%-15s") % (backup_date, backup_time, backup_id, tape_id))
      if options.nolock:
        nolock = re.search(nolock_match_compile, line)
        if nolock:
          tape_id = nolock.group(1)
          errornumber = nolocks.get(tape_id, 0) + 1
          newnumber = int(errornumber)
          nolocks[tape_id] = newnumber 

  if options.nolock:
    items = sorted(nolocks.items(), reverse=True, key=itemgetter(1))
    print
    print("%30s") % ("Top 10")
    print("%38s") % ("\"unable to lock\" Errors")
    print("%-15s%-15s") % ("Tape ID", "# of errors")
    print("-----------------------------------------------------")
    x = 0
    for i in items:
      x = x + 1
      nolockerrors_text.append(("%-15s%-15s") % (i[0], i[1]))
      if x == 10:
        break
    for i in nolockerrors_text:
      print i
    print
      

  if options.merrors:
    print
    print("%30s") % ("Media Errors")
    print("%-15s%-15s%-15s%-15s") % ("Date", "Time", "Backup ID", "Tape ID")
    print("-----------------------------------------------------")
    sorted_mediaerrors_text = mediaerrors_text.sort()
    for i in mediaerrors_text:
      print i
    print

# Call Main Function

if __name__ == "__main__":
    main()

