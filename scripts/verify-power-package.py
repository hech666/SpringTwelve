import struct, hashlib, pathlib, subprocess, tempfile, sys

def verify_macho(path):
    data=path.read_bytes()
    assert data[:4]==b'\xcf\xfa\xed\xfe', 'Expected thin 64-bit Mach-O'
    cpu,subtype=struct.unpack_from('<II',data,4)
    assert cpu==0x100000c and subtype==0x80000002, (hex(cpu),hex(subtype))
    ncmds=struct.unpack_from('<I',data,16)[0]
    pos=32; signature=None
    for _ in range(ncmds):
        cmd,size=struct.unpack_from('<II',data,pos)
        if cmd==0x1d:
            off,length=struct.unpack_from('<II',data,pos+8)
            signature=data[off:off+length]
        assert size>=8
        pos+=size
    assert signature is not None, 'No embedded signature'
    magic,length,count=struct.unpack_from('>III',signature)
    assert magic==0xfade0cc0 and length<=len(signature)
    checked=0
    for j in range(count):
        slot,off=struct.unpack_from('>II',signature,12+8*j)
        m,l=struct.unpack_from('>II',signature,off)
        if m!=0xfade0c02: continue
        cd=signature[off:off+l]
        version,flags,hashoff,identoff,special,ncode,limit=struct.unpack_from('>IIIIIII',cd,8)
        hsize,htype,platform,page=struct.unpack_from('BBBB',cd,36)
        if version>=0x20300 and limit==0xffffffff: limit=struct.unpack_from('>Q',cd,56)[0]
        alg={1:'sha1',2:'sha256',3:'sha256',4:'sha384'}[htype]
        chunk=(1<<page) if page else limit
        assert ncode==(limit+chunk-1)//chunk
        for i in range(ncode):
            expected=cd[hashoff+i*hsize:hashoff+(i+1)*hsize]
            actual=hashlib.new(alg,data[i*chunk:min((i+1)*chunk,limit)]).digest()[:hsize]
            assert expected==actual, 'Code-signature page hash mismatch: %d'%i
        checked+=ncode
    assert checked>0
    print(path.name, 'arm64e subtype=0x80000002;', checked, 'signature page hashes PASS')

package=pathlib.Path(sys.argv[1])
print('Package SHA256',hashlib.sha256(package.read_bytes()).hexdigest())
print(subprocess.check_output(['dpkg-deb','-f',str(package),'Package','Version','Architecture'],text=True))
with tempfile.TemporaryDirectory(prefix='st-power-verify-') as tmp:
    root=pathlib.Path(tmp)
    subprocess.run(['dpkg-deb','-x',str(package),tmp],check=True)
    dylibs=list(root.rglob('*.dylib'))
    assert len(dylibs)==1 and dylibs[0].name=='AxsSpringTwelve.dylib'
    verify_macho(dylibs[0])
    helpers=list(root.rglob('AxsSpringTwelvePowerHelper')); assert len(helpers)==1
    helper=helpers[0]
    verify_macho(helper)
    import tarfile, io, shutil
    payload = subprocess.check_output(['dpkg-deb', '--fsys-tarfile', str(package)])
    with tarfile.open(fileobj=io.BytesIO(payload)) as archive:
        allowed_paths = {'usr/local/libexec/AxsSpringTwelvePowerHelper',
                         'var/jb/usr/local/libexec/AxsSpringTwelvePowerHelper'}
        entries = [e for e in archive.getmembers()
                   if e.name.removeprefix('./').lstrip('/') in allowed_paths]
        assert len(entries) == 1
        entry = entries[0]
        assert entry.isfile() and entry.uid == 0 and entry.gid == 0
        assert entry.mode & 0o4000 and not entry.mode & 0o022
    import plistlib
    ldid=shutil.which('ldid') or '/var/minis/shared/toolchains/ld64-arm64e/bin/ldid'
    entitlements=plistlib.loads(subprocess.check_output([ldid,'-e',str(helper)]))
    for key in ['platform-application','com.apple.private.security.no-sandbox',
                'com.apple.private.xpc.launchd.userspace-reboot',
                'com.apple.private.xpc.launchd.userspace-reboot-now']:
        assert entitlements.get(key) is True, key
    print('Power helper ownership, setuid mode and dedicated entitlements PASS')
    for name,digest in {
        'MUtoolRecord':'f00d1331cd5c820432ba23fd3616cbc836f2e4b84df6ce2c3babc58381b0baea',
        'MUtoolMixer':'368d638ffdc2724431be66fbb8586a2d0521a1bef70c54b1731b9b891278fa60'
    }.items():
        matches=list(root.rglob(name)); assert len(matches)==1
        assert hashlib.sha256(matches[0].read_bytes()).hexdigest()==digest
        print(name,'original helper SHA256 PASS')
