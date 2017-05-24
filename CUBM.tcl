# Script Version: 0.8
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
# Data Format ñ ASCII text file
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
#If no Maid ID is entered, PBX will send a ì0î in the Maid Id field.
#
#Cloverleaf should check to see if the Maid Id = ì0î move ì9999î to the #Maid ID field else Maid ID should be sent to Meditech. 
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
    param register room-num-pattern "Pattern to use to match room number" "...." "s"
}

proc init_ConfigVars { } {
    global destination
    global aaPilot
	global aaPilot2
    global oprtr

    global cloverleafIP
    global cloverleafPort
    global maidIDPattern
    global roomNumPattern

# aa-pilot is the IVR number configured on the gateway - will use ANI as room number
# aa-pilot2 is the IVR number configured on the gateway - will ask for room number
# operator is the operator number for assisted calling

    set aaPilot [string trim [infotag get cfg_avpair aa-pilot]]
	set aaPilot2 [string trim [infotag get cfg_avpair aa-pilot2]]
    set cloverleafIP [string trim [infotag get cfg_avpair cloverleaf-ip]]
    set cloverleafPort [string trim [infotag get cfg_avpair cloverleaf-port]]
    set maidIDPattern [string trim [infotag get cfg_avpair maid-id-pattern]]
    set roomNumPattern [string trim [infotag get cfg_avpair room-num-pattern]]
}

proc init_perCallVars { } {
    puts "\nproc init_perCallvars"
    global ani
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
    puts "\nANI $ani"
    set dnis [infotag get leg_dnis]
    puts "\nDNIS $dnis"

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

    puts "\n\nproc act_Setup\n\n"
    set busyPrompt _dest_unreachable.au
    set beep 0
    init_perCallVars
    infotag set med_language 1

    if { ($dnis == "") || ($dnis == $aaPilot2) } {
        leg setupack leg_incoming
    	leg proceeding leg_incoming
    	leg connect leg_incoming
        set legConnected true
        puts "\nMatch No DNIS or DNIS is aaPilot2\n"
		set useAniAsRoom false
        fsm setstate PLAYMAIDID
        act_PlayMaidID
    } elseif { ($dnis == $aaPilot) } {
	    leg setupack leg_incoming
    	leg proceeding leg_incoming
    	leg connect leg_incoming
        set legConnected true
		set useAniAsRoom true
        puts "\nMatch DNIS is aaPilot\n"
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
    global digit_collect_params
    global fcnt
    global retrycnt
    global busyPrompt

    puts "\n proc act_Select"

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
    puts "entering PlayMaidID"

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

    set maidID [infotag get evt_dcdigits]
    puts "entering act_ValidateMaidID"
    puts "Digits: $maidID\n"

    puts "***using Ani as room number:*** $useAniAsRoom\n"

    if { $useAniAsRoom == "true" } {
	set roomID [string range $ani 0 3]

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

    puts "entering PlayRoomID"

    set pattern(account) $roomNumPattern
    leg collectdigits leg_incoming digit_collect_params pattern

    media play leg_incoming _get_room_num.au

    fsm setstate VALIDATEROOMID
}
proc act_ValidateRoomID { } {
    global roomID

    set roomID [infotag get evt_dcdigits]
    puts "entering act_ValidateRoomID"
    puts "Digits: $roomID\n"

    fsm setstate PLAYROOMSTATUS

    act_PlayRoomStatus
}
proc act_PlayRoomStatus { } {
    global digit_collect_params

    puts "entering PlayRoomStatus"

    set pattern(account) .
    leg collectdigits leg_incoming digit_collect_params pattern

    media play leg_incoming _get_status.au

    fsm setstate VALIDATEROOMSTATUS
}
proc act_ValidateRoomStatus { } {
    global roomStatus

    set roomStatus [infotag get evt_dcdigits]
    puts "entering act_ValidateRoomStatus"
    puts "Digits: $roomStatus\n"

    fsm setstate SENDCLOVERLEAF

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
    global cloverleafIP
    global cloverleafPort
    global maidID
    global roomID
    global roomStatus

    puts "\n In Procedure sendCloverleaf\n"

    if { $roomStatus == 1 } {
        set roomStringStatus "PR"
    } else {
        set roomStringStatus "CL"
    }

    set cloverleafCommand [format "%%CUBM%% %s:%s (%cST %7u %s MI    %4u%c)" $cloverleafIP $cloverleafPort "02" $roomID $roomStringStatus $maidID "03"]

    log -s INFO $cloverleafCommand
    call close
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
set fsm(SENDCLOVERLEAF,ev_any_event)              "act_SendCloverleaf CALLDISCONNECT"
set fsm(HANDOFF,ev_returned)                      "act_CallSetupDone  CONTINUE"
set fsm(CALLDISCONNECT,ev_media_done)             "act_Cleanup  same_state"

fsm define fsm CALL_INIT
