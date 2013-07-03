#!/usr/bin/env python

#######################################################################
#
# Author: Luther Barnum
#
# Date: Feb 4, 2007
#
# Description: This script is used to parse cron log. I can get the failed crons
#             for any user
#
##########################################################################

import sys
import os
import string
import re
from optparse import OptionParser

class CronLog:
  def __init__(self):
    self.file = '/var/adm/cron/log'
    self.CMDArray = {}
    self.CMDMiscArray = {}
    self.pid = '(\d+)' # Pid
    self.user = '(\w+)' # User

  def setRegex(self):
    self.CMDRegex = '\>\s+CMD:\s+(\/.*)' # Executed command
    self.CMDBaseRegex = self.user + '\s+' # User
    self.CMDBaseRegex += self.pid + '\s+' # Pid
    self.CMDBaseRegex += 'c\s+\w+\s+' # Day of week
    self.CMDBaseRegex += '\w+\s+' # Month of year
    self.CMDBaseRegex += '\d+\s+' # Day of month
    self.CMDBaseRegex += '\d+:\d+:\d+\s+' # Time of day
    self.CMDBaseRegex += '\w+\s+' # TimeZone
    self.CMDBaseRegex += '\w+' # Year
    self.CMDMiscRegex = '\>\s+' + self.CMDBaseRegex # Begining of CMD Misc line
    self.CMDStatusRegex = '\<\s+' + self.CMDBaseRegex # Begining of CMD Status line
    self.CMDFailureRegex = self.CMDStatusRegex + '\s+rc=' # Return Code of failure
    self.CMDRegex_compile = re.compile(self.CMDRegex)
    self.CMDMiscRegex_compile = re.compile(self.CMDMiscRegex)
    self.CMDStatusRegex_compile = re.compile(self.CMDStatusRegex)
    self.CMDFailureRegex_compile = re.compile(self.CMDFailureRegex)
    
  def setFileName(self, filename):
    self.file = filename
			
  def setUserName(self, user):
    self.user = '(' + user + ')'
  
  def setPid(self, pid):
    self.pid = '(' + pid + ')'

  def printErrors(self):
    handle = open(self.file)
    print("###############################################################################")
    for line in handle:
      cleanLine = string.strip(line)
      match_CMDRegex = self.CMDRegex_compile.match(cleanLine)
      match_CMDMiscRegex = self.CMDMiscRegex_compile.match(cleanLine)
      match_CMDStatusRegex = self.CMDStatusRegex_compile.match(cleanLine)
      match_CMDFailureRegex = self.CMDFailureRegex_compile.match(cleanLine)
      if match_CMDRegex:
        self.CMD = cleanLine
      elif match_CMDMiscRegex:
        self.CMDMisc = cleanLine
        pid = match_CMDMiscRegex.group(2)
        self.CMDArray[pid] = self.CMD
        self.CMDMiscArray[pid] = self.CMDMisc
      elif match_CMDFailureRegex:
        self.CMDStatus = cleanLine
        pid = match_CMDFailureRegex.group(2)
        print self.CMDArray[pid]
        print self.CMDMiscArray[pid]
        print self.CMDStatus
        print("###############################################################################")
        del self.CMDArray[pid]
        del self.CMDMiscArray[pid]
      elif match_CMDStatusRegex:
        pid = match_CMDStatusRegex.group(2)
        del self.CMDArray[pid]
        del self.CMDMiscArray[pid]
          
def main():
  d = CronLog()
  parser = OptionParser()
  parser.add_option("-f", "--file", dest="filename",
                    help="log file to use for error report")
  parser.add_option("-u", "--user", dest="username",
                    help="user to audit in log file")
  parser.add_option("-p", "--pid", dest="pidnumber",
                    help="pid number to look for in log file")
  (options, args) = parser.parse_args()
  
  if options.filename:
    d.setFileName(options.filename)
  if options.username:
    d.setUserName(options.username)
  if options.pidnumber:
    d.setPid(options.pidnumber)

  d.setRegex()
  d.printErrors()
       			
if __name__ == "__main__":
  main()

