# Client for the musik player deamon
import asyncnet, asyncdispatch, strutils, parseutils, times, tables

type 
  MpdCmd* = enum
    cIdle = "idle"
    cNoidle = "noidle"
    cPing = "ping"
    cCurrentsong = "currentsong"
    
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

proc sendCmd*(client: MpdClient, cmd: string | MpdCmd): Future[void] {.async.} = 
  client.lastCmdSent = epochTime()
  await client.socketCmd.send($cmd & "\n")

proc newMpdClient*(eventHandler: EventHandler): MpdClient = 
  result = MpdClient()
  result.eventHandler = eventHandler

proc checkHeader(socket: AsyncSocket): Future[bool] {.async.} = 
  let line = await socket.recvLine()
  if line == "":
    raise newException(OsError, "disconnected in recvAnswer")
  return line.startswith("OK MPD")

proc splitLine(line: string): AnswerLine = 
  echo "RAW: ", line
  let pos = line.parseUntil(result.key, ':', 0)
  result.val = line[pos+2..^1]

proc recvAnswer(socketCmd: AsyncSocket): Future[AnswerLines] {.async.} =
  result = @[]
  while true:
    let line = (await socketCmd.recvLine()).strip()
    if line == "": 
      raise newException(OsError, "disconnected in recvAnswer")
    if line == "OK": break
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
  await client.sendCmd(cCurrentsong)
  let lines = await client.socketCmd.recvAnswer()
  return lines.toTable

proc dispatchEvents*(client: MpdClient) {.async.} =
  ## calls the event handler
  echo "SET IDLE MODE"
  while true:
    var lines = await client.socketIdle.recvAnswer()
    echo "LINES: ", lines
    for line in lines:
      await client.eventHandler(client, line)
    await client.socketIdle.send($cIdle & "\n")

proc connect*(client: MpdClient, host: string, port: Port): Future[bool] {.async.} =
  client.host = host
  client.port = port
  client.socketCmd = await asyncnet.dial(host, port)
  if (await client.socketCmd.checkHeader()) == false:
    echo "Could not connect to cmd socketCmd"
    if not client.socketCmd.isClosed():
      client.socketCmd.close()
    return false
  #asyncCheck client.pingServer() # ping loop
  client.lastCmdSent = epochTime() 
  client.socketIdle = await asyncnet.dial(host, port)
  if (await client.socketIdle.checkHeader()) == false:
    echo "Could not connect to cmd socketIdle"
    if not client.socketIdle.isClosed():
      client.socketIdle.close()
    return false
  await client.socketIdle.send($cIdle & "\n")
  return true

proc toTable(lines: AnswerLines): Answer = 
  ## converts the AnswerLines to a table
  result = initTable[string, string]()
  for line in lines:
    result[line.key] = line.val

when isMainModule:
  proc main() {.async.} =   
    proc echoEvHandler(client: MpdClient, event: AnswerLine) {.async.} =
      # dummy handler
      echo "EVENT: ", event
      echo await client.currentSong()

    var client = newMpdClient(echoEvHandler)
    if await client.connect("192.168.1.110", 6600.Port):
      echo "Connected"
      asyncCheck client.dispatchEvents()
      asyncCheck client.pingServer() # This could maybe deadlock ??
      while true:
        let current = await client.currentSong()
        echo current
        await sleepAsync(15000)
    else:
      echo "could not connect"
  waitFor main()


