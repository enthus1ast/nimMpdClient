# Client for the musik player deamon
import asyncnet, asyncdispatch, strutils, parseutils, times, tables

type 
  MpdCmd* = enum
    cIdle = "idle"
    cNoidle = "noidle"
    cPing = "ping"
    cCurrentsong = "currentsong"
    cNext = "next"
    cPrevious = "previous"
    cStatus = "status"
    cStats = "stats"
    cConsume = "consume"
    cRandom = "random"
    cRepeat = "repeat"
    cSingle = "single"
    cSetvol = "setvol"
    cCrossfade = "crossfade"
    cPause = "pause"
    cStop = "stop"
    cPlay = "play"
    cPlayid = "playid"
    cSeek = "seek"
    cSeekid = "seekid"
    cSeekcur = "seekcur"
  MpdSingle* = enum 
    singleFalse = "0"
    singleTrue = "1"
    singleOneshot = "oneshot"
  MpdVolume* = range[0..100]
  MpdPause* = enum
    pauseToggle = "0"
    pauseResume = "1"
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
  EventHandler = proc(client: MpdClient, event: AnswerLine): Future[void]
  AnswerLine* = tuple[key, val: string]
  AnswerLines = seq[AnswerLine]
  Answer = Table[string, string]
  MpdClient* = ref object
    host: string
    port: Port
    socketIdle: AsyncSocket
    socketCmd: AsyncSocket
    eventHandler: EventHandler
    lastCmdSent: float

proc toMpdbool(val: bool): string =
  if val: "1"
  else: "0"

proc fromMpdbool(val: string): bool = 
  if val == "1": true
  else: false

proc toTable(lines: AnswerLines): Answer = 
  ## converts the AnswerLines to a table
  result = initTable[string, string]()
  for line in lines:
    result[line.key] = line.val

proc sendCmd*(client: MpdClient, cmd: string | MpdCmd): Future[void] {.async.} = 
  client.lastCmdSent = epochTime()
  await client.socketCmd.send($cmd & "\n")

proc newMpdClient*(): MpdClient = 
  result = MpdClient()

proc checkHeader(socket: AsyncSocket): Future[bool] {.async.} = 
  let line = await socket.recvLine()
  if line == "":
    raise newException(OsError, "disconnected in recvAnswer")
  return line.startswith("OK MPD")

proc splitLine(line: string): AnswerLine = 
  echo "RAW: ", line
  let pos = line.parseUntil(result.key, ':', 0)
  result.val = line[pos+2..^1]

proc parseError(line: string): MpdError = 
  echo line 


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
      await client.sendCmd(cPing)
      let lines = await client.socketCmd.recvAnswer()
      if lines.len() != 0:
        echo "WARNING ping not OK! got: ", lines 
    await sleepAsync(1000)

proc currentSong*(client: MpdClient): Future[Answer] {.async.} = 
  ## Displays the song info of the current song (same song that is identified in status).
  await client.sendCmd(cCurrentsong)
  let lines = await client.socketCmd.recvAnswer()
  return lines.toTable

proc next*(client: MpdClient): Future[void] {.async.} = 
  ## Plays next song in the playlist.
  await client.sendCmd(cNext)
  let lines = await client.socketCmd.recvAnswer()

proc previous*(client: MpdClient): Future[void] {.async.} = 
  ## Plays previous song in the playlist.
  await client.sendCmd(cPrevious)
  let lines = await client.socketCmd.recvAnswer()

proc status*(client: MpdClient): Future[Answer] {.async.} = 
  ## Reports the current status of the player and the volume level. 
  await client.sendCmd(cStatus)
  let lines = await client.socketCmd.recvAnswer()
  return lines.toTable

proc stats*(client: MpdClient): Future[Answer] {.async.} = 
  ## Displays statistics. 
  await client.sendCmd(cStats)
  let lines = await client.socketCmd.recvAnswer()
  return lines.toTable

proc consume*(client: MpdClient, enabled: bool): Future[void] {.async.} = 
  ## Sets consume state to STATE, STATE should be 0 or 1. 
  ## When consume is activated, each song played is removed from playlist.  
  await client.sendCmd("$# $#" % [$cConsume, enabled.toMpdbool])
  let lines = await client.socketCmd.recvAnswer()

proc random*(client: MpdClient, enabled: bool): Future[void] {.async.} = 
  ## Sets random state to STATE, STATE should be 0 or 1
  await client.sendCmd("$# $#" % [$cRandom, enabled.toMpdbool])
  let lines = await client.socketCmd.recvAnswer()

proc repeat*(client: MpdClient, enabled: bool): Future[void] {.async.} = 
  ## Sets repeat state to STATE, STATE should be 0 or 1.
  await client.sendCmd("$# $#" % [$cRepeat, enabled.toMpdbool])
  let lines = await client.socketCmd.recvAnswer()

proc single*(client: MpdClient, val: MpdSingle): Future[void] {.async.} = 
  ## Sets single state to STATE, STATE should be 0, 1 or oneshot [5]. 
  ## When single is activated, playback is stopped after current song, 
  ## or song is repeated if the ‘repeat’ mode is enabled.  
  await client.sendCmd("$# $#" % [$cSingle, $val])
  let lines = await client.socketCmd.recvAnswer()

proc setvol*(client: MpdClient, volume: MpdVolume): Future[void] {.async.} = 
  ## Sets volume to VOL, the range of volume is 0-100.
  await client.sendCmd("$# $#" % [$cSetvol, $volume])
  let lines = await client.socketCmd.recvAnswer()

proc crossfade*(client: MpdClient, val: int): Future[void] {.async.} = 
  ## Sets crossfading between songs.
  await client.sendCmd("$# $#" % [$cCrossfade, $val])
  let lines = await client.socketCmd.recvAnswer()

proc pause*(client: MpdClient, val = pauseToggle): Future[void] {.async.} = 
  ## Toggles pause/resumes playing, PAUSE is 0 or 1.
  await client.sendCmd("$# $#" % [$cPause, $val])
  let lines = await client.socketCmd.recvAnswer()

proc stop*(client: MpdClient): Future[void] {.async.} = 
  ## Stops playing.
  await client.sendCmd("$#"  % [$cStop])
  let lines = await client.socketCmd.recvAnswer()

proc play*(client: MpdClient, songpos: int): Future[void] {.async.} = 
  ## Begins playing the playlist at song number SONGPOS.
  await client.sendCmd("$# $#" % [$cPlay, $songpos])
  let lines = await client.socketCmd.recvAnswer()

proc playid*(client: MpdClient, songid: int): Future[void] {.async.} = 
  ## Begins playing the playlist at song SONGID. 
  await client.sendCmd("$# $#" % [$cPlayid, $songid])
  let lines = await client.socketCmd.recvAnswer()

proc seek*(client: MpdClient, songpos, time: int): Future[void] {.async.} = 
  ## Seeks to the position TIME (in seconds; fractions allowed) of entry SONGPOS in the playlist.
  await client.sendCmd("$# $# $#" % [$cSeek, $songpos, $time])
  let lines = await client.socketCmd.recvAnswer()

proc seekid*(client: MpdClient, songid, time: int): Future[void] {.async.} = 
  ## Seeks to the position TIME (in seconds; fractions allowed) of song SONGID.  
  await client.sendCmd("$# $# $#" % [$cSeekid, $songid, $time])
  let lines = await client.socketCmd.recvAnswer()

proc seekcur*(client: MpdClient, time: int): Future[void] {.async.} = 
  ## Seeks to the position TIME (in seconds; fractions allowed) 
  ## within the current song. If prefixed by + or -, 
  ## then the time is relative to the current playing position.  
  await client.sendCmd("$# $#" % [$cSeekcur, $time])
  let lines = await client.socketCmd.recvAnswer()

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

when isMainModule:
  import random as rnd
  proc main() {.async.} =   
    proc echoEvHandler(client: MpdClient, event: AnswerLine) {.async.} =
      # dummy handler
      echo "EVENT: ", event
      echo await client.currentSong()

    var client = newMpdClient()
    if await client.connect("192.168.2.167", 6600.Port, echoEvHandler):
      echo "Connected"
      asyncCheck client.dispatchEvents()
      asyncCheck client.pingServer() # This could maybe deadlock the cmd socket??
      while true:
        let current = await client.currentSong()
        #await client.nextSong()
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

#when isMainModule:
#  assert quote("""foo'bar"""") == """foo\'bar\""""


