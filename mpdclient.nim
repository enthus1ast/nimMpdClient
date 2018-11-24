# Client for the musik player deamon
import asyncnet, asyncdispatch, strutils, parseutils

type 
  MpdCmd = enum
    cIdle = "idle"
    cNoidle = "noidle"
    cPing = "ping"
    cCurrentsong = "currentsong"
    
  EventHandler = proc(client: MpdClient, event: AnswerLine): Future[void]
  AnswerLine = tuple[key, val: string]
  GenericAnswer = seq[AnswerLine]
  MpdClient = ref object
    host: string
    port: Port
    idle: bool
    socket: AsyncSocket
    eventHandler: EventHandler

proc sendCmd*(client: MpdClient, cmd: string | MpdCmd): Future[void] {.async.} = 
  if client.idle:
    client.idle = false
    await client.socket.send($cNoidle & "\n")
  await client.socket.send($cmd & "\n")

proc newMpdClient(eventHandler: EventHandler): MpdClient = 
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

proc recvAnswer(socket: AsyncSocket): Future[GenericAnswer] {.async.} =
  result = @[]
  while true:
    let line = await socket.recvLine()
    if line == "": 
      raise newException(OsError, "disconnected in recvAnswer")
    if line == "OK": break
    else: 
      result.add(line.splitLine)
  ## Cleanup here whats left

proc pingServer(client: MpdClient, interval = 10_000) {.async.} =
  while true:
    echo "ping server" 
    await client.sendCmd(cPing)
    let lines = await client.socket.recvAnswer()
    if lines.len() != 0:
      echo "WARNING ping not OK! got: ", lines 
    await sleepAsync(interval)

proc currentSong*(client: MpdClient): Future[string] {.async.} = 
  await client.sendCmd(cCurrentsong)
  echo await client.socket.recvAnswer()
  return "DUMM !!"

proc dispatchEvents(client: MpdClient) {.async.} =
  ## calls the event handler
  echo "SET IDLE MODE"
  while true:
    if not client.idle:
      client.idle = true
      await client.sendCmd(cIdle)
    
    var lines = await client.socket.recvAnswer()
    client.idle = false # idle is canceled after every event by the server

    echo "LINES: ", lines
    for line in lines:
      await client.eventHandler(client, line)

proc connect*(client: MpdClient, host: string, port: Port): Future[bool] {.async.} =
  client.host = host
  client.port = port
  client.socket = await asyncnet.dial(host, port)
  if (await client.socket.checkHeader()) == false:
    echo "Could not connect to cmd socket"
    if not client.socket.isClosed():
      client.socket.close()
    return false
  asyncCheck client.pingServer() # ping loop
  return true

proc echoEvHandler(client: MpdClient, event: AnswerLine) {.async.} =
  # dummy handler
  echo "EVENT: ", event
  echo await client.currentSong()

proc toTable() = 
  ## converts the generic answer to a table
  discard

proc main() {.async.} = 
  var client = newMpdClient(echoEvHandler)
  if await client.connect("192.168.1.110", 6600.Port):
    echo "Connected"
    echo await client.currentSong()
    await client.dispatchEvents()
  else:
    echo "could not connect"
when isMainModule:
  waitFor main()


