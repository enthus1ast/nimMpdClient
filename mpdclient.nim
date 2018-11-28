# Client for the musik player daemon
import asyncnet, asyncdispatch, strutils
import parseutils, times, tables 
#import locks
const bs = '\\'
type 
  MpdCmd* = enum
    cFind = "find"
    cSearch = "search"
    cAdd = "add"
    cAddid = "addid"
    cConsume = "consume"
    cCrossfade = "crossfade"
    cCurrentsong = "currentsong"
    cIdle = "idle"
    cNext = "next"
    cNoidle = "noidle"
    cPause = "pause"
    cPing = "ping"
    cPlay = "play"
    cPlayid = "playid"
    cPrevious = "previous"
    cRandom = "random"
    cRepeat = "repeat"
    cSeek = "seek"
    cSeekcur = "seekcur"
    cSeekid = "seekid"
    cSetvol = "setvol"
    cSingle = "single"
    cStats = "stats"
    cStatus = "status"
    cStop = "stop"
    cDelete = "delete"
    cDeleteid = "deleteid"

    cMove = "move"
    cMoveid = "moveid"
    #playlistfind
    #playlistid
    #playlistinfo
    #playlistsearch
    #plchanges
    #plchangesposid
    #prio
    #prioid
    #rangeid
    #shuffle
    #swap
    #swapid
    
  MpdSingle* = enum 
    singleFalse = "0"
    singleTrue = "1"
    singleOneshot = "oneshot"
  MpdVolume* = range[0..100]
  MpdPause* = enum
    pauseToggle = "0"
    pauseResume = "1"
  Songid* = int ## the id that gets returned when song is added
  Songpos* = int ## the position in the playlist
  MpdError* = enum
    ACK_ERROR_NOT_LIST = 1
    ACK_ERROR_ARG = 2
    ACK_ERROR_PASSWORD = 3
    ACK_ERROR_PERMISSION = 4
    ACK_ERROR_UNKNOWN = 5
    ACK_ERROR_NO_EXIST = 50
    ACK_ERROR_PLAYLIST_MAX = 51
    ACK_ERROR_SYSTEM = 52
    ACK_ERROR_PLAYLIST_LOAD = 53
    ACK_ERROR_UPDATE_ALREADY = 54
    ACK_ERROR_PLAYER_SYNC = 55
    ACK_ERROR_EXIST = 56
  EventHandler* = proc(client: MpdClient, event: AnswerLine): Future[void]
  AnswerLine* = tuple[key, val: string]
  AnswerLines* = seq[AnswerLine]
  Answer* = Table[string, string]
  MpdClient* = ref object
    host: string
    port: Port
    socketIdle: AsyncSocket
    socketCmd: AsyncSocket
    eventHandler: EventHandler
    lastCmdSent: float
    #sending: Lock
  #Filter* = string 

## filter mocup
# newFilter (file == "foo") and !(file contains "baa")

proc toMpdbool(val: bool): string =
  if val: "1"
  else: "0"

proc fromMpdbool(val: string): bool = 
  val == "1"

proc newAnswer(): Answer =
  return initTable[string, string]()

proc toTable(lines: AnswerLines): Answer = 
  ## converts the AnswerLines to a table
  result = initTable[string, string]()
  for line in lines:
    result[line.key.toLower()] = line.val

proc sendCmd*(client: MpdClient, cmd: string | MpdCmd): Future[void] {.async.} = 
  ## sends a command to the mpd server, does not wait for answer
  client.lastCmdSent = epochTime()
  await client.socketCmd.send($cmd & "\n")

proc request*(client: MpdClient, cmd: string | MpdCmd): Future[Answer] {.async.} =
  ## use this to send a cmd an also wait for response
  await client.sendCmd(cmd)
  return (await client.socketCmd.recvAnswer()).toTable()

proc newMpdClient*(): MpdClient = 
  result = MpdClient()

proc checkHeader(socket: AsyncSocket): Future[bool] {.async.} = 
  let line = await socket.recvLine()
  if line == "":
    raise newException(OsError, "disconnected in recvAnswer")
  return line.startswith("OK MPD")

proc splitLine(line: string): AnswerLine = 
  #echo "RAW: ", line
  let pos = line.parseUntil(result.key, ':', 0)
  result.val = line[pos+2..^1]

proc parseError(line: string): MpdError = 
  echo "TODO PARSE ERROR: " & line 

proc recvAnswer(socketCmd: AsyncSocket): Future[AnswerLines] {.async.} =
  result = @[]
  while true:
    let line = (await socketCmd.recvLine()).strip()
    if line == "": 
      raise newException(OsError, "disconnected in recvAnswer")
    if line == "OK": break
    elif line.startswith("ACK"):
      echo parseError(line) #TODO
      raise newException(ValueError, "mpd reported error: " & line)
    else: 
      result.add(line.splitLine)

proc pingServer(client: MpdClient, interval = 10.0) {.async.} =
  while true:
    var rest = epochTime() - client.lastCmdSent  
    echo rest
    if rest > interval.float:
      echo "ping server: ", rest 
      let lines = await client.request(cPing)
      if lines.len() != 0:
        echo "WARNING ping not OK! got: ", lines 
    await sleepAsync(15000)

proc currentSong*(client: MpdClient): Future[Answer] {.async.} = 
  ## Displays the song info of the current song (same song that is identified in status).
  let lines = await client.request(cCurrentsong)
  return lines

proc next*(client: MpdClient): Future[void] {.async.} = 
  ## Plays next song in the playlist.
  let lines = await client.request(cNext)

proc previous*(client: MpdClient): Future[void] {.async.} = 
  ## Plays previous song in the playlist.
  let lines = await client.request(cPrevious)

proc status*(client: MpdClient): Future[Answer] {.async.} = 
  ## Reports the current status of the player and the volume level. 
  let lines = await client.request(cStatus)
  return lines

proc stats*(client: MpdClient): Future[Answer] {.async.} = 
  ## Displays statistics. 
  let lines = await client.request(cStats)
  return lines

proc consume*(client: MpdClient, enabled: bool): Future[void] {.async.} = 
  ## Sets consume state to STATE, STATE should be 0 or 1. 
  ## When consume is activated, each song played is removed from playlist.  
  let lines = await client.request("$# $#" % [$cConsume, enabled.toMpdbool])

proc random*(client: MpdClient, enabled: bool): Future[void] {.async.} = 
  ## Sets random state to STATE, STATE should be 0 or 1
  let lines = await client.request("$# $#" % [$cRandom, enabled.toMpdbool])

proc repeat*(client: MpdClient, enabled: bool): Future[void] {.async.} = 
  ## Sets repeat state to STATE, STATE should be 0 or 1.
  let lines = await client.request("$# $#" % [$cRepeat, enabled.toMpdbool])

proc single*(client: MpdClient, val: MpdSingle): Future[void] {.async.} = 
  ## Sets single state to STATE, STATE should be 0, 1 or oneshot [5]. 
  ## When single is activated, playback is stopped after current song, 
  ## or song is repeated if the ‘repeat’ mode is enabled.  
  let lines = await client.request("$# $#" % [$cSingle, $val])

proc setvol*(client: MpdClient, volume: MpdVolume): Future[void] {.async.} = 
  ## Sets volume to VOL, the range of volume is 0-100.
  let lines = await client.request("$# $#" % [$cSetvol, $volume])

proc crossfade*(client: MpdClient, val: int): Future[void] {.async.} = 
  ## Sets crossfading between songs.
  let lines = await client.request("$# $#" % [$cCrossfade, $val])

proc pause*(client: MpdClient, val = pauseToggle): Future[void] {.async.} = 
  ## Toggles pause/resumes playing, PAUSE is 0 or 1.
  let lines = await client.request("$# $#" % [$cPause, $val])

proc stop*(client: MpdClient): Future[void] {.async.} = 
  ## Stops playing.
  let lines = await client.request("$#"  % [$cStop])

proc play*(client: MpdClient, songpos: int): Future[void] {.async.} = 
  ## Begins playing the playlist at song number SONGPOS.
  let lines = await client.request("$# $#" % [$cPlay, $songpos])

proc playid*(client: MpdClient, songid: Songid): Future[void] {.async.} = 
  ## Begins playing the playlist at song SONGID. 
  let lines = await client.request("$# $#" % [$cPlayid, $songid])

proc seek*(client: MpdClient, songpos, time: int): Future[void] {.async.} = 
  ## Seeks to the position TIME (in seconds; fractions allowed) of entry SONGPOS in the playlist.
  let lines = await client.request("$# $# $#" % [$cSeek, $songpos, $time])

proc seekid*(client: MpdClient, songid: Songid, time: int): Future[void] {.async.} = 
  ## Seeks to the position TIME (in seconds; fractions allowed) of song SONGID.  
  let lines = await client.request("$# $# $#" % [$cSeekid, $songid, $time])

proc seekcur*(client: MpdClient, time: int): Future[void] {.async.} = 
  ## Seeks to the position TIME (in seconds; fractions allowed) 
  ## within the current song. If prefixed by + or -, 
  ## then the time is relative to the current playing position.  
  let lines = await client.request("$# $#" % [$cSeekcur, $time])

proc add*(client: MpdClient, uri: string): Future[void] {.async.} = 
  ## Adds the file URI to the playlist (directories add recursively). URI can also be a single file. 
  let lines = await client.request("$# $#"% [$cAdd, uri])

proc addid*(client: MpdClient, uri: string): Future[Songid] {.async.} = 
  ## Adds a song to the playlist (non-recursive) and returns the song id. 
  ## URI is always a single file or URL.
  let lines = await client.request("$# $#" % [$cAddid, uri])
  if lines.len <= 0: return
  let tab = lines
  if not tab.hasKey("id"): return
  return tab["id"].parseInt

proc delete*(client: MpdClient, pos: Songpos): Future[Songid] {.async.} = 
  let lines = await client.request("$# $#" % [$cDelete, $pos])

proc deleteid*(client: MpdClient, pos: Songid): Future[Songid] {.async.} = 
  let lines = await client.request("$# $#" % [$cDeleteid, $pos])

#proc delete*(client: MpdClient, pos: Songpos): Future[Songid] {.async.} = 
#  await client.sendCmd("$# $#" % [$cDelete, $pos])
#  let lines = await client.socketCmd.recvAnswer()
#proc delete*(client: MpdClient, posRange: range[Songpos]): Future[Songid] {.async.} = discard 

proc splitFiles(lines: AnswerLines): seq[Answer] =
  ## converts the concatenated file list to a seq of answers
  result = @[]
  var cur: Answer = newAnswer()
  for line in lines:
    if line.key == "file":
      cur[line.key] = line.val
      if cur.hasKey("file"): 
        result.add cur
      cur = newAnswer()
    cur[line.key] = line.val
  result.add cur

proc dispatchEvents*(client: MpdClient) {.async.} =
  ## calls the event handler
  echo "SET IDLE MODE"
  while true:
    var lines = await client.socketIdle.recvAnswer()
    echo "LINES: ", lines
    for line in lines:
      await client.eventHandler(client, line)
    await client.socketIdle.send($cIdle & "\n")

proc connect*(client: MpdClient, host: string, port: Port, eventHandler: EventHandler): Future[bool] {.async.} =
  client.host = host
  client.port = port
  client.eventHandler = eventHandler
  client.socketCmd = await asyncnet.dial(host, port)
  if (await client.socketCmd.checkHeader()) == false:
    echo "Could not connect to cmd socketCmd"
    if not client.socketCmd.isClosed():
      client.socketCmd.close()
    return false
  client.lastCmdSent = epochTime() 
  client.socketIdle = await asyncnet.dial(host, port)
  if (await client.socketIdle.checkHeader()) == false:
    echo "Could not connect to cmd socketIdle"
    if not client.socketIdle.isClosed():
      client.socketIdle.close()
    return false
  await client.socketIdle.send($cIdle & "\n")
  return true

proc escape(str: string): string = 
  for ch in str:
    case ch
    of bs:
      result.add bs & bs
    of '"':
      result.add bs & '"'
    of '\'':
      result.add bs & '\''
    else:
      result.add ch

proc quote*(str: string): string = 
  ## quotes special chars for sending to mpd
  result = ""
  result.add "\""
  result.add str.escape()
  result.add "\""

proc search*(client: MpdClient, filter: string): Future[void] {.async.} = 
  ## the low level version of search, user must supply the filter as a string
  await client.sendCmd("$# $#" % [$cSearch, $filter]) # cannot use request here
  let lines = await client.socketCmd.recvAnswer()
  var files = lines.splitFiles()
  #echo files
  for f in files:
    echo f["file"]

when isMainModule:
#  assert quote("""foo'bar"""") == """foo\'bar\""""
  assert escape("foo") == "foo"
  assert escape("foo's") == "foo" & bs & "'s"
  assert escape(bs & bs) == bs & bs & bs & bs
  #assert escape('\'' & bs) == bs & bs & bs & bs
  #assert quote(""""'\""") == """"\"'\\""""
  #assert quote  r"\\"" == r""\\\\\"""  # \\"   ->  
  assert quote("foo") == "\"foo\""
  assert quote("foo's") == "\"foo" & bs & "'s\""

when isMainModule:
  import random as rnd
  proc main() {.async.} =   
    proc echoEvHandler(client: MpdClient, event: AnswerLine) {.async.} =
      # dummy handler
      echo "EVENT: ", event
      case event.val
      of "playlist":
        echo "Playlist changed:"
        echo await client.currentSong()
      of "options":
        echo "Options changed:"
        echo await client.status()

    var client = newMpdClient()
    if await client.connect("192.168.2.167", 6600.Port, echoEvHandler):
      echo "Connected"
      asyncCheck client.dispatchEvents()
      asyncCheck client.pingServer() # This could maybe deadlock the cmd socket??
      await client.search("artist tool")
      while true:
        let current = await client.currentSong()
        #await client.nextSong()
        await client.stop()
        echo await client.stats()
        echo await client.status()
        try:
          await client.setvol(100)
        except:
          discard
        #await client.setvol(rand(100))
        echo current
        await sleepAsync(5200)
    else:
      echo "could not connect"
  waitFor main()

