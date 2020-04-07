# Script Version: 3.1
# Script Name: cubm
#-------------------------------------------------------------------------
# Originally Created September 9, 2009 , Keller McBride kelmcbri@cisco.com
#   and Marcus Butler
#-------------------------------------------------------------------------
# Description:
# This is a TCL script to create a Bed Management interface between
# Cisco Unified Communications Manager and Meditech Bed Management
# This program communicates to Meditech via the Cloverleaf application
# The program uses a protocol specified by Cloverleaf over a TCP connection.
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
#    Added central-time-offset digit-collect-paramseter to allow the router to have central timezone configured even when you want
#    cubm to run in a different timezone.  Customer requires all network devices be managed in Central Timezone
#    Added room-digits digit-collect-paramseter to router config.  It allows you to enter a 4 or 5 depending on the number of
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
# Version 3 Changes - Keller McBride Week 2 Covid-19
# Tested with various router software loads.
#  Running on Cisco 4331 router with Cisco IOS XE Software, Version 16.12.03
#   Older versions of software caused DTMF digit collection to work incorrectly.
#    MUST use dtmf-relay rtp-nte on dial-peers

proc init { } {
    puts "     Entering procedure init"
    global legConnected
    global digit-collect-params
    set digit-collect-params(interruptPrompt) true
    set digit-collect-params(abortKey) *
    set digit-collect-params(terminationKey) #
    set digit-collect-params(dialplan) false
    set legConnected false


    param register aa-pilot "CUBM pilot number" "1234" "s"
    param register aa-pilot2 "CUMB pilot number ask room" "2356" "s"
    param register cloverleaf-ip "IP Address of Cloverleaf server" "127.0.0.1" "s"
    param register cloverleaf-port "Port number to access Cloverleaf server" "12345" "i"
    param register maid-id-pattern "Pattern to use to match maid ID" "...." "s"
    param register room-digits "Number of digits in room number" "3" "i"
    param register central-timezone-offset "offset in hours from central timezone" "+0" "i"
    param register use_timestamp "Send Timestamp to Cloverleaf" "TRUE" "s"
}

proc init_ConfigVars { } {
    puts "     Entering procedure init_ConfigVars"
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

    if [infotag get cfg_avpair_exists aa-pilot] {
        set aaPilot [string trim [infotag get cfg_avpair aa-pilot]]
        puts "        aa-pilot set to $aaPilot"
    } else {
        set aaPilot "NONE"
    }

    if [infotag get cfg_avpair_exists aa-pilot2] {
        set aaPilot2 [string trim [infotag get cfg_avpair aa-pilot2]]
        puts "        aa-pilot2 set to $aaPilot2"
    } else {
        set aaPilot2 "NONE"
    }

    if [infotag get cfg_avpair_exists cloverleaf-ip] {
        set cloverleafIP [string trim [infotag get cfg_avpair cloverleaf-ip]]
        puts "        cloverleaf-ip set to $cloverleafIP"
    } else {
        set cloverleafIP "NONE"
    }

    if [infotag get cfg_avpair_exists cloverleaf-port] {
        set cloverleafPort [string trim [infotag get cfg_avpair cloverleaf-port]]
        puts "        cloverleaf-port set to $cloverleafPort"
    } else {
        set cloverleafPort "NONE"
    }

    if [infotag get cfg_avpair_exists maid-id-pattern] {
        set maidIDPattern [string trim [infotag get cfg_avpair maid-id-pattern]]
        puts "        maid-id-pattern set to $maidIDPattern"
    } else {
        set maidIDPattern "NONE"
    }

    if [infotag get cfg_avpair_exists room-digits] {
        set roomDigits [string trim [infotag get cfg_avpair room-digits]]
        puts "        room-digits set to $roomDigits"
    } else {
        set roomDigits "NONE"
    }

    set roomNumPattern [string repeat "." $roomDigits]

    if [infotag get cfg_avpair_exists central-timezone-offset] {
        set centralTimezoneOffset [string trim [infotag get cfg_avpair central-timezone-offset]]
        puts "        central-timezone-offset set to $centralTimezoneOffset"
    } else {
        set centralTimezoneOffset "NONE"
    }

    if [infotag get cfg_avpair_exists use_timestamp] {
        set useTimeStamp [string trim [infotag get cfg_avpair use_timestamp]]
        puts "        use_timestamp set to $useTimeStamp"
    } else {
        set useTimeStamp "TRUE"
    }
}

proc init_perCallVars { } {
    puts "     Entering procedure init_perCallvars"
    global ani
    global anilength
    global digit_enabled
    global dnis
    global useAniAsRoom

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
    global dnis
    global aaPilot
    global aaPilot2
    global legConnected
    global useAniAsRoom
    global digit-collect-params
    global digitcollect
    global interruptPrompt

    set digitcollect ""
    set digit-collect-params(interruptPrompt) true
    set digit-collect-params(abortKey) *
    set digit-collect-params(terminationKey) #
    set digit-collect-params(maxDigits) 4
    set digit-collect-params(initialDigitTimeout) 3
    set digit-collect-params(interDigitTimeout) 3


    puts "     Entering procedure act_Setup"
    init_perCallVars
    infotag set med_language 1

    if { ($dnis == "") || ($dnis == $aaPilot2) } {
        puts "        Match No DNIS or DNIS matched aaPilot2: $aaPilot2"
		    set useAniAsRoom false
    } elseif { ($dnis == $aaPilot) } {
		    set useAniAsRoom true
        puts "        The Dailed number DNIS matched aaPilot: $aaPilot"
	  }
    leg setupack leg_incoming
    leg proceeding leg_incoming
    leg connect leg_incoming
    set legConnected true
    fsm setstate PLAYMAIDID
    act_PlayMaidID
}

proc act_checkStatus { } {
  global getStatus
  switch $getStatus {
                  "cd_001" {
                            puts "        cd_001 The digit collection timed out, because no digits were pressed and not enough digits were collected for a match."
                            }
                  "cd_002" {
                            puts "        cd_002 The digit collection was aborted, because the user pressed an abort key."
                            }
                  "cd_003" {
                            puts "        cd_003 The digit collection failed, because the buffer overflowed and not enough digits were collected for a match."
                            }
                  "cd_004" {
                            puts "        cd_004 The digit collection succeeded with a match to the dial plan."
                            }
                  "cd_005" {
                            puts "        cd_005 The digit collection succeeded with a match to one of the patterns."
                            }
                  "cd_006" {
                            puts "        cd_006 The digit collection failed because the number collected was invalid."
                            }
                  "cd_010" {
                            puts "        cd_010 The digit collection was terminated because of an unsupported or unknown feature or event"
                            }
                  "ms_000" {
                            puts "        ms_000 The prompt was successful and finished playing."
                            }
                  }
  return
}

proc act_PlayMaidID { } {
    global digit-collect-params
    global maidIDPattern
    global digitcollect
    global interruptPrompt

    puts "     Entering procedure PlayMaidID"

    set pattern(account) $maidIDPattern
    set digit-collect-params(interruptPrompt) true

    leg collectdigits leg_incoming digit-collect-params maidIDPattern
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
    global getStatus


    set maidID [infotag get evt_dcdigits]
    set getStatus [infotag get evt_status]
    puts "     Entering procedure act_ValidateMaidID"
    act_checkStatus
    puts "        These were the Digits entered for maidID: $maidID"
    puts "        Using calling number ANI as room number: $useAniAsRoom"

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
    global roomNumPattern
    global digit-collect-params

    puts "     Entering procedure PlayRoomID"

    set pattern() $roomNumPattern
    set digit-collect-params(maxDigits) 3

    leg collectdigits leg_incoming digit-collect-params
    media play leg_incoming _get_room_num.au

    fsm setstate VALIDATEROOMID
}

proc act_ValidateRoomID { } {
    global roomID
    global getStatus
    set roomID [infotag get evt_dcdigits]
    set getStatus [infotag get evt_status]

    puts "     Entering procedure act_ValidateRoomID"
    act_checkStatus
    puts "        These are the roomID Digits: $roomID"

    fsm setstate PLAYROOMSTATUS
    act_PlayRoomStatus
}

proc act_PlayRoomStatus { } {
    global roomID
    global digit-collect-params
    global digitcollect
    global interruptPrompt
    global roomStatusPattern


    puts "     Entering procedure PlayRoomStatus"
    puts "        The room number being used is: $roomID"

    set roomStatusPattern "."
    set digit-collect-params(interruptPrompt) true
    set digit-collect-params(maxDigits) 1

    leg collectdigits leg_incoming digit-collect-params roomStatusPattern

    media play leg_incoming _get_status.au

    fsm setstate VALIDATEROOMSTATUS
}

proc act_ValidateRoomStatus { } {
    global roomStatus
    global getStatus


    set roomStatus [infotag get evt_dcdigits]
    set getStatus [infotag get evt_status]

    puts "     Entering procedure act_ValidateRoomStatus"
    act_checkStatus
    puts "        This is the digit entered for roomStatus: $roomStatus"

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

    puts "     Entering Procedure sendCloverleaf"

    set currentDateTimeSeconds [clock seconds]
    set currentDateTimeString [clock format $currentDateTimeSeconds -format {%H:%M:%S}]

    puts "        The Time from the router is $currentDateTimeString"
    puts "        Your offset from Central Timezone is $centralTimezoneOffset hours"

    set currentDateTimeSeconds [expr $currentDateTimeSeconds + [expr $centralTimezoneOffset * 3600]]
    set currentDateTimeString [clock format $currentDateTimeSeconds -format {%Y:%m:%d %H:%M:%S}]

    puts "        The DateTime to send to Cloverleaf is $currentDateTimeString"
    puts "        This includes an offset from Central time of $centralTimezoneOffset hours"


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
    puts "        Writing message to syslog on router"
    log -s INFO $cloverleafCommand
    fsm setstate SAYBYEBYE
    act_SayGoodbye
}

proc act_SayGoodbye {} {
    puts "     Entering Procedure act_SayGoodbye"
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
