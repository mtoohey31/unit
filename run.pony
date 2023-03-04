use "backpressure"
use "files"
use "process"

class Run
  new create(env: Env, path: String, command: Array[String] iso, ecs: ExitcodeSetter) =>
    let client = ProcessClient(env, ecs)
    let notifier: ProcessNotify iso = consume client
    let pm: ProcessMonitor = ProcessMonitor(
      StartProcessAuth(env.root),
      ApplyReleaseBackpressureAuth(env.root),
      consume notifier,
      FilePath(FileAuth(env.root), path),
      consume command,
      env.vars)
    pm.done_writing() // close stdin immediately

actor ExitcodeSetter
	let _env: Env
	var _exitcode_set: Bool = false

	new create(env: Env) =>
		_env = env

	be set_exitcode(exitcode: I32) =>
		if not _exitcode_set then
			_env.exitcode(exitcode)
			_exitcode_set = true
		end

// TODO: highlight docker-style when there is more than one host
class ProcessClient is ProcessNotify
  let _env: Env
	let _ecs: ExitcodeSetter

  new iso create(env: Env, ecs: ExitcodeSetter) =>
    _env = env
		_ecs = ecs

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
				_ecs.set_exitcode(exitcode)
        _env.out.print("exit code: " + exitcode.string())
      end
    | let signaled: Signaled =>
      _env.out.print("signaled: " + signaled.signal().string())
    end
