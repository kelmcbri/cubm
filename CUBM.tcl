# Script Version: 3
# Script Name: CUBM
#-------------------------------------------------------------------------
# Originally Created September 9, 2009 , Keller McBride kelmcbri@cisco.com
#   and Marcus Butler
#-------------------------------------------------------------------------
# Description:
# This is a TCL script to create a Bed Management interface between
# Cisco Unified Communications Manager and Meditech Bed Management
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
# Position			Field Name 		Value		Note
# 1				Beginning Character	Start Character (02 Hex)
# 2-3				STATUS			ST		ST  (hard coded) Denote Status message
# 4				Space
# 5-6-7-8-9-10-11-12-13-14	Room Number		XXXXXXXXXX	1-10 digits #right justified
# 15				Space
# 16-17				Room Status		PR or CL	CL=cleaned; PR=cleaning in progress
# 18				Space
# 19-20				MaidID to Follow	MI		Denotes Maid Id #will follow
# 21				Space
# 22-23-24-25			Value for Maid Id	XXXX		Can be #1-4 digits right justified.  Not required.  If no maid id entered, #Cloverleaf will pad with generic id 9999
# 26				Space
# 27-28				TimeStamp to Follow	DS		DS Denotes Date/Time Stamp to Follow
# 29				Space
# 30-31-32-33			Year			XXXX		CCYY Date/Time stamp Year
# 34							:
# 35-36				Month			XX		MM Date/Time stamp month
# 37							:		Separator
# 38-39				Day			XX		Day Date/Time Stamp Day of Month
# 40				Space
# 41-42				Hour			XX		HH (valid time hour in 24 hr format)
# 43							:		Separator
# 44-45				Minutes			XX		MM(Valid time minutes)
# 46							:		Separator
# 47-48				Seconds			XX		SS Date/Time Stamp Seconds
# 49				Ending Character	End Character 	(03 Hex)
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
# Version 2.2 Changes
#	Change max room number digits to 10 - was 7
# Version 2.4 Changes
#	Add a variable to set whether original Nortel Hospitality format is sent to Cloverleaf or new
#          Cisco format with timestamp added.
#          Variable useTimeStamp with Default TRUE added to procedure init_ConfigVars
# Version 3 Changes - Keller McBride 10/01/2019

proc init { } {
    global legConnected
    set legConnected false

    param register aa-pilot "CUBM pilot number" "1234" "s"
    param register aa-pilot2 "CUMB pilot number ask room" "2356" "s"
    param register cloverleaf-ip "IP Address of Cloverleaf server" "127.0.0.1" "s"
    param register cloverleaf-port "Port number to access Cloverleaf server" "12345" "i"
    param register maid-id-pattern "Pattern to use to match maid ID" "...." "s"
    param register room-digits "Number of digits in room number" "10" "i"
    param register central-timezone-offset "offset in hours from central timezone" "+0" "i"
    param register use_timestamp "Send Timestamp to Cloverleaf" "TRUE" "s"
}

proc init_ConfigVars { } {
    puts "\nEntering procedure init_perCallvars"
    global destination
    global aaPilot
    global aaPilot2

    global cloverleafIP
    global cloverleafPort
    global maidIDPattern
    global roomDigits
    global roomNumPattern
    global centralTimezoneOffset
    global useTimeStamp

    # aa-pilot is the IVR number configured on the gateway - will use ANI as room number
    # aa-pilot2 is the IVR number configured on the gateway - will ask for room number
    # operator is the operator number for assisted calling

    if [infotag get cfg_avpair_exists aa-pilot] {
        set aaPilot [string trim [infotag get cfg_avpair aa-pilot]]
    } else {
        set aaPilot "NONE"
    }

    if [infotag get cfg_avpair_exists aa-pilot2] {
        set aaPilot2 [string trim [infotag get cfg_avpair aa-pilot2]]
    } else {
        set aaPilot2 "NONE"
    }

    if [infotag get cfg_avpair_exists cloverleaf-ip] {
        set cloverleafIP [string trim [infotag get cfg_avpair cloverleaf-ip]]
    } else {
        set cloverleafIP "NONE"
    }

    if [infotag get cfg_avpair_exists cloverleaf-port] {
        set loverleafPort [string trim [infotag get cfg_avpair cloverleaf-port]]
    } else {
        set loverleafPort "NONE"
    }

    if [infotag get cfg_avpair_exists maid-id-pattern] {
        set maidIDPattern [string trim [infotag get cfg_avpair maid-id-pattern]]
    } else {
        set maidIDPattern "NONE"
    }

    if [infotag get cfg_avpair_exists room-digits] {
        set roomDigits [string trim [infotag get cfg_avpair room-digits]]
    } else {
        set roomDigits "NONE"
    }

    set roomNumPattern [string repeat "." $roomDigits]

    if [infotag get cfg_avpair_exists central-timezone-offset] {
        set centralTimezoneOffset [string trim [infotag get cfg_avpair central-timezone-offset]]
    } else {
        set centralTimezoneOffset "NONE"
    }

    if [infotag get cfg_avpair_exists use_timestamp] {
        set useTimeStamp [string trim [infotag get cfg_avpair use_timestamp]]
    } else {
        set useTimeStamp "TRUE"
    }
}

proc init_perCallVars { } {
    puts "\n       Entering procedure init_perCallvars"
    global ani
    global anilength
    global digit_enabled
    global dnis
    global useAniAsRoom

    set ani ""
    set dnis ""

    set digit_enabled "FALSE"
    set ani [infotag get leg_ani]
    puts "\n        The Calling ANI is: $ani"
    set anilength [string length $ani]
    puts "\n        ANI has $anilength digits"
    set dnis [infotag get leg_dnis]
    puts "\n        The called number DNIS is: $dnis"
}

proc act_Setup { } {
    global dnis
    global aaPilot
    global aaPilot2
    global legConnected
    global useAniAsRoom

    puts "\n        Entering procedure act_Setup"
    init_perCallVars
    infotag set med_language 1

    if { ($dnis == "") || ($dnis == $aaPilot2) } {
        leg setupack leg_incoming
     	  leg proceeding leg_incoming
    	  leg connect leg_incoming
        set legConnected true
        puts "\n        Match No DNIS or DNIS is aaPilot2"
		    set useAniAsRoom false
        fsm setstate PLAYMAIDID
        act_PlayMaidID
    } elseif { ($dnis == $aaPilot) } {
	      leg setupack leg_incoming
    	  leg proceeding leg_incoming
    	  leg connect leg_incoming
        set legConnected true
		    set useAniAsRoom true
        puts "\n        The Dailed number DNIS matched aaPilot: $aaPilot"
        fsm setstate PLAYMAIDID
        act_PlayMaidID
	  }
}

proc act_PlayMaidID { } {
    global digit_collect_params
    global maidIDPattern
    puts "\n        Entering procedure PlayMaidID"

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
    puts "\n        Entering procedure act_ValidateMaidID"
    puts "\n        These were the Digits entered for maidID: $maidID"
    puts "\n        ***using dialing number ANI as room number:*** $useAniAsRoom"

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

    puts "\n         Entering procedure PlayRoomID"

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

    puts "\n        Entering procedure PlayRoomStatus"
    puts "\n        The room number being used is: $roomID"

    set pattern(account) .
    leg collectdigits leg_incoming digit_collect_params pattern

    media play leg_incoming _get_status.au

    fsm setstate VALIDATEROOMSTATUS
}

proc act_ValidateRoomStatus { } {
    global roomStatus

    set roomStatus [infotag get evt_dcdigits]
    puts "\n        Entering procedure act_ValidateRoomStatus"
    puts "\n        This is the digit entered for roomStatus: $roomStatus"

    fsm setstate SENDCLOVERLEAF

    act_SendCloverleaf
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
    global useTimeStamp

    puts "\n        Entering Procedure sendCloverleaf"

    set currentDateTimeSeconds [clock seconds]
    set currentDateTimeString [clock format $currentDateTimeSeconds -format {%H:%M:%S}]

    puts "\n        The Time from the router is :$currentDateTimeString"
    puts "\n        Your offset from Central Timezone is :$centralTimezoneOffset hours"

    set currentDateTimeSeconds [expr $currentDateTimeSeconds + [expr $centralTimezoneOffset * 3600]]
    set currentDateTimeString [clock format $currentDateTimeSeconds -format {%Y:%m:%d %H:%M:%S}]

    puts "\n        The DateTime to send to Cloverleaf is :$currentDateTimeString"
    puts "\n        This includes an offset from Central time of :$centralTimezoneOffset hours"


    if { $roomStatus == 2 } {
        set roomStringStatus "CL"
    } else {
        set roomStringStatus "PR"
    }

    if { $useTimeStamp == "TRUE" } {
        set cloverleafCommand [format "%%CUBM%% %s:%s (%cST %10s %s MI    %4s DS %s %c)" $cloverleafIP $cloverleafPort "02" $roomID $roomStringStatus $maidID $currentDateTimeString "03"]
    } else {
    	    set cloverleafCommand [format "%%CUBM%% %s:%s (%cST %7s %s MI    %4s%c)" $cloverleafIP $cloverleafPort "02" $roomID $roomStringStatus $maidID "03"]
    }
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
set fsm(any_state,ev_disconnect_done)             "act_Cleanup  same_state"
set fsm(CALL_INIT,ev_setup_indication)            "act_Setup  PLAYMAIDID"
set fsm(PLAYMAIDID,ev_any_event)                  "act_PlayMaidID VALIDATEMAIDID"
set fsm(VALIDATEMAIDID,ev_collectdigits_done)     "act_ValidateMaidID PLAYROOMID"
set fsm(PLAYROOMID,ev_any_event)                  "act_PlayRoomID VALIDATEROOMID"
set fsm(VALIDATEROOMID,ev_collectdigits_done) 	  "act_ValidateRoomID PLAYROOMSTATUS"
set fsm(PLAYROOMSTATUS,ev_any_event)              "act_PlayRoomStatus VALIDATEROOMSTATUS"
set fsm(VALIDATEROOMSTATUS,ev_collectdigits_done) "act_ValidateRoomStatus SENDCLOVERLEAF"
set fsm(SENDCLOVERLEAF,ev_any_event)              "act_SendCloverleaf SAYBYEBYE"
set fsm(SAYBYEBYE,ev_any_event)			              "act_SayGoodbye CALLDISCONNECT"
set fsm(CALLDISCONNECT,ev_media_done)             "act_Cleanup  same_state"

fsm define fsm CALL_INIT
