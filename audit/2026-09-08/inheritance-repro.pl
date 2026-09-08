use strict;
use warnings;
use Test::More;
use FindBin;
our @commands;
BEGIN {
    package Net::IP;
    $INC{'Net/IP.pm'}=__FILE__;
    package PVE::JSONSchema;
    $INC{'PVE/JSONSchema.pm'}=__FILE__;
    sub register_format {}
    package PVE::ProcFSTools;
    $INC{'PVE/ProcFSTools.pm'}=__FILE__;
    package PVE::RPCEnvironment;
    $INC{'PVE/RPCEnvironment.pm'}=__FILE__;
    package PVE::Storage::Plugin;
    $INC{'PVE/Storage/Plugin.pm'}=__FILE__;
    sub import {}
    package PVE::Tools;
    $INC{'PVE/Tools.pm'}=__FILE__;
    sub import {no strict 'refs'; *{caller().'::run_command'}=\&run_command;}
    sub run_command {push @main::commands,$_[0]; return $_[0][1] eq 'get' ? 1 : 0;}
    package PVE::RESTEnvironment;
    $INC{'PVE/RESTEnvironment.pm'}=__FILE__;
    sub import {}
    package PVE::Storage;
    $INC{'PVE/Storage.pm'}=__FILE__;
    sub APIVER () {15}
    package TrueNAS::Client;
    $INC{'TrueNAS/Client.pm'}=__FILE__;
    package TrueNAS::Helpers;
    $INC{'TrueNAS/Helpers.pm'}=__FILE__;
    sub import {no strict 'refs'; for my $name (@_[1..$#_]) {*{caller().'::'.$name}=sub {};}}
}
# Pass the unmodified upstream file pinned in the report. No ZFS command is executed.
my $upstream=shift @ARGV or die 'pass pinned ZFSPoolPlugin.pm path';
require $upstream;
$INC{'PVE/Storage/ZFSPoolPlugin.pm'}=$upstream;
use lib "$FindBin::Bin/../../perl5";
require PVE::Storage::Custom::TrueNASPlugin;
my $p='PVE::Storage::Custom::TrueNASPlugin';
my $cfg={pool=>'tank/remote',target=>'iqn.2026-01.test:audit',portal=>'audit.invalid'};
is_deeply([$p->volume_export_formats($cfg,'audit','vm-100-disk-0')],['zfs'],
    'BUG: remote plugin advertises inherited local ZFS export');
open my $fh,'+<','/dev/null' or die $!;
$p->volume_export($cfg,'audit',$fh,'vm-100-disk-0','zfs','s1',undef,0);
is_deeply($commands[-1],['zfs','send','-RpvU','--','tank/remote/vm-100-disk-0@s1'],
    'BUG: inherited export builds local zfs send for remote pool');
$p->volume_import($cfg,'audit',$fh,'vm-100-disk-0','zfs',undef,undef,0,0);
is_deeply($commands[-1],['zfs','recv','-F','-x','encryption','--','tank/remote/vm-100-disk-0'],
    'BUG: inherited import builds local zfs recv for remote pool');
done_testing;
