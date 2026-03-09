#!/usr/bin/env python3
import pexpect
import sys
import time
import os

RP_HOST = os.environ.get("RP_HOST", "rp-f0edec.local")
RP_USER = os.environ.get("RP_USER", "root")
RP_PASS = os.environ.get("RP_PASS", "root")
REMOTE_DIR = "/opt/rp-web-scope"
DEPLOY_DIR = "deploy"


def run_ssh_command(cmd, password=RP_PASS):
    print(f"Running: {cmd}")
    child = pexpect.spawn(cmd, timeout=60)
    try:
        i = child.expect(["password:", pexpect.EOF, pexpect.TIMEOUT])
        if i == 0:
            child.sendline(password)
            child.expect(pexpect.EOF)

        output = ""
        if child.before:
            output = child.before.decode("utf-8", errors="replace")
        if child.after and not isinstance(child.after, type):
            output += child.after.decode("utf-8", errors="replace")

        child.close()
        return child.exitstatus == 0, output
    except Exception as e:
        print(f"Error: {e}")
        return False, str(e)


def main():
    print("=== Deploying Red Pitaya Web Scope ===")
    print(f"Target: {RP_USER}@{RP_HOST}\n")

    print("Step 1: Creating remote directory...")
    success, output = run_ssh_command(
        f'ssh -o StrictHostKeyChecking=no {RP_USER}@{RP_HOST} "mkdir -p {REMOTE_DIR}"'
    )
    if not success:
        print(f"Failed: {output}")
        return 1

    print("\nStep 2: Stopping service and cleaning up...")
    run_ssh_command(
        f'ssh -o StrictHostKeyChecking=no {RP_USER}@{RP_HOST} "systemctl stop rp-web-scope 2>/dev/null; pkill -9 rp-web-scope 2>/dev/null; rm -f {REMOTE_DIR}/rp-web-scope; true"'
    )
    time.sleep(1)

    print("\nStep 3: Copying files to device...")
    success, output = run_ssh_command(
        f"scp -o StrictHostKeyChecking=no -r {DEPLOY_DIR}/rp-web-scope {DEPLOY_DIR}/rp-web-scope.service {DEPLOY_DIR}/frontend {RP_USER}@{RP_HOST}:{REMOTE_DIR}/"
    )
    if not success:
        print(f"Failed: {output}")
        return 1

    print("\nStep 4: Setting permissions...")
    success, output = run_ssh_command(
        f'ssh -o StrictHostKeyChecking=no {RP_USER}@{RP_HOST} "chmod +x {REMOTE_DIR}/rp-web-scope"'
    )
    if not success:
        print(f"Failed: {output}")
        return 1

    print("\n=== Deployment Complete! ===\n")
    print("Configuring and starting systemd service...\n")

    # Install service file
    success, output = run_ssh_command(
        f'ssh -o StrictHostKeyChecking=no {RP_USER}@{RP_HOST} "cp {REMOTE_DIR}/rp-web-scope.service /etc/systemd/system/ && systemctl daemon-reload && systemctl enable rp-web-scope"'
    )
    if not success:
        print(f"Failed to install service: {output}")
        return 1

    # Restart service
    print("Restarting rp-web-scope service...")
    success, output = run_ssh_command(
        f'ssh -o StrictHostKeyChecking=no {RP_USER}@{RP_HOST} "systemctl restart rp-web-scope"'
    )
    if not success:
        print(f"Failed to restart service: {output}")
        return 1

    time.sleep(2)

    print("\nChecking if service is running...")
    success, output = run_ssh_command(
        f'ssh -o StrictHostKeyChecking=no {RP_USER}@{RP_HOST} "systemctl status rp-web-scope"'
    )

    if success and "Active: active (running)" in output:
        print("\n=== Service Started Successfully via Systemd! ===\n")
        print(f"Access the web interface at: http://{RP_HOST}:3000\n")
        print(f"View logs: ssh {RP_USER}@{RP_HOST} 'journalctl -u rp-web-scope -f'\n")
        return 0
    else:
        print("\nWarning: Service might not be running correctly")
        print("Check status:")
        print(output)
        return 1


if __name__ == "__main__":
    sys.exit(main())
