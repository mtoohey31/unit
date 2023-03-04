use "files"
use "itertools"

actor Main
  let _env: Env

  new create(env: Env) =>
    _env = env

    let config = try Config(env)? else return end
    let ecs = ExitcodeSetter(env)

    for conn in config.conns.values() do
      conn.run(env, config.command, ecs)
    end

trait tag Conn
  be run(env: Env, command: String, ecs: ExitcodeSetter)

actor SSH is Conn
  let _name: String
  let _host: String

  new create(name: String, host: String) =>
    _name = name
    _host = host

  be run(env: Env, command: String, ecs: ExitcodeSetter) =>
    // TODO: push git repository
    Run(_name, env, "/run/current-system/sw/bin/ssh", ["ssh"; _host; command], ecs)

actor Local is Conn
  let _name: String

  new create(name: String) =>
    _name = name

  be run(env: Env, command: String, ecs: ExitcodeSetter) =>
    Run(_name, env, "/bin/sh", ["sh"; "-c"; command], ecs)
