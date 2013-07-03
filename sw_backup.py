#!/usr/bin/python

###########################################################
#
# Author: Luther Barnum
#
# Date: Feb 12, 2012
#
# Description: Simple script to download configurations from SAN switches
#
############################################################

import telnetlib

#switches = {"sanesp1":"password","sanesp2":"password","tapesan":"password","xpswitch11":"password","xpswitch12":"password","gevsanswitch11":"password","gevsanswitch12":"password"}
switches = {"brswitch13":"password1","brswitch14":"password1"}

password = "password1"
server = "10.10.9.1"
srv_user = "lgbarn"
srv_password = "Lutero03!"
for switch in switches:
  password = switches[switch]
  filename = switch + ".txt"
  print "Logging into " + switch
  tn = telnetlib.Telnet(switch)
  output = tn.read_until("login:")
  print "sending user"
  tn.write("admin\n")
  print "waiting for response"
  output = tn.read_until("Password:")
  print "sending password"
  tn.write(password+ "\n")
  print "waiting for response"
  output = tn.read_until(":admin>")
  print "uploading config"
  tn.write("configUpload " + server + "," + srv_user + "," + filename + "," + srv_password + "\n")
  print "waiting for response"
  output = tn.read_until(":admin>")

