# Client for the musik player deamon
import asyncnet, asyncdispatch, strutils, parseutils

type 
  EventHandler = proc(client: MpdClient, event: AnswerLine): Future[void]
  AnswerLine = tuple[key, val: string]
  GenericAnswer = seq[AnswerLine]
  MpdClient = ref object
    host: string
    port: Port
    socketIdle: AsyncSocket
    socketCmd: AsyncSocket
    eventHandler: EventHandler

proc newMpdClient(eventHandler: EventHandler): MpdClient = 
  result = MpdClient()
  result.eventHandler = eventHandler

proc checkHeader(socket: AsyncSocket): Future[bool] {.async.} = 
  let line = await socket.recvLine()
  return line.startswith("OK MPD")

proc splitLine(line: string): AnswerLine =  
  let pos = line.parseUntil(result.key, ':', 0)
  result.val = line[pos+2..^1]

proc recvAnswer(socket: AsyncSocket): Future[GenericAnswer] {.async.} =
  result = @[]
  while true:
    let line = await socket.recvLine()
    if line == "OK": break
    else: 
      result.add(line.splitLine)

proc pingServer(socket: AsyncSocket, interval = 10_000) {.async.} =
  while true:
    echo "ping server"
    await socket.send("ping\n")
    if (await socket.recvAnswer()).len() != 0:
      echo "WARNING ping not OK!"
    await sleepAsync(interval)

proc currentSong*(client: MpdClient): Future[string] {.async.} = 
  await client.socketCmd.send("currentsong\n")
  echo await client.socketCmd.recvAnswer()
  return "asdf"

proc dispatchEvents(client: MpdClient) {.async.} =
  ## calls the event handler
  echo "SET IDLE MODE"
  while true:
    await client.socketIdle.send("idle\n")
    var lines = await client.socketIdle.recvAnswer()
    echo "LINES: ", lines
    await client.eventHandler(client, lines[0])

proc connect*(client: MpdClient, host: string, port: Port): Future[bool] {.async.} =
  client.host = host
  client.port = port
  client.socketCmd = await asyncnet.dial(host, port)
  if (await client.socketCmd.checkHeader()) == false:
    echo "Could not connect to cmd socket"
    client.socketCmd.close()
    return false
  asyncCheck client.socketCmd.pingServer()

  # Only needed if event handler bound TODO
  client.socketIdle = await asyncnet.dial(host, port)
  if (await client.socketIdle.checkHeader()) == false:
    echo "Could not connect to idle socket"
    client.socketIdle.close()
    return false
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
    await client.dispatchEvents()
    #echo await client.currentSong()
  else:
    echo "could not connect"
when isMainModule:
  waitFor main()


