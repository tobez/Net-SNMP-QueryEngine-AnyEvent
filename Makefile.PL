use inc::Module::Install;

name     'Net-SNMP-QueryEngine-AnyEvent';
all_from 'lib/Net/SNMP/QueryEngine/AnyEvent.pm';
author   q{Anton Berezin <tobez@tobez.org>};
license  'bsd';

build_requires 'Test::More';

auto_install;

WriteAll;

