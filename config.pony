use "files"
use "json"

class Config
  let command: String
  let conns: Array[Conn]
  var prefix_len: USize = 0

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
      if name.size() > prefix_len then
        prefix_len = name.size()
      end

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
