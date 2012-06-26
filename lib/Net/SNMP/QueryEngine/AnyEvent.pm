package Net::SNMP::QueryEngine::AnyEvent;

use 5.006;
use strict;
use warnings;

our $VERSION = '0.01';

use AnyEvent::Handle;
use base 'AnyEvent::Handle';
use Data::MessagePack;

use constant RT_SETOPT   => 1;
use constant RT_INFO     => 3;
use constant RT_GET      => 4;
use constant RT_GETTABLE => 5;
use constant RT_REPLY    => 0x10;
use constant RT_ERROR    => 0x20;

sub read_handle;

sub new
{
	my $class_or_ref = shift;
	my %args = (connect => ["127.0.0.1", 7667], @_, on_read => \&read_handler);
	my $self = $class_or_ref->SUPER::new(%args);
	$self->{sqe}{condvar} = AnyEvent->condvar;
	$self->{sqe}{pending} = 0;
	$self->{sqe}{mp} = Data::MessagePack->new->prefer_integer;
	$self->{sqe}{up} = Data::MessagePack::Unpacker->new;
	$self->{sqe}{nup} = 0;
	$self->{sqe}{cid} = int rand 1000000;
	$self->{sqe}{cb} = {};
	return $self;
}

sub wait
{
	my $self = shift;
	return unless $self->{sqe}{pending};
	$self->{sqe}{condvar}->recv;
}

sub cmd
{
	my ($self, $cb, @cmd) = @_;
	$self->{sqe}{cb}{$self->{sqe}{cid}} = $cb;
	$self->{sqe}{pending}++;
	if ($self->{sqe}{pending} == 1 && $self->{sqe}{condvar}->ready) {
		# XXX "reset" a condvar so "wait" can be correctly called again
		$self->{sqe}{condvar} = AnyEvent->condvar;
	}
	$self->push_write($self->{sqe}{mp}->pack(\@cmd));
}

sub read_handler
{
	my $self = shift;
	my $cl = length($self->{rbuf});
	$self->{sqe}{nup} += $cl;
again:
	my $o = $self->{sqe}{up}->execute($self->{rbuf}, 0);
	if ($o) {
		my $data = $self->{sqe}{up}->data;
		if (ref($data) ne "ARRAY" || @$data < 3 || !$self->{sqe}{cb}{$data->[1]}) {
		} else {
			$self->{sqe}{cb}{$data->[1]}->($self, $data->[0] & RT_REPLY, $data->[2]);
			delete $self->{sqe}{cb}{$data->[1]};
			$self->{sqe}{pending}--;
			if ($self->{sqe}{pending} <= 0) {
				$self->{sqe}{condvar}->send;
			}
		}
		substr($self->{rbuf}, 0, $o - ($self->{sqe}{nup}-$cl), "");
		$self->{sqe}{up}->reset;
		$cl = $self->{sqe}{nup} = length($self->{rbuf});
		goto again if $cl;
	}
	$self->{rbuf} = "";
}

sub setopt
{
	my ($self, $host, $port, $opts, $cb) = @_;
	$self->cmd($cb, RT_SETOPT, ++$self->{sqe}{cid}, $host, $port, $opts);
}

sub get
{
	my ($self, $host, $port, $oids, $cb) = @_;
	$self->cmd($cb, RT_GET, ++$self->{sqe}{cid}, $host, $port, $oids);
}

sub gettable
{
	my ($self, $host, $port, $oid, $max_rep, $cb) = @_;
	if ($cb) {
		$self->cmd($cb, RT_GETTABLE, ++$self->{sqe}{cid}, $host, $port, $oid, $max_rep);
	} else {
		$self->cmd($max_rep, RT_GETTABLE, ++$self->{sqe}{cid}, $host, $port, $oid);
	}
}

sub info
{
	my ($self, $cb) = @_;
	$self->cmd($cb, RT_INFO, ++$self->{sqe}{cid});
}

=head1 NAME

Net::SNMP::QueryEngine::AnyEvent - multiplexing SNMP query engine client using AnyEvent

=head1 VERSION

Version 0.01

=head1 SYNOPSIS

This is an AnyEvent-flavored Perl client for snmp-query-engine,
a multiplexing SNMP query engine.

    use Net::SNMP::QueryEngine::AnyEvent;

    my $sqe = Net::SNMP::QueryEngine::AnyEvent->new;

    $sqe->setopt("127.0.0.1", 161, { community => "meow" }, sub {});

    $sqe->gettable("127.0.0.1", 161, "1.3.6.1.2.1.1", sub {
      my ($h, $ok, $r) = @_;
      for my $t (@$r) {
        print "$t->[0] => $t->[1]\n";
      }
    });

    $sqe->get("127.0.0.1", 161,
      ["1.3.6.1.2.1.1.5.0", "1.3.6.1.2.1.25.1.1.0"],
      sub {
        my ($h, $ok, $r) = @_;
        print "Hostname: $r->[0][1]\n";
        print "Uptime  : $r->[1][1]\n";
    });

    $sqe->wait;

=head1 METHODS

=head2 new

Constructor.  Takes the same arguments as the constructor of
the base class, AnyEvent::Handle::new,
but always overrides "on_read" callback.

By default, connects to snmp-query-engine listening on
localhost, port 7667.  Override this by specifying
a "connect" argument.

=head2 wait

Enters event loop until there are no unanswered queries.
Can be called multiple times.

=head2 setopt

Performs setopt request.

=head2 getopt

Performs getopt request.

=head2 get

Performs get request for arbitrary number
of OIDs.

=head2 gettable

Performs gettable request.

=head2 info

Performs info request.

=head1 AUTHOR

Anton Berezin, C<< <tobez at tobez.org> >>

=head1 BUGS

Please report any bugs or feature requests to C<bug-net-snmp-queryengine-anyevent at rt.cpan.org>, or through
the web interface at L<http://rt.cpan.org/NoAuth/ReportBug.html?Queue=Net-SNMP-QueryEngine-AnyEvent>.  I will be notified, and then you'll
automatically be notified of progress on your bug as I make changes.


=head1 SEE ALSO

The snmp-query-engine daemon can be found on github
at L<https://github.com/tobez/snmp-query-engine>.


=head1 SUPPORT

You can find documentation for this module with the perldoc command.

    perldoc Net::SNMP::QueryEngine::AnyEvent


You can also look for information at:

=over 4

=item * RT: CPAN's request tracker (report bugs here)

L<http://rt.cpan.org/NoAuth/Bugs.html?Dist=Net-SNMP-QueryEngine-AnyEvent>

=item * AnnoCPAN: Annotated CPAN documentation

L<http://annocpan.org/dist/Net-SNMP-QueryEngine-AnyEvent>

=item * CPAN Ratings

L<http://cpanratings.perl.org/d/Net-SNMP-QueryEngine-AnyEvent>

=item * Search CPAN

L<http://search.cpan.org/dist/Net-SNMP-QueryEngine-AnyEvent/>

=back


=head1 ACKNOWLEDGEMENTS

This work is in part sponsored by Telia Denmark.

=head1 LICENSE AND COPYRIGHT

Copyright (c) 2012, Anton Berezin "<tobez@tobez.org>". All rights
reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are
met:

1. Redistributions of source code must retain the above copyright
   notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright
   notice, this list of conditions and the following disclaimer in the
   documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY AUTHOR AND CONTRIBUTORS ``AS IS'' AND ANY
EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL AUTHOR OR CONTRIBUTORS BE
LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR
OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

=cut

1;
