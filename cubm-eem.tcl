::cisco::eem::event_register_syslog occurs 1 pattern {.*%CUBM% .*} maxrun 9

namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

# This is cubm-eem.tcl version 2
# Mechanism has been added to meter out messages to Cloverleaf every 3 seconds
# (There is some issue that keeps Cloverleaf from accepting messages sent close together)

# Query the information of latest triggered eem event
array set arr_einfo [event_reqinfo]
if {$_cerrno != 0} {
    set result [format "component=%s; subsys err=%s; posix err=%s;\n%s" \
      $_cerr_sub_num $_cerr_sub_err $_cerr_posix_err $_cerr_str]
    error $result 
}

set msg $arr_einfo(msg)

set match ""
set ip ""
set port ""

regexp {.*%CUBM% (.*?):(.*?) \((.*?)\)} $msg match ip port msg

#Set lastTimeSnet to zero in case we haven't saved the value before and read the previous value
set lastTimeSent 0
set getLastTimeSent [appl_reqinfo key "showLastTimeSent"]
set nowTime [clock seconds]

#If the first element in the list is 'data', then the second element is the value we need
if {[ lindex $getLastTimeSent 0 ] == "data" } {
    set lastTimeSent [ lindex $getLastTimeSent 1 ]
}

# If the current time is less than three seconds from the last message sent, wait 3 seconds
if { [expr $nowTime - $lastTimeSent] < 3 } {
    puts -nonewline "\r Waiting 3000 seconds.\r"
    after 3000
}

#Now send the message to Cloverleaf
if { [catch {set sd [socket $ip $port]}] } {
   puts -nonewline stderr "        Connection to Cloverleaf at $ip : $port has Failed ***\n\r"
   exit 1
 } else {
    puts -nonewline "\r $msg sent to Cloverleaf at $ip : $port\r"
    puts -nonewline $sd [string trim $msg]
    puts -nonewline $sd "\r"
    flush $sd
    close $sd
}

#Update the last time sent value to current time for the next policy instance
set lastTimeSent [clock seconds]
appl_setinfo key "showLastTimeSent" data $lastTimeSent
