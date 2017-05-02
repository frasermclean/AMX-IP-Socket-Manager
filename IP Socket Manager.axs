MODULE_NAME = 'IP Socket Manager' (dev dvDev, dev vdvComms, char caIPaddr[], integer nPort)

/*
	IP Socket Manager with integrated queue
	Programmer: Fraser McLean
	
	Version history
	v1: Original release.
	v2:
	v3:
	v4: Keep alive added
	v5: Delay moved to command
	v6: Validates IP address and IP device
	v7: Provide Channel Feedback for ONLINE state of module (Hugh Ogilvy). Also made 'Reinit' command disconnect comms to allow re-connect with new IP address etc
	v8: Formatting consistency for debugging (FM)
	v9: Restructured checker from wait to timeline. Tightened up timings. More formatting fixes.
	v10: Added command for vdvComms to fnCloseConnection (Serkan Ozcan) - See lines 249-254
	v11: Fixed long standing bug with open connection
	v12 (git): Moved code to git. Removed version number. See git commit notices for further changes.
*/


DEFINE_CONSTANT

	// comms device index
	COMM_TX				= 1 		// from main program
	COMM_RX				= 2 		// back to main program

	ERRORLEVEL_MAX		= 3
	BUFFER_DEPTH_MAX	= 255		// number of strings to queue up
	BUFFER_LENGTH_MAX	= 1024	// max length of incoming strings
	CHECKER_FREQ		= 100		// how frequently the checker runs
	DELAY_DEFAULT		= 100		// delay between sending packets
	
	// wait times
	WT_TIMEOUT			= 50		// how long to keep socket alive after sending last item in queue
	WT_ERROR				= 50
	
	// timelines
	TL_CHECKER			= 1
	TL_QUEUE				= 2
	
	CHAN_ONLINE_FB		= 251		// Device Communicating feedback channel - taken from SNAPI: DEVICE_COMMUNICATING = 251   // Feedback:  Device online event

DEFINE_VARIABLE

	volatile dev vdvResponse	// used for sending back response from remote host to main program using port 2 of virtual comms device

	volatile integer nDebug
	volatile integer nOnline, nAttemptingConnection
	volatile integer nErrorLevel, nErrorWait
	volatile char caaQueue[BUFFER_DEPTH_MAX][BUFFER_LENGTH_MAX]	
	volatile integer nQueueDepth
	volatile integer nKeepAlive
	volatile long lDelay = DELAY_DEFAULT
	
	// timeline times
	volatile long laCheckerTimes[] = { CHECKER_FREQ }
	volatile long laTLqueue[] = { DELAY_DEFAULT }	
	
DEFINE_FUNCTION fnDebug (char caMsg[]) // send debugging messages to console
{
	if (nDebug)
		send_string 0, "'[IPSM ', itoa(vdvComms.number), '] ', caMsg"
	else
		return
}
	
DEFINE_FUNCTION fnInit() // sets up variables and starts queue timeline
{
	stack_var integer nCount
	
	if (nOnline)
		fnCloseConnection()		// Added v7 - Hugh Ogilvy - to make a 'Reinit' command disconnect, allowing re-connectiong with a new IP address, etc
	
	for (nCount=1; nCount<BUFFER_DEPTH_MAX; nCount++)
		caaQueue[nCount] = ''
	
	nQueueDepth = 0
	nErrorLevel = 0
	laTLqueue[1] = lDelay
	
	// (re)create timeline
	if (timeline_active(TL_QUEUE))
		timeline_kill (TL_QUEUE)
	timeline_create (TL_QUEUE, laTLqueue, length_array(laTLqueue), TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
	
	fnDebug ('fnInit() Initialized.')
}

DEFINE_FUNCTION fnSendRemoveShift() // send and remove first item in queue and then shift array
{
	stack_var integer nCount
	
	if (nQueueDepth)
	{
		send_string dvDev, caaQueue[1]
		
		fnDebug ("'fnSendRemoveShift() sent ', itoa(length_string(caaQueue[1])), ' bytes. ', caaQueue[1]")
		
		for (nCount=1; nCount<nQueueDepth; nCount++)
		{
			caaQueue[nCount] = caaQueue[nCount+1]
			caaQueue[nCount+1] = ''
		}
		
		nQueueDepth--
		
		if (nQueueDepth == 0)
			caaQueue[1] = ''
	}
	else
	{
		fnDebug ('fnSendRemoveShift() called but no data in queue')
	}
}

DEFINE_FUNCTION integer fnIsValidIPaddr (char caIPaddr[]) // checks that ip address is in correct format
{
	stack_var char caIPaddrToCompare[15]
	stack_var char caOctet[4]
	stack_var integer nOctet
	stack_var integer nValidIPaddr
	stack_var integer nCount
	
	caIPaddrToCompare = caIPaddr
	nValidIPaddr = 1
	
	for (nCount=1; nCount<=4; nCount++)
	{
		// get value of each octet
		if (nCount < 4)
			caOctet = remove_string (caIPaddrToCompare, '.', 1)
		else
			caOctet = caIPaddrToCompare
		
		nOctet = atoi(caOctet)
		
		// validate octet
		if ( (nOctet == 0 && nCount == 1) || nOctet > 255)
		{
			nValidIPaddr = 0
			break
		}
	}
	
	return nValidIPaddr	
}
	
DEFINE_FUNCTION fnOpenConnection () // establish connection to remote host
{	
	// verify it is an ip device
	if (dvDev.NUMBER != 0)
	{
		fnDebug ('fnOpenConnection() error - trying to open an ip connection on a non ip device.')
		return
	}
	
	// validate ip address and port
	if (!fnIsValidIPaddr(caIPaddr) || !nPort)
	{
		fnDebug ("'fnOpenConnection() error - ip address and/or port number invalid. IP=', caIPaddr, ' port=', itoa(nPort)")
		return
	}
	
	if (nAttemptingConnection)
	{
		fnDebug ('fnOpenConnection() called but previous attempt is still active.')
		return
	}
	
	// open connection
	if (!nOnline)
	{
		fnDebug ("'fnOpenConnection() attempting connection to: ', caIPaddr, ':', ITOA(nPort)")	
		ip_client_open (dvDev.PORT, caIPaddr, nPort, IP_TCP)
		
		nAttemptingConnection = true
	}
}

DEFINE_FUNCTION fnCloseConnection () // close connection to remote host
{
	ip_client_close (dvDev.PORT)
	
	nOnline = false
	nAttemptingConnection = false
	fnDebug ('fnCloseConnection() Closing connection.')
	//cancel_wait 'AttemptingConnectionTimeout'
}

DEFINE_START
	
	// initialize buffer
	fnInit()
	
	// create response device
	vdvResponse = vdvComms.NUMBER:vdvComms.PORT+1:vdvComms.SYSTEM
	rebuild_event()
	
	// start checker timeline
	timeline_create (TL_CHECKER, laCheckerTimes, length_array(laCheckerTimes), TIMELINE_ABSOLUTE, TIMELINE_REPEAT)
	
DEFINE_EVENT

	data_event [vdvComms] // data coming from main program
	{
		command:
		{
			if (find_string(data.text, 'Debug ', 1))
			{
				remove_string (data.text, ' ', 1)
				nDebug = atoi(data.text)
				
				
				if (nDebug)
					fnDebug ('Debugging on.')
				else
					fnDebug ('Debugging off.')
			}
			
			if (find_string(data.text, 'Reinit', 1))
			{
				fnDebug ('Reinitializing...')				
				fnInit()				
			}
			
			if (find_string(data.text, 'KeepAlive ', 1))
			{
				remove_string(data.text, ' ', 1)
				nKeepAlive = atoi(data.text)
				fnDebug ("'Keep alive set to ', itoa(nKeepAlive)")
				if (nKeepAlive && (!nOnline))
					fnOpenConnection()		// If set to keep socket alive, and we're not online, open the connection right away
			}
			
			if (find_string(data.text, 'OpenConnection', 1))
			{
				fnDebug ("'Main program requested to open connection'")
				if (!nOnline)
					fnOpenConnection()
			}
			
			if (find_string(data.text, 'CloseConnection', 1))
			{
				fnDebug ("'Main program requested to close connection'")
				if (nOnline)
					fnCloseConnection()
			}
			
			if (find_string(data.text, 'Delay ', 1))
			{
				remove_string(data.text, ' ', 1)
				lDelay = atoi(data.text)
				fnDebug ("'Delay set to ', itoa(lDelay)")
				fnInit()
			}
			if (find_string(data.text, 'Init', 1))
			{
				fnDebug ('Init command received')
				fnInit()
			}
		}
		
		
		string: // receive new string from main program
		{
			fnDebug ("'Received string. Length=', itoa(length_string(data.text)), '. String=', data.text")
			
			if (nQueueDepth < BUFFER_DEPTH_MAX)
			{
				nQueueDepth++
				
				if (length_string(data.text) > BUFFER_LENGTH_MAX)
				{
					caaQueue[nQueueDepth] = left_string(data.text, BUFFER_LENGTH_MAX)		// put first part of packet in one queue element
					if (nQueueDepth < BUFFER_DEPTH_MAX)
					{
						nQueueDepth++
						caaQueue[nQueueDepth] = mid_string(data.text, BUFFER_LENGTH_MAX + 1, length_string(data.text) - BUFFER_LENGTH_MAX)	// Put 2nd part in another queue element
					}
					else
						fnDebug ('Error - buffer is full.')
				}
				else
				{
					caaQueue[nQueueDepth] = data.text
				}
			}
			else
			{
				fnDebug ('Error - buffer is full.')
			}			
		}
	}

	data_event [dvDev]
	{
		online:
		{
			nOnline = true
			nAttemptingConnection = false
			//cancel_wait 'AttemptingConnectionTimeout'
			nErrorLevel = 0
			on [vdvComms, CHAN_ONLINE_FB]
			fnDebug ('Online.')
		}
		offline:
		{
			nOnline = false
			nAttemptingConnection = false
			off [vdvComms, CHAN_ONLINE_FB]
			fnDebug ('Offline.')
		}
		string: // string received from remote host
		{
			fnDebug ("'Received response - ', data.text")
			send_string vdvResponse, data.text // send response back to main program
		}
		onerror:
		{
			if (nOnline)
				fnCloseConnection ()
			
			nOnline = false
			nAttemptingConnection = false
			off [vdvComms, CHAN_ONLINE_FB]
			nErrorLevel++
			
			switch (data.number)
			{
				case 2:		fnDebug ('Error - General failure (out of memory)')
				case 4:		fnDebug ('Error - Unknown host')
				case 6:		fnDebug ('Error - Connection refused')
				case 7:		fnDebug ('Error - Connection timed out')
				case 8:		fnDebug ('Error - Unknown connection error')
				case 9:		fnDebug ('Error - Already closed')
				case 14:		fnDebug ('Error - Local port already used')
				case 16:		fnDebug ('Error - Too many open sockets')
				case 17:		fnDebug ('Error - Local Port Not Open')
				default:		fnDebug ('Error - Unknown error')
			}
			
			nErrorWait = true
			wait (WT_ERROR)
			{
				nErrorWait = false
				
				if (nErrorLevel >= ERRORLEVEL_MAX)
				{
					fnDebug ('Reached maxium error level. Reinitializing...')
					fnInit()
				}
			}
		}
	}
	
	timeline_event [TL_CHECKER]
	{
		// check if we need to open connection
		if (nQueueDepth || nKeepAlive)
		{
			if (!nOnline && !nAttemptingConnection && !nErrorWait)
				fnOpenConnection()
		}
		
		// close connection if nothing to send
		else
		{
			if (nOnline)
			{
				wait (WT_TIMEOUT)
				{
					if (nOnline && !nKeepAlive)
					{
						fnDebug ('Queue is empty. Closing connection.')
						fnCloseConnection()
					}
				}
			}
		}
	}
	
	timeline_event [TL_QUEUE]
	{
		if (nOnline && nQueueDepth)
			fnSendRemoveShift()
	}
