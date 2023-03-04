use "backpressure"
use "files"
use "itertools"
use "json"
use "process"

actor Main
  new create(env: Env) =>
    let config = try Config(env)? else return end

    for conn in config.conns.values() do
      conn.run(env, config.command)
    end

// High Level

trait tag Conn
  be run(env: Env, command: String)

actor SSH is Conn
  let _name: String
  let _host: String

  new create(name: String, host: String) =>
    _name = name
    _host = host

  be run(env: Env, command: String) =>
    // TODO: push git repository
    Run(env, "/run/current-system/sw/bin/ssh", ["ssh"; _host; command])

actor Local is Conn
  let _name: String

  new create(name: String) =>
    _name = name

  be run(env: Env, command: String) =>
    Run(env, "/bin/sh", ["sh"; "-c"; command])

// Nuts and Bolts

class Config
  let command: String
  let conns: Array[Conn]

  new create(env: Env) ? =>
    // TODO: warn about unrecognized entries in all the parsing below

    let config_text = String()

    var file = File.open(FilePath(FileAuth(env.root), "unit.json"))
    if file.errno() is FileError then
      file = File.open(FilePath(FileAuth(env.root), ".unit.json"))
    end

    while file.errno() is FileOK do
      config_text.append(file.read_string(1024))
    end

    let msg: (String | None) = match file.errno()
    | FileEOF => None
    | FileError => "File error"
    | FileBadFileNumber => "Bad file number"
    | FilePermissionDenied => "Permission denied"
    else
      "Unknown error"
    end

    match msg
    | let m: String =>
      env.err.print("unit: Error opening config file: " + m)
      env.exitcode(1)
      error
    end

    let config_doc = JsonDoc

    try
      config_doc.parse(config_text.string())?
    else
      (let line, let message) = config_doc.parse_report()
      env.err.print("unit: Error parsing config file: " + line.string() + ": " + message)
      env.exitcode(1)
      error
    end

    let config_obj = try
      config_doc.data as JsonObject
    else
      env.err.print("unit: Config file JSON root should be object")
      env.exitcode(1)
      error
    end

    command = try
      try
        config_obj.data("command")?
      else
        env.err.print("unit: Config file missing \"command\" key")
        env.exitcode(1)
        error
      end as String
    else
      env.err.print("unit: Config file \"command\" key should be string")
      env.exitcode(1)
      error
    end

    let hosts_obj = try
      try
        config_obj.data("hosts")?
      else
        env.err.print("unit: Config file missing \"hosts\" key")
        env.exitcode(1)
        error
      end as JsonObject
    else
      env.err.print("unit: Config file \"hosts\" key should be object")
      env.exitcode(1)
      error
    end

    conns = Array[Conn]()

    for (name, host_json) in hosts_obj.data.pairs() do
      let host_obj = try
        host_json as JsonObject
      else
        env.err.print("unit: Config file \"hosts." + name + "\" entry should be object")
        env.exitcode(1)
        error
      end

      if host_obj.data.size() != 1 then
        env.out.print("unit: Config file \"hosts." + name + "\" object should have a single entry")
      end

      try
        (let key, let conn_json) = host_obj.data.pairs().next()?
        let conn: Conn = match key
        | "local" => Local(name)
        | "ssh" =>
          let host = try
            conn_json as String
          else
            env.err.print("unit: Config file \"hosts." + name + ".ssh\" entry should be string")
            env.exitcode(1)
            error
          end
          SSH(name, host)
        else
          env.err.print("unit: Config file \"hosts." + name + "\" entry should have child with name \"local\" or \"ssh\", found \"" + key + "\"")
          env.exitcode(1)
          error
        end

        conns.push(conn)
      end // else is impossible since we verified host_obj.data.size() == 1 above
    end

class Run
  new create(env: Env, path: String, command: Array[String] iso) =>
    let client = ProcessClient(env)
    let notifier: ProcessNotify iso = consume client
    let pm: ProcessMonitor = ProcessMonitor(
      StartProcessAuth(env.root),
      ApplyReleaseBackpressureAuth(env.root),
      consume notifier,
      FilePath(FileAuth(env.root), path),
      consume command,
      env.vars)
    pm.done_writing() // close stdin immediately

// TODO: highlight docker-style when there is more than one host
class ProcessClient is ProcessNotify
  let _env: Env

  new iso create(env: Env) =>
    _env = env

  fun ref stdout(process: ProcessMonitor ref, data: Array[U8] iso) =>
    _env.out.print(String.from_array(consume data))

  fun ref stderr(process: ProcessMonitor ref, data: Array[U8] iso) =>
    _env.out.print(String.from_array(consume data))

  fun ref failed(process: ProcessMonitor ref, err: ProcessError) =>
    _env.out.print("failed: " + err.string())

  fun ref dispose(process: ProcessMonitor ref, child_exit_status: ProcessExitStatus) =>
    match child_exit_status
    | let exited: Exited =>
      let exitcode = exited.exit_code()
      if exitcode != 0 then
        _env.exitcode(exitcode)
        _env.out.print("exit code: " + exitcode.string())
      end
    | let signaled: Signaled =>
      _env.out.print("signaled: " + signaled.signal().string())
    end
