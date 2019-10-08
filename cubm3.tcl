# Script Locked by: khom
# Script Version: 2.0.4.0
# Script Name: its_CISCO
# Script Lock Date: Wed Jul  2 09:22:04 2003
#------------------------------------------------------------------
#
# November 27, 2001, Satish Ananthanarayana (sanantha@cisco.com)
#
# Modification History:
# --------------------
# May 20, 2008, Jasmine Kalaiselvan (jkalaise@cisco.com)
#
# Modified the script to do leg setup and then handovers the call
# to Default IOS app. DDTS for this change: CSCsq35953 CSCsl08148
#
# Modified by: Raghavendra GV
# Modified Date: June 14, 2018
# - Added CLI params initial-digit-timeout and inter-digit-timeout
#
# --------------------------------------------------------
# Copyright (c) 2001 by cisco Systems, Inc.
# All rights reserved.
#------------------------------------------------------------------
#
# Description:
#       This is a TCL IVR script for the IOS Telephony Service and
#       Call Manager (CM) offload scenario. The IVR script plays a
#       welcome prompt to the user and prompts the user to enter a
#       destination number when the user dials the auto-attendant number
#       (aa-pilot configured in the CLI). The script collects the digits that
#       the user has entered and hands the call to the enhanced session
#       application (named Default).  The session application
#       returns once there is a disconnect (if the call is established)
#       or if a call setup problem occurs.
#       The operator support is also included, if the user does not dial
#       any number or enters "0" the user will be transfered to an operator
#       (if operator number is configured in the CLI). If the user enters
#       an invalid number, the user will be prompted again to re-enter
#       the number for upto 3 times before disconnecting the call.
#
#-------------------------------------------------------------------
#


proc init { } {
    global param1
    global callInfo
    global legConnected
    global maxExtensionLen

    set param1(interruptPrompt) true
    set param1(abortKey) *
    set param1(terminationKey) #

    set legConnected false
}

proc init_ConfigVars { } {
    global param1
    global aaPilot
    global oprtr
    global maxExtensionLen

# aa-pilot is the IVR number configured on the gateway to be used by the customer
# operator is the operator number for assisted calling

    if [infotag get cfg_avpair_exists aa-pilot] {
        set aaPilot [string trim [infotag get cfg_avpair aa-pilot]]
    } else {
        set aaPilot "NONE"
    }
    if [infotag get cfg_avpair_exists operator] {
        set oprtr [string trim [infotag get cfg_avpair operator]]
    } else {
        set oprtr "NONE"
    }
    if [infotag get cfg_avpair_exists initial-digit-timeout] {
        set param1(initialDigitTimeout) [string trim [infotag get cfg_avpair initial-digit-timeout]]
    } else {
        set param1(initialDigitTimeout) 10
    }
    if [infotag get cfg_avpair_exists inter-digit-timeout] {
        set param1(interDigitTimeout) [string trim [infotag get cfg_avpair inter-digit-timeout]]
    } else {
        set param1(interDigitTimeout) 10
    }
    if [infotag get cfg_avpair_exists max-extension-length] {
        set maxExtensionLen [string trim [infotag get cfg_avpair max-extension-length]]
        if { $maxExtensionLen < 0 } {
            call close
        }
    } else {
        set maxExtensionLen 5
    }
}

proc init_perCallVars { } {
    puts "\nproc init_perCallvars"
    global ani
    global fcnt
    global retrycnt
    global dnis

    set fcnt 0
    set retrycnt 6
    set ani ""
    set dnis ""

    set ani [infotag get leg_ani]
    puts "\nANI $ani"
    set dnis [infotag get leg_dnis]
    puts "\nDNIS $dnis"
}

proc act_Setup { } {
    global param1
    global dest
    global callInfo
    global dnis
    global fcnt
    global aaPilot
    global oprtr
    global busyPrompt
    global legConnected

    puts "proc act_Setup"
    set busyPrompt _dest_unreachable.au
    init_perCallVars
    infotag set med_language 1

    if { ($dnis == "") || ($dnis == $aaPilot) } {
        leg setupack leg_incoming
        leg proceeding leg_incoming
        leg connect leg_incoming
        set legConnected true

        puts "\nNo DNIS\n"
        set param1(dialPlan) true
        leg collectdigits leg_incoming param1

        media play leg_incoming _welcome.au %s1000 _enter_dest.au
    } else {
        set fcnt 6
        leg setupack leg_incoming
        #handoff callappl leg_incoming default "DESTINATION=$dnis"
        set callInfo(alertTime) 30
        leg setup $dnis callInfo leg_incoming
        fsm setstate HANDOFF
    }


}

proc act_GotDest { } {
    global dest
    global maxExtensionLen
    global destExtLen
    global callInfo
    global oprtr
    global busyPrompt
    puts "\n proc act_GotDest"
    set status [infotag get evt_status]
    set callInfo(alertTime) 30
    puts "\n STATUS: $status"
    puts "\n MAXEXTENSION: $maxExtensionLen"
    if {  ($status == "cd_004") } {
        set dest [infotag get evt_dcdigits]
        set destExtLen [string length $dest]
        puts "\n DESTLEN: $destExtLen"
        set extLength [expr $maxExtensionLen - $destExtLen]
        if { $dest == "0" } {
            set dest $oprtr
        }
        puts "\n extLength: $extLength"

        #handoff callappl leg_incoming default "DESTINATION=$dest"
        if {($maxExtensionLen > 0) && ($extLength >= 0)} {
            leg setup $dest callInfo leg_incoming
        } else {
            set busyPrompt _dest_unreachable.au
            act_Select
        }
    } elseif { ($status == "cd_001") || ($status == "cd_002") } {
        set dest $oprtr
        #handoff callappl leg_incoming default "DESTINATION=$dest"
        leg setup $dest callInfo leg_incoming
    } else {
        if { $status == "cd_006" } {
            set busyPrompt _dest_unreachable.au
        }
        puts "\nCall [infotag get con_all] got event $status collecting destination"
        set dest [infotag get evt_dcdigits]
        if { $dest == "0" } {
            set dest $oprtr
            #handoff callappl leg_incoming default "DESTINATION=$dest"
            leg setup $dest callInfo leg_incoming
        } else {
            act_Select
        }
    }
}

proc act_CallSetupDone { } {
    global busyPrompt
    global legConnected

    set status [infotag get evt_status]
    if { $status == "ls_000" } {
        puts "\n Connection success"
        handoff appl leg_all default
        act_Cleanup
    } else {
        if { $legConnected == "false" } {
            leg proceeding leg_incoming
            leg connect leg_incoming
            set legConnected true
        }
        puts "\n Call failed.  Play prompt and collect digit"
        if { ($status == "ls_007") } {
            set busyPrompt _dest_busy.au
        }
        act_Select
   }
}

proc act_Select { } {
    global param1
    global fcnt
    global retrycnt
    global busyPrompt

    puts "\n proc act_Select"

    set param1(interruptPrompt) true
    set param1(abortKey) *
    set param1(terminationKey) #
    set param1(dialPlan) true
    set param1(dialPlanTerm) true

    leg collectdigits leg_incoming param1
    if { $fcnt < $retrycnt } {
        media play leg_incoming $busyPrompt %s500 _reenter_dest.au
        incr fcnt
        fsm setstate GETDEST
    } else {
        act_DestBusy
    }
}

proc act_DestBusy { } {
    puts "\n proc act_DestBusy"
    media play leg_incoming _disconnect.au
    fsm setstate CALLDISCONNECT
}

proc act_Cleanup { } {
    call close
}

requiredversion 2.0
init

init_ConfigVars
#----------------------------------
#   State Machine
#----------------------------------
  set fsm(any_state,ev_disconnected)   "act_Cleanup  same_state"
  set fsm(any_state,ev_disconnect_done)   "act_Cleanup  same_state"
  set fsm(CALL_INIT,ev_setup_indication) "act_Setup  GETDEST"
  set fsm(GETDEST,ev_collectdigits_done) "act_GotDest HANDOFF"
  #set fsm(HANDOFF,ev_returned)   "act_CallSetupDone  CONTINUE"
  set fsm(HANDOFF,ev_setup_done)   "act_CallSetupDone  CONTINUE"
  set fsm(CALLDISCONNECT,ev_media_done) "act_Cleanup  same_state"
  fsm define fsm CALL_INIT
# Script Approval Signature: C/775c
