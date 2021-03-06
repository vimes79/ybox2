{{
	ybox2 - bootloader object
	http://www.deepdarc.com/ybox2

	Designed for use with a 64KB EEPROM. It will not work
	properly with a 32KB EEPROM.

	INSTRUCTIONS

	The first time the bootloader runs it will generate a random MAC
	address and UUID, and will then store these with the settings object.
	These values will be remembered thereafter, and should never change.

	When the device normally boots, it will start looking for a DHCP
	server. While it is doing this, it will pulse blue. Once it gets
	assigned an IP address, it will make a chirp and the LED will go
	to its idle "rainbow" state. At this point you can read off the
	IP address from the screen and type that into a web browser.

	If you have a PAL TV, you will need to switch to PAL mode. Simply press
	and hold the button while the bootloader is idle ("rainbow" colored LED)
	until you hear a chirp. At this point the bootloader has toggled the
	video mode. You only have to do this once, your setting will be
	remembered across reboots.

	From the bootloader configuration page you can do things like set
	a password, enable/disable auto-boot, reboot, boot into stage 2,
	enter IR test mode, etc. You can also download previously uploaded
	firmware, configuration settings, etc.

	UPLOADING STAGE2 FIRMWARE

	To upload a new program to be bootloaded (called "stage 2"), you first
	need to make a binary of the program. You can make the binary file by
	pressing F8 in the propeller tool, waiting for the program to compile
	(important!), and then pressing "save binary file".

	To upload the file to the ybox2, you need to preform a HTTP PUT on
	<http://[IPADDRESS]/stage2.eeprom>.

	If you are having a hard time finding a way to do a HTTP PUT, I would
	recommend using cURL. <http://curl.haxx.se/>

	The following command, for example, will write the wwwexample.binary image:

	curl http://[IPADDRESS]/stage2.eeprom -T wwwexample.binary

	If you want the unit to immediately boot into stage2, simply add ?boot to
	the URL:

	curl http://[IPADDRESS]/stage2.eeprom?boot -T wwwexample.binary

	If you have set up a password, the command line is slightly different:

	curl --anyauth http://admin:PASSWORD@[IPADDRESS]/stage2.eeprom -T wwwexample.binary

	After uploading, the ybox2 will return an MD5 hash of the uploaded eeprom, followed
	by the word "OK".

	To boot into stage two with curl, you can use the following:

	curl http://[IPADDRESS]/stage2

	QUICK REFERENCE

	TO RESET: Hold down the button while booting. Keep holding it
			down until the system reboots. You will hear a lot of warning chirps,
			but make sure you hold down the button until it reboots! After it reboots
			let go. Your ybox2 has been reset. This will erase every setting except
			for the MAC address, UUID, and LED configuration. If you forget the
			password, this is what you need to do.

	TO BYPASS AUTOBOOT: Hold down the button while booting until you hear a single
			"groan" and the screen displays "Autoboot aborted.". At this point,
			the ybox2 will boot as if autoboot were disabled. This only applies
			to the current boot. DON'T HOLD DOWN THE BUTTON TOO LONG, OR ELSE THE
			UNIT WILL RESET.

	TO BOOT INTO STAGE2: When the bootloader is 'idle' (rainbow-colored LED), press
			and release the button. Don't hold the button down, or else you will
			toggle the video mode!

	TO TOGGLE NTSC/PAL: When the bootloader is 'idle' (rainbow-colored LED), press
			and hold the button until you hear a chirp---then let go.


                                       
}}
CON

  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000                                                      

OBJ

  websocket     : "api_telnet_serial"
  term          : "TV_Text"
  subsys        : "subsys"
  settings      : "settings"
  random        : "RealRandom"
  http          : "http"
  auth          : "auth_digest"                                   
  md5           : "MD5"
  base16        : "base16"
  pause         : "pause"
  fast_eeprom   : "Fast_I2C_Driver"
  
VAR
  long stage_two
  long stack[10] 
  byte hash[md5#HASH_LENGTH]
DAT
productName   BYTE      "ybox2 bootloader v"
productVersion BYTE     "1.2dev",0 
productURL    BYTE      "http://www.deepdarc.com/ybox2/",0
productURL2    BYTE     "http://ladyada.net/make/ybox2/",0

PUB init | i, tv_mode
  ' Default to NTSC
  tv_mode:=term#MODE_NTSC
  
  ' Load persistent environment settings  
  \settings.start  

  ' Fire up the almighty subsys
  subsys.init

  ' Set the direction on the sound pin depending
  ' on if we are muted or not.
  dira[subsys#SPKRPin]:=!settings.findKey(settings#MISC_SOUND_DISABLE)

  ' If we are in the second stage of a bootloader upgrade,
  ' then we need set the appropriate variable.
  if settings.findKey(settings#MISC_STAGE2)
    stage_two := TRUE
    settings.removeKey(settings#MISC_STAGE2)
    settings.removeKey(settings#MISC_AUTOBOOT)
  else
    stage_two := FALSE

  subsys.StatusLoading

  ' If there is a TV mode preference in the EEPROM, load it up.
  if settings.findKey(settings#MISC_TV_MODE)
    tv_mode := settings.getByte(settings#MISC_TV_MODE)
    
  ' Start the TV Terminal
  term.startWithMode(12,tv_mode)

  ' Output the title, URLs, and squigly line.
  printBanner

  if NOT stage_two AND settings.findKey(settings#MISC_AUTOBOOT)
    term.str(string("Autoboot..."))
    pause.delay_ms(2000)
    if NOT ina[subsys#BTTNPin]
      boot_stage2
    else
      term.out($0A)
      term.out($00)  
      term.str(string("Autoboot Aborted.",13))
      subsys.chirpSad    

  ifnot settings.findKey(settings#NET_MAC_ADDR)
    if \initial_configuration <> 1
      term.str(string("Initial configuration failed!",13))
      subsys.StatusFatalError
      subsys.chirpSad
      pause.delay_ms(20000)
    else
      subsys.chirpHappy
      pause.delay_ms(2000)
    reboot
  
  ' If the user is holding down the button, wait two seconds.
  repeat 10
    if ina[subsys#BTTNPin]
      pause.delay_ms(200)
    
  ' If the button is still being held down, then
  ' assume we are in a password reset condition.
  if ina[subsys#BTTNPin]
    subsys.chirpHappy
    subsys.chirpSad
    subsys.chirpHappy
    subsys.chirpSad
    subsys.chirpHappy
    if ina[subsys#BTTNPin]
      term.str(string("RESET MODE",13))
      subsys.chirpSad
      resetSettings
      subsys.chirpHappy
      reboot

  ' Init the auth object with some randomness
  random.start
  auth.init(random.random)
  random.stop

  ' Print out the MAC address on the TV
  term.str(string("MAC: "))  
  if settings.getData(settings#NET_MAC_ADDR,@stack,6)
    repeat i from 0 to 5
      if i
        term.out("-")
      term.hex(byte[@stack][i],2)
    term.out(13)  
  else
    term.str(string("???",13))

  if not \websocket.start(1,2,3,4,6,7)
    showMessage(string("Unable to start networking!"))
    subsys.StatusFatalError
    subsys.chirpSad
    outa[0]~ ' Pull ethernet reset pin low, starting a reset condition.
    ' Reboot after 20 seconds, unless the
    ' user presses the button causing a
    ' stage 2 boot.
    repeat 200
      buttonCheck
      pause.delay_ms(100)
    reboot

  ' Wait for the IP address if we don't already have one.
  if NOT settings.getData(settings#NET_IPv4_ADDR,@stack,4)
    term.str(string("IPv4 ADDR: DHCP..."))
    repeat while NOT settings.getData(settings#NET_IPv4_ADDR,@stack,4)
      buttonCheck
      pause.delay_ms(100)
    term.out($0A)
    term.out($00)  

  ' Output the IP address we have aquired.
  term.str(string("IPv4 ADDR: "))
  repeat i from 0 to 3
    if i
      term.out(".")
    term.dec(byte[@stack][i])
  term.out(13)  

  if stage_two
    subsys.FadeToColor(255,0,255,200)
    term.str(string("BOOTLOADER UPGRADE",13,"STAGE TWO",13))
  else
    subsys.StatusIdle
  
  ' Make a happy noise, we are moving along!
  subsys.chirpHappy

  ' Infinite loop
  repeat
    \httpServer
    term.str(string("WEBSERVER EXCEPTION",13))
    subsys.ChirpSad
    websocket.closeall
    
PRI resetSettings | key, nextKey, ledconf
'' Preforms a "factory reset" by removing all
'' settings except those used for device identification
'' and hardware configuration.
  key:=settings.firstKey
  ifnot key
    return
  repeat
    nextKey:=settings.nextKey(key)
    case key
      settings#NET_MAC_ADDR:   ' Preserve MAC Address
      settings#MISC_UUID:      ' Preserve UUID
      settings#MISC_LED_CONF:  ' Preserve LED Configuration ONLY if it is sane
        ' We need to do this check because it is possible
        ' for a misconfigured LED configuration to interfere
        ' with the ethernet controller.
        if settings.getData(key,@ledconf,4) < 4
          ' If we are less than the expected size, kill it
          settings.removeKey(key)
        elseifnot LEDConfIsSane(ledconf)
          ' Make sure no pin assignments are insane
          settings.removeKey(key)
      other: settings.removeKey(key)
  while (key:=nextKey)

  settings.commit
PRI LEDConfIsSane(ledconf) | i,pin
  repeat i from 0 to 17 step 8
    pin := ((ledconf>>i)&%11111)
    if ((1<<pin) & %1111_0000_0000_0000_0000_0000_1111_1111) OR pin == subsys#BTTNPin
      return false
  return true
  
PRI boot_stage2 | i
  settings.setByte(settings#MISC_STAGE2,TRUE)
 
  ' XXX: Is this really necessary?
  if stage_two
    ' If we are already in stage 2, forget it... just reboot.
    reboot

  fast_eeprom.stop
    
  ' Very aggressively shut down everything except our own cog
  repeat i from 0 to 7
    if cogid<>i
      cogstop(i)
    lockret(i)

  fast_eeprom.bootstrapFromEEPROM($8000,$8000-settings#SETTINGSSIZE)

PRI initial_configuration | i
  term.str(string("First boot!",13))

  settings.purge

  random.start

  ' Make a random UUID
  repeat i from 0 to 16
    byte[@stack][i] := random.random
  settings.setData(settings#MISC_UUID,@stack,16)

  ' Make a random MAC Address
  byte[@stack][0] := $02
  repeat i from 1 to 5
    byte[@stack][i] := random.random
  settings.setData(settings#NET_MAC_ADDR,@stack,6)

  random.stop

  settings.commit
  return 1

PUB atoi(inptr):retVal | i,char
  retVal~
  
  ' Skip leading whitespace
  repeat while BYTE[inptr] AND BYTE[inptr]==" "
    inptr++
   
  repeat 10
    case (char := BYTE[inptr++])
      "0".."9":
        retVal:=retVal*10+char-"0"
      OTHER:
        quit
pri printBanner
  term.str(string($0C,7))
  term.str(@productName)
  term.out(13)
  term.str(@productURL)
  term.out(13)
  term.str(@productURL2)
  term.out(13)
  term.out($0c)
  term.out(2)
  repeat term#cols/2
    term.out($8E)
    term.out($88)
  term.out($0c)
  term.out(0)
DAT
PALString     byte      "PAL",0
NTSCString     byte     "NTSC",0
ModeSelectedString     byte     " Mode Selected",13,0

pri buttonCheck
  if ina[subsys#BTTNPin]
    ' If the user is holding down the button, wait two seconds.
    repeat 10
      if ina[subsys#BTTNPin]
        pause.delay_ms(200)

    if ina[subsys#BTTNPin]
      ' The user is still holding down the button.
      ' They must want to change the video mode!

      term.stop

      if NOT settings.findKey(settings#MISC_TV_MODE) OR settings.getByte(settings#MISC_TV_MODE)==0
        settings.setByte(settings#MISC_TV_MODE,term#MODE_PAL)
        term.startWithMode(12,term#MODE_PAL)
        printBanner
        term.str(PALString)
      else
        settings.setByte(settings#MISC_TV_MODE,term#MODE_NTSC)
        term.startWithMode(12,term#MODE_NTSC)
        printBanner
        term.str(NTSCString)
      term.str(ModeSelectedString)

      settings.commit
      subsys.chirpHappy

      ' Wait for the user to let go
      repeat while ina[subsys#BTTNPin]
    else
      ' The user let go... They must just want to boot to stage2
      boot_stage2
    
  
VAR
  long align
  byte buffer [128]
  byte buffer2 [128]
  byte httpMethod[8]
  byte httpPath[64]
  byte httpQuery[64]
  byte httpHeader[32]

DAT
HTTP_VERSION  BYTE      "HTTP/1.1 ",0
HTTP_200      BYTE      "200 OK"
CR_LF         BYTE      13,10,0
HTTP_303      BYTE      "303 See Other",13,10,0
HTTP_400      BYTE      "400 Bad Request",13,10
HTTP_401      BYTE      "401 Authorization Required",13,10,0
HTTP_403      BYTE      "403 Forbidden",13,10,0
HTTP_404      BYTE      "404 Not Found",13,10,0
HTTP_411      BYTE      "411 Length Required",13,10,0
HTTP_501      BYTE      "501 Not Implemented",13,10,0

HTTP_HEADER_SEP     BYTE ": ",0
HTTP_HEADER_CONTENT_TYPE BYTE "Content-Type",0
HTTP_HEADER_LOCATION     BYTE "Location",0
HTTP_HEADER_CONTENT_DISPOS     BYTE "Content-disposition",0
HTTP_HEADER_CONTENT_LENGTH     BYTE "Content-Length",0
HTTP_HEADER_REFRESH BYTE "Refresh",0

HTTP_CONTENT_TYPE_HTML  BYTE "text/html; charset=utf-8",0
HTTP_CONNECTION_CLOSE   BYTE "Connection: close",13,10,0

OK         BYTE "OK",13,10,0


RAMIMAGE_EEPROM_FILE    BYTE "/ramimage.binary",0
STAGE2_EEPROM_FILE      BYTE "/stage2.eeprom",0
FULL_EEPROM_FILE      BYTE "/full.eeprom",0

CONFIG_BIN_FILE         BYTE "/config.bin",0
CONFIG_PLIST_FILE         BYTE "/config.plist",0

CON
  PASSWORD_MIN    = 3  
  PASSWORD_MAX    = 52  

pri httpUnauthorized(authorized)|challenge[20]
  websocket.str(@HTTP_VERSION)
  websocket.str(@HTTP_401)
  websocket.str(@HTTP_CONNECTION_CLOSE)
  auth.generateChallenge(@challenge,constant(20*4),authorized)
  websocket.txMimeHeader(string("WWW-Authenticate"),@challenge)
  websocket.str(@CR_LF)
  websocket.str(@HTTP_401)

pri httpNotFound
  websocket.str(@HTTP_VERSION)
  websocket.str(@HTTP_404)
  websocket.str(@HTTP_CONNECTION_CLOSE)
  websocket.str(@CR_LF)
  websocket.str(@HTTP_404)

pri parseIPStr(instr,outaddr) | char, i,j
  repeat j from 0 to 3
    BYTE[outaddr][j]:=0
  j:=0
  repeat while j < 4
    case BYTE[instr]
      "0".."9":
        BYTE[outaddr][j]:=BYTE[outaddr][j]*10+BYTE[instr]-"0"
      ".":
        j++
      other:
        quit
    instr++
  if j==3
    return TRUE
  abort FALSE 
     
pub httpServer | i,j,contentLength,authorized,stale,queryptr
  repeat
    repeat while \websocket.listen(80) < 0
      buttonCheck
      pause.delay_ms(1000)
      websocket.closeall
      next

    if stage_two
      subsys.FadeToColor(255,0,255,200)
    else
      subsys.StatusIdle

    contentLength:=0

    ' Wait for a connection
    repeat while NOT websocket.waitConnectTimeout(100)
      buttonCheck

    ' We have received a connection. Blink accordingly.
    subsys.StatusActivity

    if \http.parseRequest(websocket.handle,@httpMethod,@httpPath)<0
      websocket.close
      next

    ' If there isn't a password set, then we are by default "authorized"
    authorized:=NOT settings.findKey(settings#MISC_PASSWORD)

    repeat while \http.getNextHeader(websocket.handle,@httpHeader,32,@buffer,128)>0
      if strcomp(@httpHeader,@HTTP_HEADER_CONTENT_LENGTH)
        contentLength:=atoi(@buffer)
      elseif NOT authorized AND strcomp(@httpHeader,string("Authorization"))
        authorized:=auth.authenticateResponse(@buffer,@httpMethod,@httpPath)
        
    ' Authorization check
    ' You can comment this out if you want to
    ' be able to let unauthorized people see the
    ' front page. They won't be able to upload
    ' or download firmware, or change settings
    ' without being authorized because those
    ' actions check for authorization anyway.
    if authorized<>auth#STAT_AUTH
      httpUnauthorized(authorized)
      websocket.close
      next

    queryPtr:=http.splitPathAndQuery(@httpPath)         
    if strcomp(@httpMethod,string("GET")) or strcomp(@httpMethod,string("POST"))
      if strcomp(@httpPath,string("/"))
        websocket.str(@HTTP_VERSION)
        websocket.str(@HTTP_200)
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.txmimeheader(@HTTP_HEADER_CONTENT_TYPE,@HTTP_CONTENT_TYPE_HTML)        
        websocket.str(@CR_LF)
        indexPage(authorized)
      elseif strcomp(@httpPath,string("/info"))
        websocket.str(@HTTP_VERSION)
        websocket.str(@HTTP_200)
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.str(@CR_LF)
        infoPage
      elseif strcomp(@httpPath,string("/config"))
        if authorized<>auth#STAT_AUTH
          httpUnauthorized(authorized)
          websocket.close
          next
        i:=0
        repeat while contentLength AND i<127
          buffer[i++]:=websocket.rxtime(1000)
          contentLength--
        buffer[i]~
        buffer2[0]~
        if http.getFieldFromQuery(@buffer,string("dhcp"),@buffer2,64)
          if buffer2[0] == "0"
            settings.setByte(settings#NET_DHCPv4_DISABLE,1)
          else
            settings.removeKey(settings#NET_DHCPv4_DISABLE)
        if http.getFieldFromQuery(@buffer,string("addr"),@buffer2,64)
          parseIPStr(@buffer2,@buffer2+65)
          settings.setData(settings#NET_IPv4_ADDR,@buffer2+65,4)  
        if http.getFieldFromQuery(@buffer,string("mask"),@buffer2,64)
          parseIPStr(@buffer2,@buffer2+65)
          settings.setData(settings#NET_IPv4_MASK,@buffer2+65,4)  
        if http.getFieldFromQuery(@buffer,string("gate"),@buffer2,64)
          parseIPStr(@buffer2,@buffer2+65)
          settings.setData(settings#NET_IPv4_GATE,@buffer2+65,4)  
        if http.getFieldFromQuery(@buffer,string("dns1"),@buffer2,64)
          parseIPStr(@buffer2,@buffer2+65)
          settings.setData(settings#NET_IPv4_DNS,@buffer2+65,4)  
        settings.commit
        websocket.str(@HTTP_VERSION)
        websocket.str(@HTTP_200)
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.str(@CR_LF)
        websocket.str(string("Settings changed. Reboot required.",13,10))
         
      elseif strcomp(@httpPath,string("/password"))
        if authorized<>auth#STAT_AUTH
          httpUnauthorized(authorized)
          websocket.close
          next
        i:=0
        repeat while contentLength AND i<127
          buffer[i++]:=websocket.rxtime(1000)
          contentLength--
        buffer[i]~
        buffer2[0]~
        i:=http.getFieldFromQuery(@buffer,string("pwd1"),@buffer2,PASSWORD_MAX)
        if i and (i < PASSWORD_MIN)
          websocket.str(@HTTP_VERSION)
          websocket.str(@HTTP_400)
          websocket.str(@HTTP_CONNECTION_CLOSE)
          websocket.txmimeheader(@HTTP_HEADER_REFRESH,string("6;url=/"))        
          websocket.str(@CR_LF)
          websocket.str(string("Password too short.",13,10))        
        elseif i<>http.getFieldFromQuery(@buffer,string("pwd2"),@httpQuery,PASSWORD_MAX) OR NOT strcomp(@httpQuery,@buffer2)
          websocket.str(@HTTP_VERSION)
          websocket.str(@HTTP_400)
          websocket.str(@HTTP_CONNECTION_CLOSE)
          websocket.txmimeheader(@HTTP_HEADER_REFRESH,string("6;url=/"))        
          websocket.str(@CR_LF)
          websocket.str(string("Password mismatch, or password too long.",13,10))
        else
          auth.setAdminPassword(@httpQuery)           
          websocket.str(@HTTP_VERSION)
          websocket.str(@HTTP_303)
          websocket.str(@HTTP_CONNECTION_CLOSE)
          websocket.txmimeheader(@HTTP_HEADER_LOCATION,string("/"))        
          websocket.str(@CR_LF)
          websocket.str(@OK)
      elseif strcomp(@httpPath,string("/reboot"))
        websocket.str(@HTTP_VERSION)
        websocket.str(@HTTP_200)
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.txmimeheader(@HTTP_HEADER_REFRESH,string("12;url=/"))        
        websocket.str(@CR_LF)
        websocket.str(string("REBOOTING",13,10))
        websocket.close
        pause.delay_ms(100)
        outa[0]~ ' Pull ethernet reset pin low, starting a reset condition.
        reboot
      elseif strcomp(@httpPath,string("/irtest"))
        websocket.str(@HTTP_VERSION)
        websocket.str(@HTTP_200)
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.txmimeheader(@HTTP_HEADER_REFRESH,string("5;url=/"))        
        websocket.str(@CR_LF)
        subsys.irTest
        websocket.str(string("Status LED should now blink on IR activity.",13,10))
      elseif strcomp(@httpPath,string("/stage2"))
        websocket.str(@HTTP_VERSION)
        websocket.str(@HTTP_200)
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.txmimeheader(@HTTP_HEADER_REFRESH,string("12;url=/"))        
        websocket.str(@CR_LF)
        websocket.str(string("BOOTING STAGE 2",13,10))
        websocket.close
        pause.delay_ms(100)
        boot_stage2
      elseif strcomp(@httpPath,string("/login"))
        if authorized<>auth#STAT_AUTH
          httpUnauthorized(authorized)
          websocket.close                                                               
          next
        websocket.str(@HTTP_VERSION)
        websocket.str(@HTTP_303)
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.txmimeheader(@HTTP_HEADER_LOCATION,string("/"))        
        websocket.str(@CR_LF)
        websocket.str(@OK)
      elseif strcomp(@httpPath,string("/ledconfig"))
        if authorized<>auth#STAT_AUTH
          httpUnauthorized(authorized)
          websocket.close
          next
        websocket.str(@HTTP_VERSION)
        websocket.str(@HTTP_200)
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.str(@CR_LF)
        if base16.decode(@i,queryPtr,4)==4 AND LEDConfIsSane(i)
          settings.setLong(settings#MISC_LED_CONF,i)
          settings.commit
          websocket.str(string("LED Configuration changed. (NEEDS REBOOT)",13,10))
        else        
          websocket.str(string("Invalid LED Configuration.",13,10))
      elseif strcomp(@httpPath,string("/mute"))
        if authorized<>auth#STAT_AUTH
          httpUnauthorized(authorized)
          websocket.close
          next
        websocket.str(@HTTP_VERSION)
        websocket.str(@HTTP_303)
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.txmimeheader(@HTTP_HEADER_LOCATION,string("/"))        
        websocket.str(@CR_LF)
        case byte[queryPtr]
          "1": i~~
          "0": i~
          other: i:=NOT settings.findKey(settings#MISC_SOUND_DISABLE)
        if i
          settings.setByte(settings#MISC_SOUND_DISABLE,1)
          settings.commit
          websocket.str(string("MUTED",13,10))
          dira[subsys#SPKRPin]~
        else
          settings.removeKey(settings#MISC_SOUND_DISABLE)
          settings.commit
          websocket.str(string("UNMUTED",13,10))
          dira[subsys#SPKRPin]~~
        subsys.click
      elseif strcomp(@httpPath,string("/autoboot"))
        if authorized<>auth#STAT_AUTH
          httpUnauthorized(authorized)
          websocket.close
          next
        websocket.str(@HTTP_VERSION)
        websocket.str(@HTTP_303)
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.txmimeheader(@HTTP_HEADER_LOCATION,string("/"))        
        websocket.str(@CR_LF)
        if byte[queryPtr][0]=="1"
          settings.setByte(settings#MISC_AUTOBOOT,1)
          settings.commit
          websocket.str(string("ENABLED",13,10))
        else
          settings.removeKey(settings#MISC_AUTOBOOT)
          settings.commit
          websocket.str(string("DISABLED",13,10))
      elseif strcomp(@httpPath,@RAMIMAGE_EEPROM_FILE)
        if authorized<>auth#STAT_AUTH
          httpUnauthorized(authorized)
          websocket.close
          next
        websocket.str(@HTTP_VERSION)
        websocket.str(@HTTP_200)
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.txmimeheader(@HTTP_HEADER_CONTENT_TYPE,string("application/x-eeprom"))        
        websocket.txmimeheader(@HTTP_HEADER_CONTENT_DISPOS,string("attachment; filename=ramimage.eeprom"))        
        websocket.txmimeheader(@HTTP_HEADER_CONTENT_LENGTH,string("32768"))        
        websocket.str(@CR_LF)
        websocket.txdata(0,$8000)
      elseif strcomp(@httpPath,@FULL_EEPROM_FILE)
        if authorized<>auth#STAT_AUTH
          httpUnauthorized(authorized)
          websocket.close
          next
        sendFromEEPROM(@FULL_EEPROM_FILE+1,0,$10000{-settings#SettingsSize})
        
      elseif strcomp(@httpPath,@STAGE2_EEPROM_FILE)
        if authorized<>auth#STAT_AUTH
          httpUnauthorized(authorized)
          websocket.close
          next
        ifnot i:=settings.getLong(settings#MISC_STAGE2_SIZE)
          i:=$8000-settings#SettingsSize
        sendFromEEPROM(@STAGE2_EEPROM_FILE+1,$8000,i)
      elseif strcomp(@httpPath,@CONFIG_BIN_FILE)
        if authorized<>auth#STAT_AUTH
          httpUnauthorized(authorized)
          websocket.close
          next
        sendFromEEPROM(@CONFIG_BIN_FILE+1,$8000+settings#SettingsBottom,settings#SettingsSize)
      elseif strcomp(@httpPath,@CONFIG_PLIST_FILE)
        if authorized<>auth#STAT_AUTH
          httpUnauthorized(authorized)
          websocket.close
          next
        websocket.str(@HTTP_VERSION)
        websocket.str(@HTTP_200)
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.txmimeheader(@HTTP_HEADER_CONTENT_DISPOS,string("attachment; filename=config.plist"))        
        websocket.str(@CR_LF)
        configPList
      else           
        httpNotFound
    elseif strcomp(@httpMethod,string("PUT"))
      if authorized<>auth#STAT_AUTH
        httpUnauthorized(authorized)
        websocket.close
        next
      if not contentLength
        websocket.str(@HTTP_VERSION)
        websocket.str(@HTTP_411)
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.str(@CR_LF)
        websocket.str(@HTTP_411)
      elseif strcomp(@httpPath,@RAMIMAGE_EEPROM_FILE) OR strcomp(@httpPath,@CONFIG_BIN_FILE)
        websocket.str(@HTTP_VERSION)
        websocket.str(@HTTP_403)
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.str(@CR_LF)
        websocket.str(@HTTP_403)
      elseif strcomp(@httpPath,@STAGE2_EEPROM_FILE)
        bytefill(@buffer2,$F0,128)
        if (i:=\downloadFirmwareHTTP(contentLength))
          subsys.StatusFatalError
          subsys.chirpSad
          websocket.str(@HTTP_VERSION)
          websocket.str(@HTTP_400)
          websocket.str(@HTTP_CONNECTION_CLOSE)
          websocket.str(@CR_LF)
          websocket.str(string("Upload Failure",13,10))
          websocket.dec(i)         
          websocket.str(@CR_LF)
          repeat i from 0 to 127
            websocket.hex(buffer2[i],2)
            websocket.tx(" ")
        else
          if strcomp(queryPtr,string("boot")) OR stage_two
            websocket.str(@HTTP_VERSION)
            websocket.str(@HTTP_200)
            websocket.str(@HTTP_CONNECTION_CLOSE)
            websocket.txmimeheader(@HTTP_HEADER_REFRESH,string("12;url=/"))        
            websocket.str(@CR_LF)
            repeat i from 0 to md5#HASH_LENGTH-1
              websocket.hex(hash[i],2)
            websocket.tx(" ")
            websocket.str(@OK)
            websocket.close
            pause.delay_ms(100)
            if stage_two
              outa[0]~ ' Pull ethernet reset pin low, starting a reset condition.
              reboot
            else
              boot_stage2
          else
            websocket.str(@HTTP_VERSION)
            websocket.str(@HTTP_303)
            websocket.str(@HTTP_CONNECTION_CLOSE)
            websocket.txmimeheader(@HTTP_HEADER_LOCATION,string("/"))        
            websocket.str(@CR_LF)
            repeat i from 0 to md5#HASH_LENGTH-1
              websocket.hex(hash[i],2)
            websocket.tx(" ")
            websocket.str(@OK)
      else
        httpNotFound
    else
      websocket.str(@HTTP_VERSION)
      websocket.str(@HTTP_501)
      websocket.str(@HTTP_CONNECTION_CLOSE)
      websocket.str(@CR_LF)
      websocket.str(@HTTP_501)
    
    websocket.close
PUB sendFromEEPROM(filename,addr,len)| i
  websocket.str(@HTTP_VERSION)
  websocket.str(@HTTP_200)
  websocket.str(@HTTP_CONNECTION_CLOSE)
  websocket.txmimeheader(@HTTP_HEADER_CONTENT_TYPE,string("application/x-eeprom"))        
  websocket.str(@HTTP_HEADER_CONTENT_DISPOS)
  websocket.str(string(": attachment; filename="))
  websocket.str(filename)
  websocket.str(@CR_LF)        
  websocket.str(@HTTP_HEADER_CONTENT_LENGTH)
  websocket.str(string(": "))
  websocket.dec(len)
  websocket.str(@CR_LF)        
  websocket.str(@CR_LF)
  repeat i from 0 to len-1 step 128
    if \fast_eeprom.blockRead(@buffer, i+addr, 128)
      quit
    websocket.txData(@buffer,128)
   
pub infoPage | i
  websocket.str(string("ybox.version = '"))
  websocket.str(@productVersion)
  websocket.str(string("';",10))
  
  if settings.getData(settings#NET_MAC_ADDR,@httpMethod,6)
    websocket.str(string("ybox.macaddr = '"))
    repeat i from 0 to 5
      if i
        websocket.tx(":")
      websocket.hex(byte[@httpMethod][i],2)
    websocket.str(string("';",10))

  if settings.getData(settings#MISC_UUID,@httpQuery,16)
    websocket.str(string("ybox.uuid = '"))
    repeat i from 0 to 3
      websocket.hex(byte[@httpQuery][i],2)
    websocket.tx("-")
    repeat i from 4 to 5
      websocket.hex(byte[@httpQuery][i],2)
    websocket.tx("-")
    repeat i from 6 to 7
      websocket.hex(byte[@httpQuery][i],2)
    websocket.tx("-")
    repeat i from 8 to 9
      websocket.hex(byte[@httpQuery][i],2)
    websocket.tx("-")
    repeat i from 10 to 15
      websocket.hex(byte[@httpQuery][i],2)
    websocket.str(string("';",10))

  if settings.getData(settings#MISC_STAGE2_HASH,@httpQuery,md5#HASH_LENGTH)
    websocket.str(string("ybox.stage2.hash = '"))
    repeat i from 0 to md5#HASH_LENGTH-1
      websocket.hex(byte[@httpQuery][i],2)
    websocket.str(string("';",10))

  websocket.str(string("ybox.stage2.size = "))
  websocket.dec(settings.getLong(settings#MISC_STAGE2_SIZE))
  websocket.str(string(";",10))

    
  websocket.str(string("ybox.uptime = "))
  websocket.dec(subsys.RTC)
  websocket.str(string(";",10))
  websocket.str(string("ybox.ina = "))
  websocket.dec(ina)
  websocket.str(string(";",10))

PRI configPList | key,ptr,printable
'' Outputs all of the current settings as a property list
  key:=settings.firstKey
  websocket.str(string("{",10))
  repeat
    ifnot key
      quit
    if key==settings#MISC_STAGE2_SIZE
      next
    websocket.str(string("    "))
    websocket.dec(key)
    websocket.str(string(" = <"))
    repeat settings.getData(key,(ptr:=@buffer),128)
      websocket.hex(byte[ptr++],2)
    websocket.str(string(">;",10))

  while (key:=settings.nextKey(key))
  websocket.str(string("}",10))

pri httpOutputLink(url,class,content)
  websocket.str(string("<a href='"))
  websocket.strxml(url)
  if class
    websocket.str(string("' class='"))
    websocket.strxml(class)
  websocket.str(string("'><span>"))
  websocket.str(content)
  websocket.str(string("</span></a>"))


pub beginInfo
    websocket.str(string("<div><tt>"))
pub endInfo
    websocket.str(string("</tt></div>"))

pub beginForm(action,method)
  websocket.str(string("<form action='"))
  websocket.str(action)
  websocket.str(string("' method='"))
  websocket.str(method)
  websocket.str(string("'>"))
pub endForm
  websocket.str(string("</form>"))
pub addHiddenField(id,value)
  websocket.str(string("<input type='hidden' name='"))
  websocket.str(id)
  websocket.str(string("' id='"))
  websocket.str(id)
  websocket.str(string("' value='"))
  websocket.strxml(value)
  websocket.str(string("' />"))
pub addTextField(id,label,value,length)
  websocket.str(string("<div><label for='"))
  websocket.str(id)
  websocket.str(string("'>"))
  websocket.str(label)
  websocket.str(string(":</label><br /><input name='"))
  websocket.str(id)
  websocket.str(string("' id='"))
  websocket.str(id)
  websocket.str(string("' size='"))
  websocket.dec(length)
  websocket.str(string("' value='"))
  websocket.strxml(value)
  websocket.str(string("' /></div>"))
pub addIPField(id,label,value,length)
  websocket.str(string("<div><label for='"))
  websocket.str(id)
  websocket.str(string("'>"))
  websocket.str(label)
  websocket.str(string(":</label><br /><input name='"))
  websocket.str(id)
  websocket.str(string("' id='"))
  websocket.str(id)
  websocket.str(string("' value='"))
  websocket.txip(value)
  websocket.str(string("' /></div>"))
pub addPasswordField(id,label,value,length)
  websocket.str(string("<div><label for='"))
  websocket.str(id)
  websocket.str(string("'>"))
  websocket.str(label)
  websocket.str(string(":</label><br /><input type='password' name='"))
  websocket.str(id)
  websocket.str(string("' id='"))
  websocket.str(id)
  websocket.str(string("' size='"))
  websocket.dec(length)
  if value
    websocket.str(string("' value='"))
    websocket.strxml(value)
  websocket.str(string("' /></div>"))
pub addSubmitButton
  websocket.str(string("<input type='submit' />"))
  
pub indexPage(authorized) | i
  websocket.str(string("<html><head><meta name='viewport' content='width=320' />"))
  websocket.str(string("<title>ybox2 bootloader</title>"))
  websocket.str(string("<link rel='stylesheet' href='http://www.deepdarc.com/ybox2.css' />"))
 
  websocket.str(string("</head><body><h1>"))
  websocket.str(@productName)
  websocket.str(string("</h1>"))

  if stage_two
    websocket.str(string("<center><small>Bootloader Upgrade - Stage Two</small></center>"))

  if settings.getData(settings#NET_MAC_ADDR,@httpMethod,6)
    beginInfo
    websocket.str(string("MAC: "))
    repeat i from 0 to 5
      if i
        websocket.tx(":")
      websocket.hex(byte[@httpMethod][i],2)
    endInfo

  beginInfo
  websocket.str(string("Uptime: "))
  websocket.dec(subsys.RTC/3600)
  websocket.tx("h")
  websocket.dec(subsys.RTC/60//60)
  websocket.tx("m")
  websocket.dec(subsys.RTC//60)
  websocket.tx("s")
  endInfo
   
  ifnot stage_two
    beginInfo
    websocket.str(string("Autoboot: "))
    if settings.findKey(settings#MISC_AUTOBOOT)  
      websocket.str(string("<b>ON</b> "))
      if authorized
        httpOutputLink(string("/autoboot?0"),0,string("disable"))
    else
      websocket.str(string("<b>OFF</b> "))
      if authorized
        httpOutputLink(string("/autoboot?1"),0,string("enable"))
    endInfo
     
    beginInfo
    websocket.str(string("Password: "))
    if settings.findKey(settings#MISC_PASSWORD)
      websocket.str(string("SET"))  
    else
      websocket.str(string("NOT SET"))  
    endInfo
     
     
    if authorized
      beginForm(string("/password"),string("POST"))
      websocket.str(string("<div><small>Username is 'admin'.</small></div>"))
      addPasswordField(string("pwd1"),string("Password"),0,PASSWORD_MAX)
      addPasswordField(string("pwd2"),string("Password (Repeat)"),0,PASSWORD_MAX)
      addSubmitButton 
      endForm

    if authorized
      beginForm(string("/config"),string("POST"))
      websocket.str(string("DHCP:<br \> <input type='radio' name='dhcp' value='0'"))
      if (settings.getByte(settings#NET_DHCPv4_DISABLE))
        websocket.str(string(" checked "))
      websocket.str(string("> Disabled <input type='radio' name='dhcp' value='1' "))
      if (not settings.getByte(settings#NET_DHCPv4_DISABLE))
        websocket.str(string(" checked "))
      websocket.str(string("> Enabled<br \>"))
      settings.getData(settings#NET_IPv4_ADDR,@buffer,4)
      addIPField(string("addr"),string("IP"),@buffer,constant(3+3*4))
      settings.getData(settings#NET_IPv4_MASK,@buffer,4)
      addIPField(string("mask"),string("Subnet Mask"),@buffer,constant(3+3*4))
      settings.getData(settings#NET_IPv4_GATE,@buffer,4)
      addIPField(string("gate"),string("Gateway"),@buffer,constant(3+3*4))
      settings.getData(settings#NET_IPv4_DNS,@buffer,4)
      addIPField(string("dns1"),string("Domain Name Server"),@buffer,constant(3+3*4))
      addSubmitButton 
      endForm
       
  websocket.str(string("<h2>Actions</h2>"))
  websocket.str(string("<p>"))
  ifnot stage_two
    httpOutputLink(string("/stage2"),string("white button"),string("Boot stage 2"))
    websocket.str(string("</p><p>"))
    httpOutputLink(string("/irtest"),string("blue button"),string("IR Test Mode"))
    websocket.str(string("</p><p>"))
  httpOutputLink(string("/reboot"),string("black button"),string("Reboot"))
  if not authorized AND not stage_two
    websocket.str(string("</p><p>"))
    httpOutputLink(string("/login"),string("blackRight button"),string("Login"))
  websocket.str(string("</p>"))
   
   
  websocket.str(string("<h2>Files</h2>"))
  beginInfo
  httpOutputLink(@RAMIMAGE_EEPROM_FILE,0,@RAMIMAGE_EEPROM_FILE+1)
  websocket.tx(" ")
  httpOutputLink(@STAGE2_EEPROM_FILE,0,@STAGE2_EEPROM_FILE+1)
  websocket.tx(" ")
  httpOutputLink(@FULL_EEPROM_FILE,0,@FULL_EEPROM_FILE+1)
  websocket.tx(" ")
  httpOutputLink(@CONFIG_BIN_FILE,0,@CONFIG_BIN_FILE+1)
  websocket.tx(" ")
  httpOutputLink(@CONFIG_PLIST_FILE,0,@CONFIG_PLIST_FILE+1)
  endInfo
   
  websocket.str(string("<h2>Other</h2>"))
  beginInfo
  httpOutputLink(@productURL,0,@productURL)
  endInfo
  beginInfo
  httpOutputLink(@productURL2,0,@productURL2)
  endInfo

  websocket.str(string("</body></html>",13,10))

pub downloadFirmwareHTTP(contentLength) | timeout, retrydelay,in, i, total, addr,j, isFading
'  eeprom.Initialize(eeprom#BootPin)

  i~
  total~
  isFading~
  
  if stage_two
    addr~ ' Stage two writes to the lower 32KB
  else
    addr:=$8000 ' Stage one writes to the upper 32KB

  if contentLength > $8000-settings#SettingsSize
    contentLength:=$8000-settings#SettingsSize

  md5.hashStart(@hash)

  repeat
{
    if (in := websocket.rxdata(buffer+i,128-i)) > 0
      i+=in
}
    if (in := websocket.rxcheck) => 0
      buffer[i++] := in
      isFading~
      subsys.StatusSolid(0,255,0)
      if i == 128
        ' flush to EEPROM                              
        subsys.StatusSolid(0,0,255)

        if stage_two
          'Verify that the bytes we got match the EEPROM
          if fast_eeprom.blockRead(@buffer2,total+$8000, 128)
            abort -1
          repeat i from 0 to 127
            if buffer[i] <> buffer2[i]
              term.str(string(13,"Verify failed.",13))
              abort -2

          repeat i from 0 to 128-md5#BLOCK_LENGTH step md5#BLOCK_LENGTH
            md5.hashBlock(@buffer+i,@hash)
        else
          ' Wait for the previous write to be finished
          repeat while fast_eeprom.busy

          repeat while \fast_eeprom.blockWrite(@buffer,total+addr, 128)
          '  abort -3

          ' Calculate our hash while we wait
          repeat i from 0 to 128-md5#BLOCK_LENGTH step md5#BLOCK_LENGTH
            md5.hashBlock(@buffer+i,@hash)
            
          ' Wait for the write to be finished
          'repeat while fast_eeprom.busy
        total+=i
        i~
        bytefill(@buffer,0,128)
        
        term.out(".")
      if total => $8000-settings#SettingsSize
        websocket.close
    else
      ifnot isFading
        subsys.FadeToColor(255,0,0,500)
        isFading~~
      if websocket.isEOF OR (total+i) => contentLength
        md5.hashFinish(@buffer,i,total+i,@hash)

        if stage_two
          ' Do we have the correct number of bytes?
          if settings.findKey(settings#MISC_STAGE2_SIZE) AND ((total+i) <> settings.getWord(settings#MISC_STAGE2_SIZE))
            subsys.chirpSad
            term.out(13)
            term.dec((total+i) - settings.getWord(settings#MISC_STAGE2_SIZE))
            term.str(string(" byte diff!",13))
            abort -4                     

          'Verify that the bytes we got match the EEPROM
          if i
            if \fast_eeprom.blockRead(@buffer2,total+$8000, 128)
              abort -1
            repeat j from 0 to i-1
              if buffer[j] <> buffer2[j]
                term.str(string(13,"Verify failed: "))
                term.dec(buffer[j])
                term.out(" ")
                term.dec(buffer2[j])
                abort -5

          total+=i

          'If we got to this point, then everything matches! Write it out
          subsys.StatusLoading
          subsys.chirpHappy

          term.str(string(13,"Writing",13))

          repeat i from 0 to total-1 step 128
            repeat while fast_eeprom.busy
            repeat while \fast_eeprom.blockRead(@buffer,i+$8000, 128)
            '  abort -6
            repeat while \fast_eeprom.blockWrite(@buffer,i, 128)
            '  abort -7
            term.out(".")
          ' Now we need to fill in the rest of the image with zeros.
          bytefill(@buffer,0,128)
          repeat j from i to $8000-settings#SettingsSize step 128
            subsys.StatusSolid(0,0,128)
            repeat while fast_eeprom.busy
            repeat while \fast_eeprom.blockWrite(@buffer,j, 128)
            '  abort -9
            subsys.StatusSolid(0,128,0)
            term.out(".")
        else
          repeat while fast_eeprom.busy
          repeat while \fast_eeprom.blockWrite(@buffer,total+addr, 128)
          '  abort -8
          ' Now we need to fill in the rest of the image with zeros.
          bytefill(@buffer,0,128)
          repeat j from total+128 to $8000-settings#SettingsSize-1 step 128
            subsys.StatusSolid(0,0,128)
            repeat while fast_eeprom.busy
            repeat while \fast_eeprom.blockWrite( @buffer,j+addr, 128)
            '  abort -9
            subsys.StatusSolid(0,128,0)
            term.out(".")

          total+=i
        
        ' done!
        term.str(string("done.",13))
        term.dec(total)
        term.str(string(" bytes written",13))
        subsys.chirpHappy
        subsys.FadeToColor(0,255,0,200)
        settings.setWord(settings#MISC_STAGE2_SIZE,total)
        settings.setData(settings#MISC_STAGE2_HASH,@hash,md5#HASH_LENGTH)
        settings.commit
        return 0


  return 0

PUB showMessage(str)
  term.str(string($1,$B,12,$C,$1))    
  term.str(str)    
  term.str(string($C,$8))    
  