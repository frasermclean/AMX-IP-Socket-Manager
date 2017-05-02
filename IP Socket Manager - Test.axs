PROGRAM_NAME='IP Socket Manager - Test'

INCLUDE 'IP Socket Manager - Header'

DEFINE_DEVICE

	dvSocket				= 0:2:0
	vdvSocket_tx		= 33001:1:0
	vdvSocket_rx		= 33001:2:0

DEFINE_VARIABLE

	// ip address and port of host we want to connect to
	volatile char caIPaddr[] = '10.176.32.10'
	volatile integer nPort = 13000

DEFINE_MODULE

	//'IP Socket Manager v6' mdlSocket (dvSocket, vdvSocket_tx, caIPaddr, nPort)
	'IP Socket Manager v7' mdlSocket (dvSocket, vdvSocket_tx, caIPaddr, nPort)
	
DEFINE_EVENT

	data_event [vdvSocket_tx]
	{
		online:
		{
			// module settings (all optional)
			send_command vdvSocket_tx, 'Debug 1' // enable debugging
			send_command vdvSocket_tx, 'KeepAlive 1' // tell module to keep connection alive
			send_command vdvSocket_tx, 'Delay 500' // delay in milliseconds between packets
		}
	}
	
	data_event [vdvSocket_rx]
	{
		string:
		{
			// parse strings from remote host
		}
	}