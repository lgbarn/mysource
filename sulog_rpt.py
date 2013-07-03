#!/usr/local/bin/python

######################################################################################################
#
# Date: 11/04/2006
#
# Author: Luther Barnum
#
# Description: This program will send a report to root for SU Log entries
#
######################################################################################################


import os
import sys
import re

from datetime import datetime, timedelta
from socket import gethostname


# Modify the exclude list for users that should be excluded from the report
# for successful root logins
ExcludeList=["root","lgbarn","dayarg","rmwall"]

class SuLog:
  def __init__(self):
    self.SuLog="/home/lgbarn/sulog"
    self.LogArray = []

  def PrintLog(self):
    f = open(self.SuLog, "r")
    for i in f:
      print i,

  def GetLog(self):
    f = open(self.SuLog, "r")
    for i in f:
      clean = i.strip()
      self.LogArray.append(clean)
    return self.LogArray 

class SuLogLine:
  def __init__(self, line):
    self.line = line
    self.LineArray = re.split("\s+", line)

  def GetLine(self):
    return self.line

  def GetLineArray(self):
    return self.LineArray

  def GetDate(self):
    return self.LineArray[1]

  def GetTime(self):
    return self.LineArray[2]

  def GetPassFail(self):
    if self.LineArray[3] == '+':
      PassFail = "1"
    else:
      PassFail = "0"
    return PassFail

  def GetUser(self):
    self.User = self.LineArray[5]
    self.CleanUser = self.User.strip() 
    return self.CleanUser

  def GetUserSRC(self):
    self.UserSRC = re.split("-",self.LineArray[5])
    return self.UserSRC[0]

  def GetUserDST(self):
    self.UserSRC = re.split("-",self.LineArray[5])
    return self.UserSRC[1]


if __name__ == "__main__":
  #test = os.popen("uname -n")
  today = datetime.today()
  yesterday = today - timedelta(1)
  MyDate = re.split("[- ]", str(yesterday))
  YesterDay = re.split("[\s+]", str(yesterday))
  SearchDate = "%s/%s" % (MyDate[1], MyDate[2])
  y = SuLog()
  g = y.GetLog()
  UserArraySuccess = {}
  UserArrayFail = {}
  Keys = []
  for line in g:
    p = SuLogLine(line)
    if p.GetPassFail() == '1':
      SkipUser = "0"
      SkipDay = "0"
      UserSRC = p.GetUserSRC()
      if p.GetDate() <> SearchDate:
        SkipDay = "1"
        SkipUser = "1"
      for i in ExcludeList:
        if i == UserSRC:
          SkipUser = "1"
      if SkipUser == "0":
        try:
          UserArraySuccess[p.GetUser()] = UserArraySuccess[p.GetUser()] + 1
        except:
          UserArraySuccess[p.GetUser()] = + 1
    if p.GetPassFail() == '0':
      if SkipDay == "0":
        try:
          UserArrayFail[p.GetUser()] = UserArrayFail[p.GetUser()] + 1
        except:
          UserArrayFail[p.GetUser()] = + 1
  print("%s: SuLog Report for %s" % (gethostname(), YesterDay[0]))
  print("Successfull SuLog Entries")
  print("----------------------------------------------------")
  SuccessKeys = UserArraySuccess.keys()
  SuccessKeys.sort()
  for user in  SuccessKeys:
    print("%-20s%20s" % (user, UserArraySuccess[user]))
  print("====================================================")
  print("Failed SuLog Entries")
  print("----------------------------------------------------")
  FailedKeys = UserArrayFail.keys()
  FailedKeys.sort()
  for user in  FailedKeys:
    print("%-20s%20s" % (user, UserArrayFail[user]))
  print("====================================================")
