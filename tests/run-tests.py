#!/usr/bin/env python3
"""Compile production TOTP code and auth state handlers with in-memory OS doubles.
No real Keychain, VPN connection, UI alert, or network is accessed.
"""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'tunnelblick/VPNConnection.m').read_text()
signatures = [
    '-(void) processPasswordOrPassphraseWithLine:',
    '-(void) afterFailure: (NSDictionary *) dict {',
    '-(void) credentialsHaveBeenAskedFor: (NSDictionary *) dict {',
    '-(void) cancelAutomaticTotpCredentialsTimer {',
    '-(void) provideAutomaticTotpCredentials: (NSTimer *) timer {',
    '-(BOOL) deferAutomaticTotpCredentials:',
    '-(void) prepareAutomaticTotpForConnection {',
]

def method(signature):
    start = source.index(signature)
    # Skip a private declaration, when present.
    while source.find(';', start) < source.find('{', start):
        start = source.index(signature, start + len(signature))
    opening = source.index('{', start)
    depth = 1
    cursor = opening + 1
    while depth:
        depth += (source[cursor] == '{') - (source[cursor] == '}')
        cursor += 1
    return source[start:cursor]

with tempfile.TemporaryDirectory(prefix='tunnelblick-totp-tests-') as temporary:
    work = Path(temporary)
    (work / 'ProductionAuthHandlers.inc').write_text('\n\n'.join(map(method, signatures)))
    command = ['xcrun', 'clang', '-fno-objc-arc', '-fblocks', '-Wall', '-Wextra',
               '-Werror', '-Wno-unused-parameter', '-Wno-deprecated-declarations',
               '-I' + str(root / 'tunnelblick'), '-I' + temporary,
               '-fmodules-cache-path=' + str(work / 'ModuleCache'),
               '-framework', 'Cocoa', str(root / 'tests/AutomaticTotpTests.m'),
               str(root / 'tunnelblick/TBTotpGenerator.m'),
               str(root / 'tunnelblick/NSTimer+TB.m'), '-o', str(work / 'tests')]
    subprocess.run(command, check=True, cwd=root)
    subprocess.run([str(work / 'tests')], check=True, cwd=root)
    source = (root / 'tunnelblick/AuthAgent.m').read_text()
    (work / 'ProductionCredentialHandler.inc').write_text(method('-(NSArray *)getUsernameAndPassword'))
    credential_command = command[:]
    credential_command[credential_command.index(str(root / 'tests/AutomaticTotpTests.m'))] = str(root / 'tests/AuthAgentTotpTests.m')
    credential_command[-1] = str(work / 'credential-tests')
    subprocess.run(credential_command, check=True, cwd=root)
    subprocess.run([str(work / 'credential-tests')], check=True, cwd=root)
