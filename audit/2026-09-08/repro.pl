use strict;
use warnings;
no warnings 'once';
use Test::More;
use JSON::PP ();
use FindBin;
BEGIN {
    # PVE and logging substitutes only; real JSON-RPC and WebSocket dependencies.
    package PVE::SafeSyslog;
    $INC{'PVE/SafeSyslog.pm'} = __FILE__;
    package TrueNAS::Helpers;
    $INC{'TrueNAS/Helpers.pm'} = __FILE__;
    sub import { no strict 'refs'; my $p = caller; for my $n (@_[1..$#_]) { *{"${p}::$n"} = sub { 0 }; } }
    package PVE::Storage::ZFSPoolPlugin;
    $INC{'PVE/Storage/ZFSPoolPlugin.pm'} = __FILE__;
    # Fixture for the PVE ZFSPoolPlugin volume-name contract, not a full PVE runtime.
    sub parse_volname {
        my ($class,$volname)=@_;
        my ($parent,$name)=$volname =~ m{^(?:(base-\d+-[^/]+)/)?((?:vm|base)-\d+-[^/]+)$};
        die 'unsupported fixture volume name' unless defined $name;
        my ($vmid)=$name =~ /^(?:vm|base)-(\d+)-/;
        my ($basevmid)=defined($parent) ? $parent =~ /^base-(\d+)-/ : ();
        return ('images',$name,$vmid,$parent,$basevmid,$name =~ /^base-/ ? 1 : 0,'raw');
    }
    package PVE::RESTEnvironment;
    $INC{'PVE/RESTEnvironment.pm'} = __FILE__;
    sub import {}
    package PVE::RPCEnvironment;
    $INC{'PVE/RPCEnvironment.pm'} = __FILE__;
    package PVE::Storage;
    $INC{'PVE/Storage.pm'} = __FILE__;
    sub APIVER () { 15 }
}
use lib "$FindBin::Bin/../../perl5";
require TrueNAS::Client;
require PVE::Storage::Custom::TrueNASPlugin;
{
    package AuditClient;
    our @ISA = ('TrueNAS::Client');
    sub _is_connected { 1 }
    sub _send { 1 }
    sub _receive { die "injected receive timeout\n" }
    sub _disconnect { $_[0]{connected}=0; $_[0]{auth}=0; }
}
sub client {
    return bless {auth=>1, connected=>1, error=>undef, timeout=>1, msg_id=>0, protocol=>'jsonrpc', rpc=>JSON::RPC::Common::Marshal::Text->new, targets=>{}}, 'AuditClient';
}
{
    my $c=client();
    my $r=$c->request('pool.dataset.create', {});
    ok(!defined($r) && !$c->has_error, 'BUG: receive timeout returns undef with has_error false');
    is(client()->zfs_zvol_create('tank/test',1048576,'16k',1),1,'BUG: create reports success after receive timeout');
    is(client()->zfs_zvol_delete('tank/test'),1,'BUG: delete reports success after receive timeout');
    is(client()->zfs_zvol_resize('tank/test',1048576,'volsize'),1,'BUG: resize reports success after receive timeout');
}
{
    no warnings 'redefine';
    local *AuditClient::iscsi_lun_nextid=sub {0};
    local *AuditClient::iscsi_target_getid=sub {1};
    local *AuditClient::_is_connected=sub {1};
    local *AuditClient::_connect=sub {};
    local *AuditClient::_authenticate=sub {$_[0]{auth}=1};
    my $c=client();
    is($c->iscsi_lun_create('/dev/zvol/tank/test'),1,'BUG: extent and mapping timeouts still return LUN success');
}
{
    my $c=client();
    $c->_handle_response('{"jsonrpc":"2.0","id":0,"error":{"code":-32601,"message":"Method not found"}}');
    ok(!$c->has_error,'BUG: valid JSON-RPC error without data.reason is not recorded');
    $c->{protocol}='ddp';
    eval {$c->_handle_response('invalid-json')};
    like($@,qr/HASH ref/,'BUG: parse failure crashes error handler with string-as-hash error');
    $c->{protocol}='jsonrpc';
    is($c->_handle_response('{"jsonrpc":"2.0","id":9999,"result":"foreign-response"}'),'foreign-response','BUG: response accepted without matching request ID');
    my $r=$c->_handle_response('{"jsonrpc":"2.0","id":0,"result":{"nested":{"result":null}}}');
    ok($r->{nested}{result},'BUG: null rewrite changes nested application data');
}
{
    no warnings 'redefine';
    my $connects=0;
    local *TrueNAS::Client::_send=sub {1};
    local *TrueNAS::Client::_message_gen=sub {'ping'};
    local *TrueNAS::Client::_receive=sub {die "injected heartbeat timeout\n"};
    local *TrueNAS::Client::_connect=sub {$connects++};
    my $c=bless {sock=>1, connected=>1, auth=>1, lastcall=>time-35},'TrueNAS::Client';
    eval {$c->request('system.version')};
    like($@,qr/heartbeat timeout/,'BUG: heartbeat timeout escapes request');
    is($connects,0,'BUG: heartbeat timeout does not reconnect');
    $c->{sock}=undef;
}
{
    # Real local pipe, IO::Select, sysread and Protocol::WebSocket::Frame.
    pipe(my $read, my $write) or die $!;
    syswrite($write,Protocol::WebSocket::Frame->new('first')->to_bytes . Protocol::WebSocket::Frame->new('second')->to_bytes);
    my $c=bless {sock=>$read, connected=>1, auth=>1, frame=>Protocol::WebSocket::Frame->new},'TrueNAS::Client';
    is($c->_receive(1),'first','control: first frame from multi-frame read is returned');
    eval {$c->_receive(1)};
    like($@,qr/Timeout waiting/,'BUG: buffered second frame is ignored until new socket data arrives');
    $c->_disconnect;
    is($c->{frame}->next,'second','BUG: disconnect preserves old connection frame data');
    close $write;
}
{
    package PluginFake;
    sub new {bless {},'PluginFake'}
    sub request {'test-version'}
    sub set_target {}
    sub zfs_zvol_resize {undef}
    sub zfs_zvol_delete {undef}
    sub iscsi_lun_delete {undef}
    sub iscsi_lun_get {{id=>1}} # present extent, absent lunid
    package main;
    no warnings 'redefine';
    local *TrueNAS::Client::new=\&PluginFake::new;
    my $cfg={truenas_apiv4_host=>'audit.invalid', pool=>'tank', portal=>'audit.invalid', target=>'iqn.2026-01.test:audit'};
    my $p='PVE::Storage::Custom::TrueNASPlugin';
    is($p->volume_resize($cfg,'audit','vm-100-disk-0',1048576,0),1048576,'BUG: plugin returns new size when resize failed');
    my $r=eval {$p->free_image('audit',$cfg,'vm-100-disk-0',0)};
    ok(!$@ && !defined($r),'BUG: plugin deletion returns normally after all five attempts fail');
    my $opts=$p->qemu_blockdev_options($cfg,'audit','vm-100-disk-0',undef,{});
    is($opts->{lun},0,'BUG: extent without lunid silently selects LUN 0');
}
{
    pipe(my $r, my $w) or die $!;
    my $c=bless {sock=>$w}, 'TrueNAS::Client';
    $c->_send('audit');
    sysread($r,my $wire,128);
    ok(!(unpack('C',substr($wire,1,1)) & 128),'BUG: actual client WebSocket frame is unmasked');
    close $r;
}
{
    # Real EOF and timeout through original request/_send/_receive.
    require Socket;
    for my $scenario ('eof','timeout') {
        socketpair(my $a,my $b,Socket::AF_UNIX(),Socket::SOCK_STREAM(),0) or die $!;
        shutdown($b,1) if $scenario eq 'eof';
        my $c=bless {sock=>$a,connected=>1,auth=>1,lastcall=>time,timeout=>0.2,msg_id=>0,
            protocol=>'jsonrpc',rpc=>JSON::RPC::Common::Marshal::Text->new,
            frame=>Protocol::WebSocket::Frame->new}, 'TrueNAS::Client';
        my $r=$c->request('system.version');
        ok(!defined($r) && !$c->has_error,"BUG: real socket $scenario returns without error status");
        close $b;
    }
}
{
    # Real TCP handshake stall, bounded only by an independent watchdog.
    require Time::HiRes;
    my $server=IO::Socket::IP->new(LocalHost=>'127.0.0.1',LocalPort=>80,Listen=>1,ReuseAddr=>1) or die $!;
    my $pid=fork(); defined($pid) or die $!;
    if (!$pid) { my $peer=$server->accept; sleep 2; close $peer if $peer; require POSIX; POSIX::_exit(0); }
    my $c=bless {secure=>0,host=>'127.0.0.1',timeout=>0.1,
        endpoints=>[{url=>'ws://127.0.0.1/websocket',protocol=>'ddp'}]},'TrueNAS::Client';
    my $start=Time::HiRes::time();
    local $SIG{ALRM}=sub {die "audit independent watchdog\n"};
    alarm 1;
    eval {$c->_connect};
    my $err=$@;
    alarm 0;
    like($err,qr/audit independent watchdog/,'BUG: handshake exits only because external watchdog fires');
    cmp_ok(Time::HiRes::time()-$start,'>=',0.9,'BUG: configured 0.1s timeout does not bound handshake');
    waitpid($pid,0);
    close $server;
}

{
    my $c=client();
    my $msg=JSON::PP::decode_json($c->_message_gen('auth.login','00123','000456'));
    is_deeply($msg->{params},[123,456],'BUG: numeric-looking credentials lose string type and leading zeroes');
    my $real=TrueNAS::Client->new({truenas_apiv4_host=>'audit.invalid',truenas_apikey=>'synthetic-key',
        truenas_use_ssl=>0,target=>'iqn.2026-01.test:audit'});
    is($real->{secure},1,'BUG: explicit SSL false is replaced with true');
    my @version=TrueNAS::Client::truenas_parse_version('TrueNAS-25.10.0');
    ok(!defined($version[0]),'BUG: version parser does not parse its input');
}
{
    no warnings 'redefine';
    local *AuditClient::iscsi_target_getid=sub {1};
    local *AuditClient::iscsi_targetextent_query=sub {undef};
    is(client()->iscsi_lun_nextid,0,'BUG: failed LUN enumeration is treated as an empty target');
}
{
    no warnings 'redefine';
    local *AuditClient::iscsi_lun_get=sub {{id=>2,targetextent=>3}};
    local *AuditClient::iscsi_target_getid=sub {1};
    local *AuditClient::request=sub {
        my ($c,$method)=@_;
        return $c->_handle_response($method eq 'iscsi.targetextent.delete'
            ? '{"jsonrpc":"2.0","id":1,"error":{"code":-32000,"message":"error","data":{"reason":"injected failure"}}}'
            : '{"jsonrpc":"2.0","id":2,"result":true}');
    };
    is(client()->iscsi_lun_delete('/dev/zvol/tank/test'),1,'BUG: second delete success hides first delete failure');
}
{
    no warnings 'redefine';
    local *TrueNAS::Client::new=\&PluginFake::new;
    local *PVE::Storage::ZFSPoolPlugin::find_free_diskname=sub {'vm-101-disk-0'};
    local *PluginFake::zfs_zvol_clone=sub {1};
    local *PluginFake::iscsi_lun_create=sub {1};
    local *PluginFake::zfs_zvol_get=sub {undef};
    my @deleted;
    my @listed;
    local *PluginFake::zfs_snapshot_delete=sub {push @deleted,$_[1];1};
    local *PluginFake::zfs_snapshot_list=sub {
        push @listed,$_[1];
        return [{name=>'tank/vm-101-disk-0@s1',snapshot_name=>'s1',
            properties=>{guid=>{value=>'1'},creation=>{rawvalue=>1}}}];
    };
    my $cfg={truenas_apiv4_host=>'audit.invalid',pool=>'tank',portal=>'audit.invalid',target=>'iqn.2026-01.test:audit'};
    my $p='PVE::Storage::Custom::TrueNASPlugin';
    is($p->clone_image($cfg,'audit','base-100-disk-0',101,undef),'vm-101-disk-0',
        'BUG: clone return value omits base volume prefix');
    $p->volume_snapshot_delete($cfg,'audit','base-100-disk-0/vm-101-disk-0','s1',0);
    is($deleted[-1],'tank/base-100-disk-0/vm-101-disk-0@s1','BUG: snapshot delete uses encoded volume name as dataset');
    $p->volume_rollback_is_possible($cfg,'audit','base-100-disk-0/vm-101-disk-0','s1',[]);
    is($listed[-1],'tank/base-100-disk-0/vm-101-disk-0','BUG: rollback check uses encoded volume name as dataset');
    my $info=$p->volume_snapshot_info($cfg,'audit','vm-101-disk-0');
    ok(!exists($info->{s1}) && exists($info->{'tank/vm-101-disk-0@s1'}),'BUG: snapshot info keys use full dataset path');
    is(scalar($p->volume_size_info($cfg,'audit','vm-101-disk-0',1)),0,'BUG: failed size query becomes a successful zero size');
    local *PluginFake::zfs_zvol_clone=sub {undef};
    is($p->clone_image($cfg,'audit','base-100-disk-0',101,undef),'vm-101-disk-0','BUG: failed clone still returns volume name');
}
{
    no warnings 'redefine';
    my @keys;
    local *TrueNAS::Client::new=sub {push @keys,$_[1]{truenas_apikey};return PluginFake->new};
    my $cfg={truenas_apiv4_host=>'cache-audit.invalid',target=>'iqn.2026-01.test:audit',truenas_apikey=>'synthetic-A'};
    PVE::Storage::Custom::TrueNASPlugin::truenas_client_init($cfg);
    PVE::Storage::Custom::TrueNASPlugin::truenas_client_init({%$cfg,truenas_apikey=>'synthetic-B'});
    is(scalar(@keys),1,'BUG: credential change on same host does not create a new client');
}
{
    # Nonempty Ping is returned as a business response rather than answered with Pong.
    pipe(my $r,my $w) or die $!;
    syswrite($w,Protocol::WebSocket::Frame->new(type=>'ping',buffer=>'audit-ping')->to_bytes);
    my $c=bless {sock=>$r,frame=>Protocol::WebSocket::Frame->new},'TrueNAS::Client';
    is($c->_receive(1),'audit-ping','BUG: WebSocket Ping payload is delivered as RPC response');
    $c->_disconnect;
    close $w;
}
{
    # Empty close frame has a false payload, so the opcode handling is skipped.
    pipe(my $r,my $w) or die $!;
    syswrite($w,Protocol::WebSocket::Frame->new(type=>'close',buffer=>'')->to_bytes);
    my $c=bless {sock=>$r,connected=>1,frame=>Protocol::WebSocket::Frame->new},'TrueNAS::Client';
    eval {$c->_receive(0.2)};
    like($@,qr/Timeout waiting/,'BUG: empty Close frame becomes a timeout instead of an immediate close');
    $c->_disconnect;
    close $w;
}
done_testing;
