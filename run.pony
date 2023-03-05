use "backpressure"
use "files"
use "process"
use "term"

class Run
  new create(name: String, prefix_len: USize, colour: String, env: Env, path: String, command: Array[String] iso, ecs: ExitcodeSetter) =>
    let client = ProcessClient(name, prefix_len, colour, env, ecs)
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

// TODO: keep track of modifiers in the actual output and preserve them across
// lines
class ProcessClient is ProcessNotify
  let _name: String
  let _prefix_len: USize
  let _colour: String
  let _env: Env
	let _ecs: ExitcodeSetter
  let _buf: Array[U8] = Array[U8]()
  let _pending_out: String ref = String()
  let _pending_err: String ref = String()

  new iso create(name: String, prefix_len: USize, colour: String, env: Env, ecs: ExitcodeSetter) =>
    _name = name
    _prefix_len = prefix_len
    _colour = colour
    _env = env
		_ecs = ecs

  fun ref stdout(process: ProcessMonitor ref, data: Array[U8] iso) =>
    _print(consume data)

  fun ref stderr(process: ProcessMonitor ref, data: Array[U8] iso) =>
    _eprint(consume data)

  fun ref failed(process: ProcessMonitor ref, err: ProcessError) =>
    _eprint_string("failed: " + err.string())

  fun ref dispose(process: ProcessMonitor ref, child_exit_status: ProcessExitStatus) =>
    if _pending_out.size() != 0 then
      _env.out.print(_prefix() + _pending_out)
    end
    if _pending_err.size() != 0 then
      _env.err.print(_prefix() + _pending_err)
    end

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

  fun box _prefix(): String =>
    _colour + _name + " ".repeat_str((_prefix_len - _name.size()) + 1) + "| " + ANSI.reset()

  fun box _err_path(): FilePath =>
    FilePath(FileAuth(_env.root), _name + ".err")

  fun ref _eprint_string(s: String iso) =>
    let data = (consume s).iso_array()
    data.push('\n')
    _eprint(consume data)

  fun ref _fprint(out: OutStream, pending: String ref, data: Array[U8] iso) =>
    let s = String.from_iso_array(consume data)
    let parts: Array[String] iso = s.split_by("\n")
    let last = try parts.pop()? else "" end
    if parts.size() > 0 then
      out.write(_prefix() + pending + ("\n" + _prefix()).join((consume parts).values()) + "\n")
      pending.truncate(0)
    end
    pending.concat(last.values())

  fun ref _print(data: Array[U8] iso) =>
    _fprint(_env.out, _pending_out, consume data)

  fun ref _eprint(data: Array[U8] iso) =>
    _fprint(_env.err, _pending_err, consume data)
