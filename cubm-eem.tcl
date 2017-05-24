::cisco::eem::event_register_syslog occurs 1 pattern {.*%CUBM% .*} maxrun 9

namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

# 1. query the information of latest triggered eem event
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

set sd [socket $ip $port]

puts -nonewline $sd [string trim $msg]
puts -nonewline $sd "\r"

flush $sd
close $sd
