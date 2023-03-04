use "backpressure"
use "files"
use "process"

class Run
  new create(name: String, env: Env, path: String, command: Array[String] iso, ecs: ExitcodeSetter) =>
    let client = ProcessClient(name, env, ecs)
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
  let _name: String
  let _env: Env
	let _ecs: ExitcodeSetter
  let _buf: Array[U8] = Array[U8]()

  new iso create(name: String, env: Env, ecs: ExitcodeSetter) =>
    _name = name
    _env = env
		_ecs = ecs

  fun ref stdout(process: ProcessMonitor ref, data: Array[U8] iso) =>
    _print(consume data)

  fun ref stderr(process: ProcessMonitor ref, data: Array[U8] iso) =>
    _eprint(consume data)

  fun ref failed(process: ProcessMonitor ref, err: ProcessError) =>
    _eprint_string("failed: " + err.string())

  fun ref dispose(process: ProcessMonitor ref, child_exit_status: ProcessExitStatus) =>
    match child_exit_status
    | let exited: Exited =>
      let exitcode = exited.exit_code()
      if exitcode == 0 then
        // remove error file if it exists, then early return to avoid printing
        // "exit code: 0" and saving the output
        _err_path().remove()
        return
      end
			_ecs.set_exitcode(exitcode)
      _eprint_string("exit code: " + exitcode.string())
    | let signaled: Signaled =>
      _eprint_string("signaled: " + signaled.signal().string())
    end

    let err_file = File(_err_path())

    let msg = match err_file.errno()
    | FileOK =>
      err_file.set_length(0) // truncate
      err_file.write(_buf)
      return
    | FileError => "File error"
    | FileBadFileNumber => "Bad file number"
    | FilePermissionDenied => "Permission denied"
    else
      "Unknown error"
    end

    _env.out.print("unit: Error writing output: " + msg)

  fun box _err_path(): FilePath => FilePath(FileAuth(_env.root), _name + ".err")

  fun ref _eprint_string(s: String iso) =>
    let data = (consume s).iso_array()
    data.push('\n')
    _eprint(consume data)

  fun ref _print(data: Array[U8] iso) =>
    let data': Array[U8] val = consume data
    _buf.concat(data'.values())
    _env.out.write(String.from_array(data'))

  fun ref _eprint(data: Array[U8] iso) =>
    let data': Array[U8] val = consume data
    _buf.concat(data'.values())
    _env.err.write(String.from_array(data'))
