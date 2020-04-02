<<<<<<< HEAD
# cubm v2.4 [Cisco Unified Bed Management interface]
## Phone --> PBX --> Cisco Router --> Cloverleaf/Meditech Bed Management Interface 
### This version can switch between providing and not providing time stamps

## Motivation
=======
# cubm3 - Upgrade code for newer Cisco ISR4000 series routers
## Bed Management Interface
>>>>>>> cubm3
Hospitals need to quickly clean patient rooms to turn the room over to a new patient.  They typically have some sort of bed management system to help coordinate the process of getting a room cleaned and turned over.  Sometimes, this is a manual process involving a "bed board" written on the wall.  Most hospitals are moving towards electronic versions of the bed board.
Many legacy phone systems have a "hospitality" feature that allows a housekeeper to dial a number, input housekeeper ID, Bed#, and Cleaning Status.  Some hospitals take the output of that hospitality feature and feed it into their electronic bed management system.  Although many phone systems support hospitality, Cisco's Unified Communication Manager (CUCM) does not have a built in hospitality function.  This software is an effort to mitigate that feature gap and allow hospitals running CUCM the ability to have housekeepers enter bed status information from a phone. The software will work with output from Cisco and 3rd party PBXs as well. 

## How it works:
<<<<<<< HEAD
Cisco has an example router script written in TCL that performs IVR (Interactive Voice Response) - a caller dials a number, the router answers and asks questions the caller can respond to.  cubm.tcl is a tweak of that example TCL script running on a Cisco router.  You connect the router running cubm.tcl to your phone system (doesn't matter if its cisco or some other vendor) via SIP trunk or PRI and designate a phone number on your phone system that, when called, sends the call down the trunk to the cisco router.  cubm.tcl will answer the call and play a set of prompts (in English and Spanish) asking the caller, "What is your housekeeper ID", "What is the bed number", "Press 1 to start cleaning or 2 to finish."  The answers are saved in the router's syslog file.  In parallel, a Cisco Embedded Event Manager TCL script called cubm-eem.tcl running on the same router looks for entries from cubm.tcl in the router's syslog file.  If it sees an entry, it will open a TCP session with a Cloverleaf gateway and send the formatted message to Cloverleaf.  Cloverleaf takes the message it receives from CUBM, re-formats it (HL7) and sends it to the hospital's Bed Management System. (Meditech)
=======
Cisco has an example router script written in TCL that performs IVR (Interactive Voice Response) - a caller dials a number, the router answers and asks questions the caller can respond to.  cubm.tcl is a tweak of that example TCL script running on a Cisco router.  You connect the router running cubm.tcl to your phone system (doesn't matter if its Cisco or some other vendor) via SIP trunk or PRI and designate a phone number on your phone system that, when called, sends the call down the trunk to the Cisco router.  cubm.tcl will answer the call and play a set of prompts (in English and Spanish) asking the caller, "What is your housekeeper ID", "What is the bed number", "Press 1 to start cleaning or 2 to finish."  The answers are saved in the router's syslog file.  In parallel, a Cisco Embedded Event Manager TCL script called cubm-eem.tcl running on the same router looks for entries from cubm.tcl in the router's syslog file.  If it sees an entry, it will open a TCP session with a Cloverleaf gateway and send the formatted message to Cloverleaf.  Cloverleaf takes the message it receives from CUBM, re-formats it (HL7) and sends it to the hospital's Bed Management System. (Meditech)
>>>>>>> cubm3

### Features
- CUBM uses english/spanish prompts so very little training is needed for the housekeepers
- CUBM works the same with Cisco/Nortel/Avaya/whoever PBX - so there is consistency for the housekeepers that may move from facility to faciltiy.
- If a facilities bed numbers match the last x digits of the phone number, CUBM can read the "bed number" from the callerid automatically and will not prompt the housekeeper to enter the bed number. (Housekeeper dials one number to enter bed numbers manually and another number to have the system pull the bed number automatically.

<<<<<<< HEAD
### NOTE
- CUBM does not recieve any feedback from the bed management system... it doesn't know if the data supplied by the housekeeper is legitimate.
- CUBM does not check to validate that the housekeeper is legitimate.
- All the data is sent "in the clear" via a socket opened between the router and cloverleaf/meditech server. This data can be read by anyone with a network sniffer.
=======
CUBM uses English/Spanish prompts so very little training is needed for the housekeepers
CUBM works the same with Cisco/Nortel/Avaya/whoever PBX - so there is consistency for the housekeepers that may move from facility to faciltiy.
If a facilities bed numbers match the last x digits of the phone number, CUBM can read the "bed number" from the callerid automatically and will not prompt the housekeeper to enter the bed number.
CUBM does not recieve any feedback from the bed management system... it doesn't know if the data supplied by the housekeepr is legitimate.
>>>>>>> cubm3

## License

This project is licensed to you under the terms of the [Cisco Sample
Code License](./LICENSE).
