#!/usr/local/bin/python

import os
import sys
import re
import time
import datetime
import glob
import getopt

class Log:
  def __init__(self):
#    self.dir = "/opt/firewall/vpn/sn32077/LOG/"
#    self.file = "20070702.log"
    self.s_dir = str(self.dir)
    self.s_file = str(self.file)
    self.fullpath = self.dir + self.file
    self.loginTime = "00:00:00"
    self.logoutTime = "23:59:59"
    self.year = self.file[0:4]
    self.month = self.file[4:6]
    self.day = self.file[6:8]
    self.login = 0
    self.loginHour = "00"
    self.loginMin = "00"
    self.loginSec = "00"
    self.logoutHour = "23"
    self.logoutMin = "59"
    self.logoutSec = "59"
    self.userInfo = []

  def getUserDetails(self, user, files):
    self.user = user
    self.files = files
    loginMatch = "(\w+)\s+(\w+)\s+(..:..:..).*" + self.user + ".*logged\s+into\s+group"
    logoutMatch = "(\w+)\s+(\w+)\s+(..:..:..).*" + self.user + ".*logged\s+out"
    loginMatchCompile = re.compile(loginMatch) 
    logoutMatchCompile = re.compile(logoutMatch) 
    for File in files:
      print("%s file is being processed" % (File))
      self.handle = open(File)
      for line in self.handle:
        loginHit = re.search(loginMatchCompile, line)
        logoutHit = re.search(logoutMatchCompile, line)
        if loginHit:
          self.login = 1
          self.loginHour = loginHit.group(3)[0:2]
          self.loginMin = loginHit.group(3)[3:5]
          self.loginSec = loginHit.group(3)[6:8]
        if logoutHit:
          self.login = 0
          self.logoutHour = logoutHit.group(3)[0:2]
          self.logoutMin = logoutHit.group(3)[3:5]
          self.logoutSec = logoutHit.group(3)[6:8]
          userLogInfo = self.user + ":" + self.year + ":" + self.month + ":" + self.day + ":" + self.loginHour + ":" + self.loginMin + ":" + self.loginSec + ":" + self.year + ":" + self.month + ":" + self.day + ":" + self.logoutHour + ":" + self.logoutMin + ":" + self.logoutSec
          self.userInfo.append(userLogInfo)
    if self.login == 1:    
      userLogInfo = self.user + ":" + self.year + ":" + self.month + ":" + self.day + ":" + self.loginHour + ":" + self.loginMin + ":" + self.loginSec + ":" + self.year + ":" + self.month + ":" + self.day + ":" + self.logoutHour + ":" + self.logoutMin + ":" + self.logoutSec
      self.userInfo.append(userLogInfo)
    try:
      return self.userInfo
    except UnboundLocalError:
      userInfo = "NoLogin"
      return self.userInfo
  
  def getTotalTime(self, Log):
    self.Log = Log
    time = 0
    self.TotalTime = datetime.timedelta(hours=00,minutes=00,seconds=00)
    for Entry in Log:
      EntryX = re.split(r':', Entry)
      total = datetime.datetime(int(EntryX[7]), int(EntryX[8]), int(EntryX[9]), int(EntryX[10]), int(EntryX[11]), int(EntryX[12])) - datetime.datetime(int(EntryX[1]), int(EntryX[2]), int(EntryX[3]), int(EntryX[4]), int(EntryX[5]),  int(EntryX[6]))
      newtime = str(total)
      newtimeX = re.split(r':', newtime)
      self.TotalTime = self.TotalTime + datetime.timedelta(hours=int(newtimeX[0]), minutes=int(newtimeX[1]), seconds=int(newtimeX[2]))
    return self.TotalTime

def main():
  files = glob.glob('*.log')
  try:
    opts, args = getopt.getopt(sys.argv[1:], "hs:e:u:f:", ["help", "start=", "end=", "user", "file"])
  except getopt.GetoptError:
    # print help information and exit:
    usage()
    sys.exit(2)
  output = None
  verbose = False
  for o, a in opts:
    if o == "-v":
      verbose = True
    if o in ("-h", "--help"):
      usage()
      sys.exit()
    if o in ("-s", "--start"):
      print("Start = %s" % a)
    if o in ("-e", "--end"):
      print("End = %s" % a)
    if o in ("-u", "--user"):
      User = a
    if o in ("-f", "--file"):
      files = [a]
  d = Log()
  try:
    User
  except NameError:
    User = None
  if User is None:
    print("You must specify a user")
  else:
    compressedFiles = glob.glob('*.gz')
    g = d.getUserDetails(User, files)
    TotalTime = d.getTotalTime(g)
    print("%s was logged on for %s" % (User, TotalTime))



if __name__ == "__main__":
  main()
