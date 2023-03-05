use "files"
use "itertools"
use "term"

actor Main
  let _env: Env

  new create(env: Env) =>
    _env = env

    let config = try Config(env)? else return end
    let ecs = ExitcodeSetter(env)

    let colours = Iter[String]([
      ANSI.red()
      ANSI.green()
      ANSI.yellow()
      ANSI.blue()
      ANSI.magenta()
      ANSI.cyan()
    ].values()).cycle()

    for conn in config.conns.values() do
      conn.run(env, config.prefix_len, try colours.next()? else "" end, config.command, ecs)
    end

trait tag Conn
  be run(env: Env, prefix_len: USize, colour: String, command: String, ecs: ExitcodeSetter)

actor SSH is Conn
  let _name: String
  let _host: String

  new create(name: String, host: String) =>
    _name = name
    _host = host

  be run(env: Env, prefix_len: USize, colour: String, command: String, ecs: ExitcodeSetter) =>
    // TODO: push git repository
    Run(_name, prefix_len, colour, env, "/run/current-system/sw/bin/ssh", ["ssh"; _host; command], ecs)

actor Local is Conn
  let _name: String

  new create(name: String) =>
    _name = name

  be run(env: Env, prefix_len: USize, colour: String, command: String, ecs: ExitcodeSetter) =>
    Run(_name, prefix_len, colour, env, "/bin/sh", ["sh"; "-c"; command], ecs)
