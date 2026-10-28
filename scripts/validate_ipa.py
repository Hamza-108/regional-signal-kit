"""Validate a device-only unsigned package without any signing credentials."""
import pathlib
import plistlib
import struct
import sys
import zipfile

def validate(path):
    with zipfile.ZipFile(path) as archive:
        assert archive.testzip() is None, 'Invalid archive CRC'
        names=archive.namelist();root='Payload/SignalKit.app/'
        info=plistlib.loads(archive.read(root+'Info.plist'))
        assert info['CFBundleIdentifier']=='org.regionalsignal.client'
        assert info['CFBundleShortVersionString']=='0.1.0'
        assert info['CFBundleVersion']=='2'
        assert info['NSAppTransportSecurity'].get('NSAllowsLocalNetworking') is True
        assert not info['NSAppTransportSecurity'].get('NSAllowsArbitraryLoads',False)
        assert info.get('NSLocalNetworkUsageDescription')
        assert info['DTPlatformName']=='iphoneos'
        assert 'iPhoneOS' in info['CFBundleSupportedPlatforms']
        executable=archive.read(root+info['CFBundleExecutable'])
        assert executable[:4]==bytes.fromhex('cffaedfe'), 'Expected a device Mach-O'
        assert struct.unpack_from('<I',executable,4)[0]==0x0100000C, 'Expected arm64'
        assert b'SyntheticUITests' not in executable and b'synthetic-only' not in executable, 'Test transport in release binary'
        assert not any(n.endswith('embedded.mobileprovision') for n in names)
        for name in names:
            assert not any(part in ['.local-docs','.env','data'] for part in pathlib.PurePosixPath(name).parts)
            assert not name.endswith(('.sqlite','.sqlite-wal','.sqlite-shm'))
        print('Validated unsigned arm64 device payload, identity and excluded private files')
if __name__=='__main__':validate(sys.argv[1])
