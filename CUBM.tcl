# Script Version: 0.2
# Script Name: CUBM
#------------------------------------------------------------------
# September 9, 2009 , Keller McBride kelmcbri@cisco.com
#         
#------------------------------------------------------------------
#         
# Description: 
# This is a TCL script to create a Bed Management interface between
# Cisco Unified Communications Manager and HCA Meditech Bed Management
# This program communicates to Meditech via the Cloverleaf application
# The program uses a protocol specified by Cloverleaf over a TCP connection.
# 
# INBOUND DATA TO CLOVERLEAF FROM  PBX
# Data Format – ASCII text file
# Data Example:
#        Room Status Change:
# 
#        ?ST    8099 PR MI    7896?
# 
#PROCESS RULES:
#1.	ROOM STATUS
#CL - CLean
#PR -Cleaning in PRogress
# 
#Any additional room status sent by PBX should be ignored.
# 
#2.	MAID ID 
#If no Maid ID is entered, PBX will send a “0” in the Maid Id field.
# 
#Cloverleaf should check to see if the Maid Id = “0” move “9999” to the #Maid ID field else Maid ID should be sent to Meditech. 
# 
# 
#Data Layout from  PBX 
#Position	Field Name 	Value	Data type
#X = Alphanumeric
#9 = Numeric	Notes
#0	Beginning Character	Start Character	 (02HEX)	 
#1-2	STATUS	ST  (hard coded)	XX	Denote Status message 
# 
#3	Space	 	 	 
#4-5-6-7-8-9-10	Room Number	8099 (valid room number)	XXXXXXX	1-7 digits #right justified
#11	Space	 	 	 
#12-13	Room Status	PR (or CL)	XX	CL=cleaned; PR=cleaning in progress
#14	Space	 	 	 
#15-16	Denotes MAID ID to follow 	MI (hard coded)	XX	Denotes Maid Id #will follow
#17-18-19-20	Space	 	 	 
#21-22-23-24	Value for Maid Id	7896 (valid maid id)	XXXX	Can be #1-4 digits right justified.  Not required.  If no maid id entered, #Cloverleaf will pad with generic id 9999 
# 25	Ending Character	End Character	 	(03HEX) 
# 
# 
# 
#-------------------------------------------------------------------
         


proc init { } {
    global param1
    global selectCnt
    global callInfo
    global legConnected

    set param1(interruptPrompt) true
    set param1(abortKey) *
    set param1(terminationKey) #
    set selectCnt 0
    set legConnected false
	param register aa-pilot "CUBM pilot number" "*1234" "s"
	param register cloverleaf-ip "IP Address of Cloverleaf server" "127.0.0.1" "s"
	param register cloverleaf-port "Port number to access Cloverleaf server" "12345" "i"
}
proc init_ConfigVars { } {
    global destination
    global aaPilot
    global oprtr
	global cloverleafIP
	global cloverleafPort
	global cloverleafSocket

# aa-pilot is the IVR number configured on the gateway to be used by the customer
# operator is the operator number for assisted calling

    set aaPilot [string trim [infotag get cfg_avpair aa-pilot]]
    set cloverleafIP [string trim [infotag get cfg_avpair cloverleaf-ip]]
	set cloverleafPort [string trim [infotag get cfg_avpair cloverleaf-port]]
	set cloverleafSocket -1
}
proc init_CloverSocket { } {
	global 

	fsm setstate CLOVERSOCKETSET
}
proc init_perCallVars { } {
    puts "\nproc init_perCallvars"
    global ani
    global digit_enabled
    global fcnt
    global retrycnt
    global dnis

    set fcnt 0
    set retrycnt 6
    set ani ""
    set dnis ""

    set digit_enabled "FALSE"
    set ani [infotag get leg_ani]
    puts "\nANI $ani"
    set dnis [infotag get leg_dnis]
    puts "\nDNIS $dnis"
}

proc act_Setup { } {
    global param1
    global selectCnt
    global dest
    global beep
    global callInfo
    global dnis
    global fcnt
    global aaPilot
    global oprtr
    global busyPrompt
    global legConnected

    puts "\n\nproc act_Setup\n\n"
    set busyPrompt _dest_unreachable.au
    set beep 0
    init_perCallVars
    infotag set med_language 1

    if { ($dnis == "") || ($dnis == $aaPilot) } {
        leg setupack leg_incoming
    	leg proceeding leg_incoming
    	leg connect leg_incoming
        set legConnected true
		  

	puts "\nNo DNIS\n"
#       set param1(dialPlan) true
#       leg collectdigits leg_incoming param1
#       media play leg_incoming _get_maid_id.au
		fsm setstate PLAYMAIDID
		act_PlayMaidID
    } else {
        set fcnt 6
	leg setupack leg_incoming
        handoff callappl leg_incoming default "DESTINATION=$dnis"
        fsm setstate HANDOFF
    } 


}
proc act_GotDest { } {
    global dest
    global callInfo
    global oprtr
    global busyPrompt
    puts "\n proc act_GotDest"
    set status [infotag get evt_status]
    set callInfo(alertTime) 30

    if {  ($status == "cd_004") } {
        set dest [infotag get evt_dcdigits]
	if { $dest == "0" } {
		set dest $oprtr
	}
        handoff callappl leg_incoming default "DESTINATION=$dest"
    } elseif { ($status == "cd_001") || ($status == "cd_002") } {
	set dest $oprtr
        handoff callappl leg_incoming default "DESTINATION=$dest"
    }	else {
	if { $status == "cd_006" } {
		set busyPrompt _dest_unreachable.au
	}
        puts "\nCall [infotag get con_all] got event $status collecting destination"
	set dest [infotag get evt_dcdigits]
	if { $dest == "0" } {
		set dest $oprtr
		handoff callappl leg_incoming default "DESTINATION=$dest"
	} else {
        	act_Select
	}
    }
	puts "\nThe destination digits entered were $dest\n"
}
proc act_CallSetupDone { } {
    global busyPrompt
    global legConnected 

    set status [infotag get evt_handoff_string]
    if { [string length $status] != 0} {
        regexp {([0-9][0-9][0-9])} $status StatusCode
        puts "IP IVR Disconnect Status = $status" 
        switch $StatusCode {
          "016" {
              puts "\n Connection success"
              fsm setstate CONTINUE
              act_Cleanup 
          }
          default {
              if { $legConnected == "false" } {
                  leg proceeding leg_incoming  
                  leg connect leg_incoming  
                  set legConnected true 
              }
              puts "\n Call failed.  Play prompt and collect digit"
              if { ($StatusCode == "017") } {
                  set busyPrompt _dest_busy.au
              } 
              act_Select
          }
        } 
    } else {
        puts "\n Caller disconnected" 
        fsm setstate CALLDISCONNECT 
        act_Cleanup 
    }
}
proc act_Select { } {
    global destination
    global promptFlag2
    global destBusy
    global param1
    global fcnt
    global retrycnt
    global busyPrompt
    
    puts "\n proc act_Select"

    set promptFlag2 0
    set param1(interruptPrompt) true
    set param1(abortKey) *
    set param1(terminationKey) #
    set param1(dialPlan) true
    set param1(dialPlanTerm) true

    leg collectdigits leg_incoming param1 
    if { $fcnt < $retrycnt } {
    	media play leg_incoming $busyPrompt %s500 _reenter_dest.au
	incr fcnt
    	fsm setstate GETROOM
    } else {
	act_DestBusy
    }
}
proc act_PlayMaidID { } {
	puts "entering PlayMaidID"
	media play leg_incoming _get_maid_id.au
	fsm setstate GETMAIDID
}
proc act_GetMaidID { } {
	global param1
	set param1(dialPlan) true
	set pattern(account) .+
	puts "entering GetMaidID"
	set param1(enableReporting) true
	leg collectdigits leg_incoming param1 pattern
	fsm setstate VALIDATEMAIDID
}
proc act_ValidateMaidID { } {
	global maidID
	
	set maidID [infotag get evt_dcdigits]
	puts "entering act_ValidateMaidID"
	puts "Digits: $maidID\n"
	
	fsm setstate PLAYROOMID

	# FIXME: event workaround
	act_PlayRoomID
}
proc act_PlayRoomID { } {
	puts "entering PlayRoomID"
	fsm setstate GETROOMID
	media play leg_incoming _get_room_num.au
	act_GetRoomID
	#	fsm setstate GETROOMID
}
proc act_GetRoomID { } {
	global param1
	set param1(dialPlan) true
	set param1(interruptPrompt) true
	set pattern(account) .+
	puts "entering GetRoomID"
	set param1(enableReporting) true
	leg collectdigits leg_incoming param1 pattern
	fsm setstate VALIDATEROOMID
}
proc act_ValidateRoomID { } {
	global roomID
	
	set roomID [infotag get evt_dcdigits]
	puts "entering act_ValidateRoomID"
	puts "Digits: $roomID\n"
	
	fsm setstate PLAYROOMSTATUS

	# FIXME: event workaround
	act_PlayRoomStatus
}
proc act_PlayRoomStatus { } {
	puts "entering PlayRoomStatus"
	media play leg_incoming _get_status.au
	fsm setstate GETROOMSTATUS
}
proc act_GetRoomStatus { } {
	global param1
	set param1(dialPlan) true
	set param1(interruptPrompt) true
	set pattern(account) .+
	puts "entering GetRoomStatus"
	set param1(enableReporting) true
	leg collectdigits leg_incoming param1 pattern
	fsm setstate VALIDATEROOMSTATUS
}
proc act_ValidateRoomStatus { } {
	global roomStatus
	
	set roomStatus [infotag get evt_dcdigits]
	puts "entering act_ValidateRoomStatus"
	puts "Digits: $roomStatus\n"
	
	fsm setstate SENDCLOVERLEAF

	# FIXME: event workaround
	act_SendCloverleaf
}
proc act_DestBusy { } {
    puts "\n proc act_DestBusy"
    media play leg_incoming _disconnect.au
    fsm setstate CALLDISCONNECT
}
proc act_Cleanup { } {
    call close
}
proc act_SendCloverleaf { } {
	global sd

	puts "\n In Procedure giveClover\n"

	leg disconnect
#	set sd [socket "192.168.200.2" 80]
#	puts $sd {
#?ST    8099 PR MI    7896?
#	}
#	flush $sd
#	fsm setstate GAVECLOVER
}
proc receiveClover { } {
    puts "\n In Procedure receiveClover\n"
	fsm setstate GOTCLOVER
}
	
requiredversion 2.0
init 
init_ConfigVars
#----------------------------------
#   State Machine
#----------------------------------
  set fsm(any_state,ev_disconnected)   				"act_Cleanup  same_state"
  set fsm(CALL_INIT,ev_setup_indication) 			"act_Setup  PLAYMAIDID"
  set fsm(PLAYMAIDID,ev_any_event)					"act_PlayMaidID GETMAIDID"
  set fsm(GETMAIDID,ev_media_done)					"act_GetMaidID VALIDATEMAIDID"
  set fsm(VALIDATEMAIDID,ev_collectdigits_done)		"act_ValidateMaidID PLAYROOMID"
  set fsm(PLAYROOMID,ev_any_event)					"act_PlayRoomID GETROOMID"
  set fsm(GETROOMID,ev_media_done)					"act_GetRoomID VALIDATEROOMID"
  set fsm(VALIDATEROOMID,ev_collectdigits_done) 	"act_ValidateRoomID PLAYROOMSTATUS"
  set fsm(PLAYROOMSTATUS,ev_any_event)				"act_PlayRoomStatus GETROOMSTATUS"
  set fsm(GETROOMSTATUS,ev_media_done)				"act_GetRoomStatus VALIDATEROOMSTATUS"
  set fsm(VALIDATEROOMSTATUS,ev_collectdigits_done) "act_ValidateRoomStatus SENDCLOVERLEAF"
  set fsm(SENDCLOVERLEAF,ev_any_event)				"act_SendCloverleaf CALLDISCONNECT"
  set fsm(HANDOFF,ev_returned)   					"act_CallSetupDone  CONTINUE"
  set fsm(CALLDISCONNECT,ev_media_done) 			"act_Cleanup  same_state"

  fsm define fsm CALL_INIT
