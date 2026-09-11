#!/usr/bin/env node
/*
 * Minimal password-based SSH helper for DSH (uses pure-JS ssh2, no child_process).
 *
 * Usage:
 *   node sshx.js exec  "<remote shell command>"      [--timeout ms]
 *   node sshx.js script <local/file.sh> [--sudo]     [--timeout ms]
 *   node sshx.js put   <local> <remote>
 *   node sshx.js get   <remote> <local>
 *
 * Connection info comes from env: DGX_HOST, DGX_PORT(22), DGX_USER, DGX_PASS.
 * Exit code mirrors the remote command's exit status.
 */
const fs = require('fs');
const path = require('path');
const { Client } = require(path.join(__dirname, '..', '.nodemods', 'node_modules', 'ssh2'));

const HOST = process.env.DGX_HOST;
const PORT = parseInt(process.env.DGX_PORT || '22', 10);
const USER = process.env.DGX_USER;
const PASS = process.env.DGX_PASS;

function connect() {
  return new Promise((resolve, reject) => {
    const c = new Client();
    c.on('ready', () => resolve(c));
    c.on('error', reject);
    c.connect({
      host: HOST, port: PORT, username: USER, password: PASS,
      readyTimeout: 30000, keepaliveInterval: 15000,
      algorithms: undefined,
    });
  });
}

function exec(c, command, { sudo = false, timeout = 0 } = {}) {
  return new Promise((resolve) => {
    const cmd = sudo ? `sudo -S -p '' bash -c ${JSON.stringify(command)}` : command;
    c.exec(cmd, { pty: false }, (err, stream) => {
      if (err) return resolve({ code: 255, out: '', errr: String(err) });
      let out = '', errr = '', done = false;
      let timer = null;
      if (timeout > 0) timer = setTimeout(() => { done = true; try { stream.close(); } catch (e) {} resolve({ code: 124, out, errr: errr + '\n[timeout]' }); }, timeout);
      if (sudo) stream.write(PASS + '\n');
      stream.on('data', (d) => { out += d.toString('utf8'); process.stdout.write(d); });
      stream.stderr.on('data', (d) => { errr += d.toString('utf8'); process.stderr.write(d); });
      stream.on('close', (code, signal) => {
        if (done) return;
        done = true;
        if (timer) clearTimeout(timer);
        resolve({ code: code === null ? (signal ? 137 : 0) : code, out, errr });
      });
    });
  });
}

function sftpPut(c, local, remote) {
  return new Promise((resolve, reject) => {
    c.sftp((err, sftp) => {
      if (err) return reject(err);
      sftp.fastPut(local, remote, (e) => e ? reject(e) : resolve());
    });
  });
}

function sftpGet(c, remote, local) {
  return new Promise((resolve, reject) => {
    c.sftp((err, sftp) => {
      if (err) return reject(err);
      sftp.fastGet(remote, local, (e) => e ? reject(e) : resolve());
    });
  });
}

(async () => {
  const argv = process.argv.slice(2);
  const mode = argv[0];
  const timeoutIdx = argv.indexOf('--timeout');
  const timeout = timeoutIdx > -1 ? parseInt(argv[timeoutIdx + 1], 10) : 0;
  const sudo = argv.includes('--sudo');
  const args = argv.slice(1).filter((a, i, arr) => {
    if (a === '--sudo') return false;
    if (a === '--timeout' || (i > 0 && arr[i - 1] === '--timeout')) return false;
    return true;
  });

  if (!HOST || !USER || !PASS) {
    console.error('missing DGX_HOST / DGX_USER / DGX_PASS env');
    process.exit(2);
  }

  let result;
  try {
    const c = await connect();
    if (mode === 'exec') {
      result = await exec(c, args[0], { sudo, timeout });
    } else if (mode === 'script') {
      const local = args[0];
      const body = fs.readFileSync(local, 'utf8').replace(/\r\n/g, '\n');
      const remote = `/tmp/dsh-job-${Date.now()}.sh`;
      const tmpLocal = path.join(path.dirname(local), `.upload-${Date.now()}.sh`);
      fs.writeFileSync(tmpLocal, body);
      await sftpPut(c, tmpLocal, remote);
      fs.unlinkSync(tmpLocal);
      // forward any positional args (everything after the script path) to the script
      const shq = (s) => "'" + String(s).replace(/'/g, "'\\''") + "'";
      const fwd = args.slice(1).map(shq).join(' ');
      result = await exec(c, `bash ${remote} ${fwd}; rc=$?; rm -f ${remote}; exit $rc`, { sudo, timeout });
    } else if (mode === 'put') {
      await sftpPut(c, args[0], args[1]);
      result = { code: 0, out: `uploaded ${args[0]} -> ${args[1]}\n`, errr: '' };
      process.stdout.write(result.out);
    } else if (mode === 'get') {
      await sftpGet(c, args[0], args[1]);
      result = { code: 0, out: `downloaded ${args[0]} -> ${args[1]}\n`, errr: '' };
      process.stdout.write(result.out);
    } else {
      console.error('unknown mode: ' + mode);
      process.exit(2);
    }
    c.end();
    process.exitCode = (result && typeof result.code === 'number') ? result.code : 0;
  } catch (e) {
    console.error('SSH ERROR: ' + (e && e.message ? e.message : String(e)));
    process.exit(3);
  }
})();
