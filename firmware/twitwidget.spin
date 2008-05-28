{{
        ybox2 - Info Widget
        http://www.deepdarc.com/ybox2

        ABOUT

        This simple (!?) program will poll a webpage for information
        and display it on your TV screen, updating in 30 second
        intervals. You can configure where it gets the data
        by connecting to the device with a web browser and
        changing the settings. By default it will grab weather
        data from the 95008 zip code, which you can change
        using any web browser.

        If a password was set in the bootloader, it will be
        required to change the settings.
}}
CON

  _clkmode = xtal1 + pll16x
  _xinfreq = 5_000_000                                                      

  NO_TWEET = 0
  FIRST_TWEET = 1
  TWEETING = 2
  
OBJ

  websocket     : "api_telnet_serial"
  term          : "TV_Text"
  subsys        : "subsys"
  settings      : "settings"
  http          : "http"
  auth          : "auth_digest"
  tel           : "api_telnet_serial"
  random        : "RealRandom"
                                     
VAR
  byte path_holder[64]
  byte tv_mode

  ' Statistics
  long stat_refreshes
  long stat_errors

  long weatherstack[200]

  byte tweet[160]
  byte stringbuffer[256]
  long laststatus
    
DAT
productName   BYTE      "ybox2 twitter widget",0      
productURL    BYTE      "http://www.ladyada.net/make/ybox2/",0
footer         BYTE     $1, $C,6,"                               YTwitter",0
info_refresh_period   long    30  ' in seconds

palette                 byte    $07,   $B2    '0    white / dark blue
                        byte    $9E,   $B2    '1    yellow / black
                        byte    $3D,   $B2    '2   yellow / brown
                        byte    $04,   $07    '3     grey / white
                        byte    $3D,   $3B    '4     cyan / dark cyan
                        byte    $6B,   $6E    '5    green / gray-green
                        byte    $BB,   $CE    '6      black, white
                        byte    $9E,   $B2    '7     red, black

    
PUB init | i
  dira[0]:=1 ' Set direction on reset pin
  outa[0]:=0 ' Set state on reset pin to LOW
  dira[subsys#SPKRPin]:=1

  stat_refreshes:=0
  stat_errors:=0


  ' Default to NTSC
  tv_mode:=term#MODE_NTSC
  
  settings.start
  subsys.init

  'initial_configuration
  
  ' If there is a TV mode preference in the EEPROM, load it up.
  if settings.findKey(settings#MISC_TV_MODE)
    tv_mode := settings.getByte(settings#MISC_TV_MODE)
    
  ' Start the TV Terminal
  term.startWithMode(12,tv_mode)
  term.setcolors(@palette) 
  term.str(string($0C,7))
  term.str(@productName)
  term.out(13)
  term.str(@productURL)
  term.out(13)
  term.out($0c)
  term.out(2)
  repeat term#cols
    term.out($90)
  term.out($0c)
  term.out(0)

  subsys.StatusLoading

  ' Init the auth object with some randomness
  random.start
  auth.init(random.random)
  random.stop

  if settings.findKey(settings#MISC_STAGE2)
    settings.removeKey(settings#MISC_STAGE2)

  'ir.init(15, 0, 300, 1)
         
  if settings.findKey(settings#MISC_SOUND_DISABLE) == FALSE
    dira[subsys#SPKRPin]:=1
  else
    dira[subsys#SPKRPin]:=0

  if NOT settings.findKey(settings#SERVER_PATH)
    if NOT \initial_configuration
      showMessage(string("Server configuration failed!"))
      subsys.StatusFatalError
      SadChirp
      waitcnt(clkfreq*100000 + cnt)
      reboot
  
  outa[0]:=1 ' Pull ethernet reset pin high, ending the reset condition.
  if not \tel.start(1,2,3,4,6,7,-1,-1)
    showMessage(string("Unable to start networking!"))
    subsys.StatusFatalError
    SadChirp
    waitcnt(clkfreq*10000 + cnt)
    reboot

  if settings.getData(settings#NET_MAC_ADDR,@weatherstack,6)
    term.str(string("MAC: "))
    repeat i from 0 to 5
      if i
        term.out("-")
      term.hex(byte[@weatherstack][i],2)
    term.out(13)  

  if NOT settings.getData(settings#NET_IPv4_ADDR,@weatherstack,4)
    term.str(string("IPv4 ADDR: DHCP..."))
    repeat while NOT settings.getData(settings#NET_IPv4_ADDR,@weatherstack,4)
      if ina[subsys#BTTNPin]
        reboot
      delay_ms(500)
  term.out($0A)
  term.out($00)  
  term.str(string("IPv4 ADDR: "))
  repeat i from 0 to 3
    if i
      term.out(".")
    term.dec(byte[@weatherstack][i])
  term.out(13)  


  if settings.getData(settings#NET_IPv4_DNS,@weatherstack,4)
    term.str(string("DNS ADDR: "))
    repeat i from 0 to 3
      if i
        term.out(".")
      term.dec(byte[@weatherstack][i])
    term.out(13)  

  if settings.getData(settings#SERVER_IPv4_ADDR,@weatherstack,4)
    term.str(string("SERVER ADDR:"))
    repeat i from 0 to 3
      if i
        term.out(".")
      term.dec(byte[@weatherstack][i])
    term.out(":")  
    term.dec(settings.getWord(settings#SERVER_IPv4_PORT))
    term.out(13)  

  if settings.getString(settings#SERVER_PATH,@weatherstack,40)
    term.str(string("SERVER PATH:'"))
    term.str(@weatherstack)
    term.str(string("'",13))

  if settings.getString(settings#SERVER_HOST,@weatherstack,40)
    term.str(string("SERVER HOST:'"))
    term.str(@weatherstack)
    term.str(string("'",13))
   
  
  cognew(WeatherCog, @weatherstack) 

  repeat
    HappyChirp
    i:=\httpServer
    term.out("[")
    term.dec(i)
    term.out("]")
     
    subsys.StatusFatalError
    SadChirp
    delay_ms(500)
    websocket.closeAll
  reboot

PUB strstrn(haystack, needle, len) | i, j   ' finds needle string in haystack string, up to len bytes long
   i := 0         ' string incrementer
   j := 0        ' substring incrementer
   RESULT := -1     ' our success (-1 not found, otherwise index of substr
   repeat i from 0 to len
      if BYTE[haystack][i] == 0      ' haystack over
         quit
      if (BYTE[haystack][i] == BYTE[needle][0])        ' start substr compare
         j := 0

         repeat while (j < strsize(needle))
           if ((i+j) => len)
              quit
           if BYTE[haystack][i+j] <> BYTE[needle][j]
              quit
           j++
         if j == strsize(needle)
            RESULT := i     ' success!
            return 

PRI initial_configuration

  settings.setString(settings#SERVER_HOST,string("twitter.com"))  
  settings.setData(settings#SERVER_IPv4_ADDR,string(128,121,146,100),4)
  settings.setWord(settings#SERVER_IPv4_PORT,80)
  settings.setString(settings#SERVER_PATH,string("/ladyada"))
  return TRUE
     

CON
  WEATHER_SUCCESS = 860276
pub WeatherCog | retrydelay,port,err
  port := 20000
  retrydelay := 1 ' Reset the retry delay

  laststatus := 0  ' only update on new twitter update statuses
  
  repeat
    subsys.StatusLoading
    if (err:=\WeatherUpdate(port)) == WEATHER_SUCCESS
      retrydelay := 1 ' Reset the retry delay
      subsys.StatusIdle
      'term.str(string($B,12))    
      'term.dec(subsys.RTC) ' Print out the RTC value
      'term.out(" ")
      tel.close
      delay_s(info_refresh_period)     ' 30 sec delay
    else
      if err>0
        subsys.StatusErrorCode(err)
      stat_errors++
      showMessage(string("Error!"))
      term.dec(err)    
      tel.closeall
      websocket.closeall
      if retrydelay < 15
         retrydelay+=retrydelay
      delay_s(retrydelay)             ' failed to connect     
    if ++port > 30000
      port := 20000
       

pub WeatherUpdate(port) | timeout, addr, gotstart,in,i,header[4],value[4], idx, stringptr, TMP, status, state, tweetptr, j
  if settings.getString(settings#SERVER_PATH,@path_holder,64)=<0
    abort 5
   
  addr := settings.getLong(settings#SERVER_IPv4_ADDR)
  if tel.connect(@addr,settings.getWord(settings#SERVER_IPv4_PORT),port) == -1
    abort 6
   
  'term.str(string($1,$A,39,$C,1," ",$C,$8,$1,$B))
  'term.out(0)
   
  tel.waitConnectTimeout(2000)
   
  ifnot tel.isEOF   
    'term.str(string($1,$B,12,"                                       "))
    'term.str(string($1,$A,39,$C,$8," ",$1))
    
    tel.str(string("GET "))      
    tel.str(@path_holder)
    tel.str(string(" HTTP/1.0",13,10))       ' use HTTP/1.0, since we don't support chunked encoding
    
    if settings.getString(settings#SERVER_HOST,@path_holder,64)
      tel.txmimeheader(string("Host"),@path_holder)
   
    tel.txmimeheader(string("User-Agent"),string("PropTCP"))
    tel.txmimeheader(string("Connection"),string("close"))
    tel.str(@CR_LF)
   
    repeat while \http.getNextHeader(tel.handle,@header,16,@value,16)>0
      if strcomp(string("Refresh"),@header)
        info_refresh_period:=atoi(@value)
        if info_refresh_period < 4
          info_refresh_period:=4 ' Four second minimum refresh  
        
    timeout := cnt 
    i:=0
    idx := 0
    tweetptr := @tweet
    status := 0
  
    repeat
      if (in := \tel.rxcheck) > 0
        timeout := cnt              ' set the timeout from -last- byte
        if in <> 10
          '\term.out(in)
          stringbuffer[idx] := in
          idx++
          i++
        else
          stringbuffer[idx] := 0
          'term.str(@stringbuffer)
          idx := 0
        
          stringptr := @stringbuffer

          ' get the status #
          TMP := strstrn(stringptr, string("<div id=",34,"status_actions_"), 256)
          if ((TMP <> -1) and (status == NO_TWEET))
             status := atoi(stringptr + TMP + 24)
             'term.dec(status)

             if (status > laststatus)
                ' a new update!
                laststatus := status


                term.out(0)
                term.str(@footer)
                settings.getData(settings#NET_IPv4_ADDR, @path_holder,4)
                term.out($0A)
                term.out($00)
                repeat i from 0 to 3
                  if i
                    term.out(".")
                  term.dec(byte[@path_holder][i])
                term.str(string($B, 13))

                ' print out last twitter we parsed out
                term.str(string($C, 2))
                settings.getString(settings#SERVER_PATH,@path_holder,64)
                if ((term.getrow + (strsize(@path_holder)+2 + strsize(tweetptr))/term#cols) => (term#rows - 1))
                  return WEATHER_SUCCESS
                term.out(13)
             
                term.str(@path_holder+1)
                term.str(string(": ", $C))
                term.out(0)
                tweetptr := cleantweet(@tweet)
                term.str(tweetptr)
                tweetptr := @tweet 
                state := NO_TWEET
             else
                return WEATHER_SUCCESS 
          ' special exception, for the very first tweet
          TMP := strstrn(stringptr, string("<p class=",34,"entry-title entry-content",34,">"), 256)
          if (TMP <> -1)
              stringptr := @stringbuffer + TMP + 37                ' point to the beginning
              TMP := strstrn(stringptr, string("</p>"), 256)       ' find the end
              if (TMP == -1)
                j := strsize(stringptr)
                if ((tweetptr + j) > (@tweet + 160))
                  term.str(string("too long!"))
                  state := NO_TWEET
                  next
                bytemove(tweetptr, stringptr, j)
                tweetptr += j
                byte[tweetptr][0] := 0
                term.str(@tweet)
                   
                state := FIRST_TWEET
                next
              tweetptr := @tweet
              bytemove(tweetptr, stringptr, TMP)                     ' copy it over
              byte[tweetptr][TMP] := 0
              
              tweetptr := cleantweet(@tweet)

              
          ' check for end of first tweet
          TMP := strstrn(stringptr, string("</p>"), 256)
          if ((TMP <> -1) and (state == FIRST_TWEET))
             j := TMP
             if ((tweetptr + j) > (@tweet + 160))
               state := NO_TWEET
               next
             bytemove(tweetptr, stringptr, j)
             tweetptr += j
             byte[tweetptr][0] := 0
             state := NO_TWEET
             
          ' check for the beginning of a tweet
          TMP :=  strstrn(stringptr, string("<span class=",34,"entry-content",34,">"), 256)
          if (TMP <> -1)                                                                          
             ' TMP is the starting index
             stringptr := @stringbuffer + TMP + 28
             ' now stringptr points to the start
             j := strsize(stringptr)      
             'term.str(string(13,"START:"))
             'term.str(stringptr)
             'term.dec(j)
             tweetptr := @tweet
             if ((tweetptr + j) > (@tweet + 160))
               state := NO_TWEET
               next
             bytemove(tweetptr, stringptr, j)
             tweetptr += j
             byte[tweetptr][0] := 0
             'term.str(@tweet)            
             
             state := TWEETING
             next       ' repeat loop
   
          ' check for the end of a tweet   
          TMP :=  strstrn(stringptr, string("</span>"), 256)
          if ((TMP <> -1) and (state == TWEETING))
             ' TMP is the starting index
             j := TMP

             'term.str(string(13,"END:"))      
             'term.str(stringptr)
             'term.dec(j)
             if ((tweetptr + j) > (@tweet + 160))
               state := NO_TWEET
               next
             bytemove(tweetptr, stringptr, j)
             tweetptr += j
             byte[tweetptr][0] := 0

             tweetptr := cleantweet(@tweet)

             term.str(string($C, 2))
             settings.getString(settings#SERVER_PATH,@path_holder,64)
             if ((term.getrow + (strsize(@path_holder)+2 + strsize(tweetptr))/term#cols) => (term#rows - 1))
                return WEATHER_SUCCESS
             term.out(13)
             
             term.str(@path_holder+1)
             term.str(string(": ", $C))
             term.out(0)
             term.str(tweetptr)
             tweetptr := @tweet 
             state := NO_TWEET
             
             next        ' repeat loop

          ' check for the middle of a tweet
          if ((state == TWEETING) or (state == FIRST_TWEET))
             j := strsize(stringptr)
             'term.str(string(13,"MID:"))
             'term.str(stringptr)
             'term.dec(j)
             if ((tweetptr + j) > (@tweet + 160))
               state := NO_TWEET
               next
             bytemove(tweetptr, stringptr, j)
             tweetptr += j
             byte[tweetptr][0] := 0
             'term.str(@tweet)
              
             next
      else
        ifnot tel.isConnected
          if i > 1
            stat_refreshes++
            return WEATHER_SUCCESS
          abort 4
        if ( (cnt-timeout) > (subsys#DISCONNECTTIMEOUT*clkfreq)) ' ~10 second timeout      
          abort(subsys#ERR_DISCONNECTED)
  else
    abort(subsys#ERR_NO_CONNECT)
  return 5
     
PUB showMessage(str)
  term.str(string($1,$B,12,$C,$1))    
  term.str(str)    
  term.str(string($C,$8))    

pub HappyChirp
  subsys.chirpHappy
pub SadChirp
  subsys.chirpSad
    
PRI delay_ms(Duration)
  waitcnt(((clkfreq / 1_000 * Duration - 3932)) + cnt)
PRI delay_s(Duration)
  repeat Duration
    delay_ms(1000)  
VAR
  byte httpMethod[8]
  byte httpPath[128]
  byte httpHeader[32]
  byte buffer[128]
  byte buffer2[128]
DAT
HTTP_200      BYTE      "HTTP/1.1 200 OK"
CR_LF         BYTE      13,10,0
HTTP_303      BYTE      "HTTP/1.1 303 See Other",13,10,0
HTTP_404      BYTE      "HTTP/1.1 404 Not Found",13,10,0
HTTP_403      BYTE      "HTTP/1.1 403 Forbidden",13,10,0
HTTP_401      BYTE      "HTTP/1.1 401 Authorization Required",13,10,0
HTTP_411      BYTE      "HTTP/1.1 411 Length Required",13,10,0
HTTP_501      BYTE      "HTTP/1.1 501 Not Implemented",13,10,0

HTTP_HEADER_SEP     BYTE ": ",0
HTTP_HEADER_CONTENT_TYPE BYTE "Content-Type",0
HTTP_HEADER_LOCATION     BYTE "Location",0
HTTP_HEADER_CONTENT_DISPOS     BYTE "Content-disposition",0
HTTP_HEADER_CONTENT_LENGTH     BYTE "Content-Length",0

HTTP_CONTENT_TYPE_HTML  BYTE "text/html; charset=utf-8",0
HTTP_CONNECTION_CLOSE   BYTE "Connection: close",13,10,0



pri httpUnauthorized(authorized)
  websocket.str(@HTTP_401)
  websocket.str(@HTTP_CONNECTION_CLOSE)
  auth.generateChallenge(@buffer,127,authorized)
  websocket.txMimeHeader(string("WWW-Authenticate"),@buffer)
  websocket.str(@CR_LF)
  websocket.str(@HTTP_401)

pri httpNotFound
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
      
PRI cleantweet(strptr) : retptr | tmp, tmp2
  repeat while BYTE[strptr] AND (BYTE[strptr]==" " OR BYTE[strptr] == 09)
    strptr++
  retptr := strptr

  repeat
    strptr := retptr
    ' search for URL 'hrefs' and delete them
    tmp := strstrn(strptr, string("<a href"), 256)
    if (tmp <> -1)
      tmp2 := strstrn(strptr+tmp, string(34,">"), 256)
      if (tmp2 <> -1)
        bytemove(strptr+tmp, strptr+tmp+tmp2+2, strsize(strptr+tmp+tmp2)-1)
    else
       quit

  repeat
    strptr := retptr
    ' search for URL </a>'s and delete them
    tmp := strstrn(strptr, string("</a>"), 256)
    if (tmp <> -1)
       byte[strptr+tmp] := " "
       bytemove(strptr+tmp+1, strptr+tmp+4, strsize(strptr+tmp)-2)
    else
       quit

  strptr := retptr
    ' go to end
  repeat while BYTE[strptr]
    strptr++
  ' at the end now
  strptr--
  repeat while BYTE[strptr] AND (BYTE[strptr]==" " OR BYTE[strptr] == 09 OR BYTE[strptr] == 13)
    BYTE[strptr] := 0
    strptr--     
  return retptr

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

pub httpServer | i, contentLength,authorized,queryPtr
  repeat
    repeat while websocket.listen(80) < 0
      if ina[subsys#BTTNPin]
        reboot
      delay_ms(1000)
      websocket.closeall
      next
    
    repeat while NOT websocket.waitConnectTimeout(100)
      if ina[subsys#BTTNPin]
        reboot

    ' If there isn't a password set, then we are by default "authorized"
    authorized:=NOT settings.findKey(settings#MISC_PASSWORD)
    contentLength:=0

    if \http.parseRequest(websocket.handle,@httpMethod,@httpPath,$8000)<0
      websocket.close
      next
        
    repeat while \http.getNextHeader(websocket.handle,@httpHeader,32,@buffer,128)>0
      if strcomp(@httpHeader,@HTTP_HEADER_CONTENT_LENGTH)
        contentLength:=atoi(@buffer)
      elseif NOT authorized AND strcomp(@httpHeader,string("Authorization"))
        authorized:=auth.authenticateResponse(@buffer,@httpMethod,@httpPath)

    ' Authorization check
    ' You can comment this out if you want to
    ' be able to let unauthorized people see the
    ' front page. Even if you uncomment this,
    ' unauthorized users won't be able to
    ' change the settings or reboot, due to
    ' redundant checks below.
    if authorized<>auth#STAT_AUTH
      httpUnauthorized(authorized)
      websocket.close
      next
             
    queryPtr:=http.splitPathAndQuery(@httpPath)
    if strcomp(@httpMethod,string("GET")) or strcomp(@httpMethod,string("POST"))
      if strcomp(@httpPath,string("/"))
        websocket.str(@HTTP_200)
        websocket.txmimeheader(@HTTP_HEADER_CONTENT_TYPE,@HTTP_CONTENT_TYPE_HTML)        
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.str(@CR_LF)

        websocket.str(string("<html><head><meta name='viewport' content='width=320' /><title>ybox2</title>"))
        websocket.str(string("<link rel='stylesheet' href='http://www.deepdarc.com/ybox2.css' />"))
 
        websocket.str(string("</head><body><h1>"))
        websocket.str(@productName)
        websocket.str(string("</h1>"))

        if settings.getData(settings#NET_MAC_ADDR,@httpMethod,6)
          websocket.str(string("<div><tt>MAC: "))
          repeat i from 0 to 5
            if i
              websocket.tx("-")
            websocket.hex(byte[@httpMethod][i],2)
          websocket.str(string("</tt></div>"))

        websocket.str(string("<div><tt>Uptime: "))
        websocket.dec(subsys.RTC/60)
        websocket.tx("m")
        websocket.dec(subsys.RTC//60)
        websocket.tx("s")
        websocket.str(string("</tt></div>"))
        websocket.str(string("<div><tt>Refreshes: "))
        websocket.dec(stat_refreshes)
        websocket.str(string("</tt></div>"))        
        websocket.str(string("<div><tt>Errors: "))
        websocket.dec(stat_errors)
        websocket.str(string("</tt></div>"))
        websocket.str(string("<div><tt>Refresh Period: "))
        websocket.dec(info_refresh_period)
        websocket.str(string("s</tt></div>"))
        websocket.str(string("<div><tt>INA: "))
        repeat i from 0 to 7
          websocket.dec(ina[i])
        websocket.tx(" ")
        repeat i from 8 to 15
          websocket.dec(ina[i])
        websocket.tx(" ")
        repeat i from 16 to 23
          websocket.dec(ina[i])
        websocket.tx(" ")
        repeat i from 23 to 31
          websocket.dec(ina[i])          
        websocket.str(string("</tt></div>"))

        websocket.str(string("<h2>Settings</h2>"))
        websocket.str(string("<form action='/config' method='POST'>"))
        settings.getString(settings#SERVER_HOST,@httpPath,32)
        addTextField(string("SH"),string("Twitter Host"),@httpPath,32)
        settings.getString(settings#SERVER_Path,@httpPath,32)
        addTextField(string("SP"),string("Twitter User"),@httpPath,32)

        websocket.str(string("<label for='SA'>Server Address</label><br /><input name='SA' id='SA' size='32' value='"))
        settings.getData(settings#SERVER_IPv4_ADDR,@httpPath,32)
        websocket.txip(@httpPath)
        websocket.str(string("' /><br />"))

        websocket.str(string("<input name='submit' type='submit' />"))
        websocket.str(string("</form>"))
        
        
        websocket.str(string("<h2>Actions</h2>"))
        websocket.str(string("<div><a href='/reboot'>Reboot</a></div>"))
        websocket.str(string("<h2>Other</h2>"))
        websocket.str(string("<div><a href='"))
        websocket.str(@productURL)
        websocket.str(string("'>More info</a></div>"))

        websocket.str(string("</body></html>",13,10))
        
      elseif strcomp(@httpPath,string("/config"))
        if authorized<>auth#STAT_AUTH
          httpUnauthorized(authorized)
          websocket.close
          next

        if contentLength
          i:=0
          repeat while contentLength AND i<127
            httpPath[i++]:=websocket.rxtime(1000)
            contentLength--
          httpPath[i]~
          queryPtr:=@httpPath
          
        if http.getFieldFromQuery(queryPtr,string("SH"),@buffer,127)
          settings.setString(settings#SERVER_HOST,@buffer)  
        if http.getFieldFromQuery(queryPtr,string("SP"),@buffer,127)
          settings.setString(settings#SERVER_PATH,@buffer)  

        if http.getFieldFromQuery(queryPtr,string("SA"),@buffer,127)
          parseIPStr(@buffer,@buffer2)
          settings.setData(settings#SERVER_IPv4_ADDR,@buffer2,4)  
        
        settings.removeKey($1010)
        settings.removeKey(settings#MISC_STAGE2)
        settings.commit
        
        websocket.str(@HTTP_303)
        websocket.txmimeheader(@HTTP_HEADER_LOCATION,string("/"))        
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.str(@CR_LF)
        websocket.str(string("OK",13,10))

      elseif strcomp(@httpPath,string("/reboot"))
        if authorized<>auth#STAT_AUTH
          httpUnauthorized(authorized)
          websocket.close
          next
        websocket.str(@HTTP_200)
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.str(@CR_LF)
        websocket.str(string("REBOOTING",13,10))
        websocket.close
        reboot
      else           
        httpNotFound
    else
        websocket.str(@HTTP_501)
        websocket.str(@HTTP_CONNECTION_CLOSE)
        websocket.str(@CR_LF)
        websocket.str(@HTTP_501)
    
    websocket.close
 