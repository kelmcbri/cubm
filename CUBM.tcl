# Script Version: 2.1
# Script Name: CUBM
#-------------------------------------------------------------------------
# Originally Created September 9, 2009 , Keller McBride kelmcbri@cisco.com
#-------------------------------------------------------------------------
# This version created July 29, 2013 Keller McBride
#-------------------------------------------------------------------------
# Description: 
# This is a TCL script to create a Bed Management interface between
# Cisco Unified Communications Manager and HCA Meditech Bed Management
# This program communicates to Meditech via the Cloverleaf application
# The program uses a protocol specified by Cloverleaf over a TCP connection.
#
# INBOUND DATA TO CLOVERLEAF FROM  Router
# Data Format ASCII text
# Data Example:
#        Room Status Change:
#
#        ?ST    8099 PR MI    7896 DS 2012:05:12 13:01:02?
#
#Cloverleaf PROCESS RULES:
#1.	ROOM STATUS
#           CL - CLean
#           PR - Cleaning in PRogress
#
#Any additional room status sent by PBX should be ignored.
#
#2.	MAID ID 
#If no Maid ID is entered, PBX will send a 9999 in the Maid Id field.
#
#Data Layout from  PBX 
#Position		Field Name 		Value			Data type
# 1 			Beginning Character 	StartCharacter 		(02Hex)
# 2-3 			STATUS ST 		ST (hardcoded)		Denote Status message
# 4 			Space
# 5-6-7-8-9-10-11 	Room Number 		XXXXXXX 		1-7 digits right justified
# 12 			Space
# 13-14 		Room Status 		PR or CL 		CL=cleaned; PR=cleaning in progress
# 15 			Space
# 16-17 		MaidID to Follow 	MI 			Denotes Maid Id will follow
# 18 			Space
# 19-20-21-22 		Value for Maid Id 	XXXX 			Can be 1?4 digits right justified. Not required. If no maid id entered, Cloverleaf will pad with generic id 9999
# 23 			Space
# 24-25 		TimeStamp to Follow 	DS 			DS Denotes Date/TimeStamp to Follow
# 26 			Space
# 27-28-29-30 		Year 			XXXX CCYY 		Date/Time stamp Year
# 31 			Space
# 32-33 		Month 			XX 			MM Date/Time stamp month
# 34 			Separator		: 			
# 35-36 		Hour 			XX 			HH (valid time hour in 24 hr format)
# 37 			Separator 		:
# 38-39 		Minutes 		XX 			MM(Valid time minutes)
# 40 			Separator		:
# 41-42 		Seconds 		XX 			SS Date/Time Stamp Seconds
# 43 			Ending Character 				End Character (03 Hex)
#
#-------------------------------------------------------------------
# Version 1.1 fixes
# changed printf function in sendCloverleaf procedure to accept leading 0s for room number and maidID
#
# Version 1.2 Changes
#    "debug voice application scripts"  will now print embedded help messages to router console as program runs
#    Added a catch in cubm-eem.tcl to print error message to router console if tcp connection to Cloverleaf failed.
#    NEW TIMESTAMP ADDED TO PACKET SENT TO CLOVERLEAF - positions 25-32 inserted
#
# Version 2.0 Changes
#    Added central-time-offset parameter to allow the router to have central timezone configured even when you want
#    cubm to run in a different timezone.  HCA requires all network devices be managed in Central Timezone
#    Added room-digits parameter to router config.  It allows you to enter a 4 or 5 depending on the number of
#    digits in your room numbers.#
# Version 2.1 Changes
#     Fixed CUBM to work with OneVoice 10 Digit dial plan
#      The room number was pulling the FIRST x digits instead of the LAST x digits from the ani
#       in proc act_ValidateMaidID.

proc init { } {
    global digit_collect_params
    global selectCnt
    global callInfo
    global legConnected

    set digit_collect_params(interruptPrompt) true
    set digit_collect_params(abortKey) *
    set digit_collect_params(terminationKey) #
    set digit_collect_params(dialPlan) true
    set digit_collect_params(enableReporting) true

    set selectCnt 0
    set legConnected false

    param register aa-pilot "CUBM pilot number" "234" "s"
    param register aa-pilot2 "CUMB pilot number ask room" "235" "s"
    param register cloverleaf-ip "IP Address of Cloverleaf server" "127.0.0.1" "s"
    param register cloverleaf-port "Port number to access Cloverleaf server" "12345" "i"
    param register maid-id-pattern "Pattern to use to match maid ID" "...." "s"
    param register room-digits "Number of digits in room number" "5" "i"
    param register central-timezone-offset "offset in hours from central timezone" "+0" "i"
}

proc init_ConfigVars { } {
    global destination
    global aaPilot
    global aaPilot2
    global oprtr

    global cloverleafIP
    global cloverleafPort
    global maidIDPattern
    global roomDigits
    global roomNumPattern
    global centralTimezoneOffset

# aa-pilot is the IVR number configured on the gateway - will use ANI as room number
# aa-pilot2 is the IVR number configured on the gateway - will ask for room number
# operator is the operator number for assisted calling

    set aaPilot [string trim [infotag get cfg_avpair aa-pilot]]
    set aaPilot2 [string trim [infotag get cfg_avpair aa-pilot2]]
    set cloverleafIP [string trim [infotag get cfg_avpair cloverleaf-ip]]
    set cloverleafPort [string trim [infotag get cfg_avpair cloverleaf-port]]
    set maidIDPattern [string trim [infotag get cfg_avpair maid-id-pattern]]
    set roomDigits [string trim [infotag get cfg_avpair room-digits]]
    set roomNumPattern [string repeat "." $roomDigits]
    set centralTimezoneOffset [string trim [infotag get cfg_avpair central-timezone-offset]]
}

proc init_perCallVars { } {
    puts "        Entering procedure init_perCallvars"
    global ani
    global anilength
    global digit_enabled
    global fcnt
    global retrycnt
    global dnis
    global useAniAsRoom

    set fcnt 0
    set retrycnt 6
    set ani ""
    set dnis ""

    set digit_enabled "FALSE"
    set ani [infotag get leg_ani]
    puts "        The Calling ANI is: $ani"
    set anilength [string length $ani]
    puts "        ANI has $anilength digits"
    set dnis [infotag get leg_dnis]
    puts "        The called number DNIS is: $dnis"

}

proc act_Setup { } {
    global digit_collect_params
    global selectCnt
    global dest
    global beep
    global callInfo
    global dnis
    global fcnt
    global aaPilot
    global aaPilot2
    global oprtr
    global busyPrompt
    global legConnected
    global useAniAsRoom

    puts "        Entering procedure act_Setup"
    set busyPrompt _dest_unreachable.au
    set beep 0
    init_perCallVars
    infotag set med_language 1

    if { ($dnis == "") || ($dnis == $aaPilot2) } {
        leg setupack leg_incoming
    	leg proceeding leg_incoming
    	leg connect leg_incoming
        set legConnected true
        puts "        Match No DNIS or DNIS is aaPilot2"
		set useAniAsRoom false
        fsm setstate PLAYMAIDID
        act_PlayMaidID
    } elseif { ($dnis == $aaPilot) } {
	    leg setupack leg_incoming
    	leg proceeding leg_incoming
    	leg connect leg_incoming
        set legConnected true
		set useAniAsRoom true
        puts "        The Dailed number DNIS matched aaPilot: $aaPilot"
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
    puts "        Entering procedure act_GotDest"
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
        puts "        Call [infotag get con_all] got event $status collecting destination"
	set dest [infotag get evt_dcdigits]
	if { $dest == "0" } {
		set dest $oprtr
		handoff callappl leg_incoming default "DESTINATION=$dest"
	} else {
        	act_Select
	}
    }
    puts "        The destination digits entered were $dest"
}

proc act_CallSetupDone { } {
    global busyPrompt
    global legConnected 

    set status [infotag get evt_handoff_string]
    if { [string length $status] != 0} {
        regexp {([0-9][0-9][0-9])} $status StatusCode
        puts "        IP IVR Disconnect Status = $status" 
        switch $StatusCode {
          "016" {
              puts "        Connection success\n"
              fsm setstate CONTINUE
              act_Cleanup 
          }
          default {
              if { $legConnected == "false" } {
                  leg proceeding leg_incoming  
                  leg connect leg_incoming  
                  set legConnected true 
              }
              puts "        Call failed.  Play prompt and collect digit"
              if { ($StatusCode == "017") } {
                  set busyPrompt _dest_busy.au
              } 
              act_Select
          }
        } 
    } else {
        puts "        Caller disconnected\n" 
        fsm setstate CALLDISCONNECT 
        act_Cleanup 
    }
}

proc act_Select { } {
    global destination
    global promptFlag2
    global destBusy
    global digit_collect_params
    global fcnt
    global retrycnt
    global busyPrompt

    puts "        Entering procedure act_Select"

    set promptFlag2 0
    set digit_collect_params(interruptPrompt) true
    set digit_collect_params(abortKey) *
    set digit_collect_params(terminationKey) #
    set digit_collect_params(dialPlan) true
    set digit_collect_params(dialPlanTerm) true

    leg collectdigits leg_incoming digit_collect_params 
    if { $fcnt < $retrycnt } {
    	media play leg_incoming $busyPrompt %s500 _reenter_dest.au
        incr fcnt
        fsm setstate GETROOM
    } else {
        act_DestBusy
    }
}

proc act_PlayMaidID { } {
    global digit_collect_params
    global maidIDPattern
    puts "        Entering procedure PlayMaidID"

    set pattern(account) $maidIDPattern
    leg collectdigits leg_incoming digit_collect_params pattern
    media play leg_incoming _get_maid_id.au

    fsm setstate VALIDATEMAIDID
}
proc act_ValidateMaidID { } {
    global maidID
    global useAniAsRoom
    global ani
    global roomID
    global roomDigits
    global anilength

    set maidID [infotag get evt_dcdigits]
    puts "        Entering procedure act_ValidateMaidID"
    puts "        These were the Digits entered for maidID: $maidID"

    puts "        ***using dialing number ANI as room number:*** $useAniAsRoom"

    if { $useAniAsRoom == "true" } {
	set roomID [string range $ani [expr $anilength - $roomDigits ] $anilength]

	fsm setstate PLAYROOMSTATUS
	act_PlayRoomStatus
    } else {
	fsm setstate PLAYROOMID
	act_PlayRoomID
    }
}
proc act_PlayRoomID { } {
    global digit_collect_params
    global roomNumPattern

    puts "         Entering procedure PlayRoomID"

    set pattern(account) $roomNumPattern
    leg collectdigits leg_incoming digit_collect_params pattern

    media play leg_incoming _get_room_num.au

    fsm setstate VALIDATEROOMID
}
proc act_ValidateRoomID { } {
    global roomID

    set roomID [infotag get evt_dcdigits]
    puts "        Entering procedure act_ValidateRoomID"
    puts "        These are the roomID Digits: $roomID"

    fsm setstate PLAYROOMSTATUS

    act_PlayRoomStatus
}
proc act_PlayRoomStatus { } {
    global digit_collect_params
    global roomID

    puts "        Entering procedure PlayRoomStatus"
    puts "        The room number being used is: $roomID"

    set pattern(account) .
    leg collectdigits leg_incoming digit_collect_params pattern

    media play leg_incoming _get_status.au

    fsm setstate VALIDATEROOMSTATUS
}
proc act_ValidateRoomStatus { } {
    global roomStatus

    set roomStatus [infotag get evt_dcdigits]
    puts "        Entering procedure act_ValidateRoomStatus"
    puts "        This is the digit entered for roomStatus: $roomStatus"

    fsm setstate SENDCLOVERLEAF

    act_SendCloverleaf
}
proc act_DestBusy { } {
    puts "        Entering procedure act_DestBusy"
    media play leg_incoming _disconnect.au
    fsm setstate CALLDISCONNECT
}
proc act_Cleanup { } {
    call close
}
proc act_SendCloverleaf { } {
    global cloverleafIP
    global cloverleafPort
    global maidID
    global roomID
    global roomStatus
    global currentDateTimeSeconds
    global currentDateTimeString
    global centralTimezoneOffset

    puts "        Entering Procedure sendCloverleaf"

    set currentDateTimeSeconds [clock seconds]
    set currentDateTimeString [clock format $currentDateTimeSeconds -format {%H:%M:%S}]
    
    puts "        The Time from the router is :$currentDateTimeString"
    puts "        Your offset from Central Timezone is :$centralTimezoneOffset hours"
    
    set currentDateTimeSeconds [expr $currentDateTimeSeconds + [expr $centralTimezoneOffset * 3600]]
    set currentDateTimeString [clock format $currentDateTimeSeconds -format {%Y:%m:%d %H:%M:%S}]
    
    puts "        The DateTime to send to Cloverleaf is :$currentDateTimeString"
    puts "        This includes an offset from Central time of :$centralTimezoneOffset hours"

    
    if { $roomStatus == 2 } {
        set roomStringStatus "CL"
    } else {
        set roomStringStatus "PR"
    }
    
    set cloverleafCommand [format "%%CUBM%% %s:%s (%cST %7s %s MI    %4s DS %s %c)" $cloverleafIP $cloverleafPort "02" $roomID $roomStringStatus $maidID $currentDateTimeString "03"]
    puts "        Writing message to syslog on router\n"
    log -s INFO $cloverleafCommand
    puts "        Leaving Procedure sendCloverleaf"
    fsm setstate SAYBYEBYE
    act_SayGoodbye
}
proc act_SayGoodbye {} {
    puts "        Entering Procedure act_SayGoodbye"
    media play leg_incoming _goodbye.au
    fsm setstate CALLDISCONNECT
}

requiredversion 2.0
init 
init_ConfigVars
#----------------------------------
#   State Machine
#----------------------------------

set fsm(any_state,ev_disconnected)                "act_Cleanup  same_state"
set fsm(CALL_INIT,ev_setup_indication)            "act_Setup  PLAYMAIDID"
set fsm(PLAYMAIDID,ev_any_event)                  "act_PlayMaidID VALIDATEMAIDID"
set fsm(VALIDATEMAIDID,ev_collectdigits_done)     "act_ValidateMaidID PLAYROOMID"
set fsm(PLAYROOMID,ev_any_event)                  "act_PlayRoomID VALIDATEROOMID"
set fsm(VALIDATEROOMID,ev_collectdigits_done) 	  "act_ValidateRoomID PLAYROOMSTATUS"
set fsm(PLAYROOMSTATUS,ev_any_event)              "act_PlayRoomStatus VALIDATEROOMSTATUS"
set fsm(VALIDATEROOMSTATUS,ev_collectdigits_done) "act_ValidateRoomStatus SENDCLOVERLEAF"
set fsm(SENDCLOVERLEAF,ev_any_event)              "act_SendCloverleaf SAYBYEBYE"
set fsm(HANDOFF,ev_returned)                      "act_CallSetupDone  CONTINUE"
set fsm(SAYBYEBYE,ev_any_event)			  "act_SayGoodbye CALLDISCONNECT"
set fsm(CALLDISCONNECT,ev_media_done)             "act_Cleanup  same_state"

fsm define fsm CALL_INIT
