#!/usr/bin/perl -w
use strict;

use POE qw(Wheel::ReadWrite);
use Carp;
use Audio::XMMSClient;

$| = 1;

print "\033]0;xmms2 status\007";

my $REOPEN_INTERVAL = 3600;

POE::Session->create(
  inline_states => {
    _start => sub {
      $_[HEAP]{xsspid} = open($_[HEAP]{xssin}, "xscreensaver-command -watch |");
      $_[HEAP]{watcher} = POE::Wheel::ReadWrite->new(
        Handle => $_[HEAP]{xssin},
        InputEvent => 'on_input',
      );
      $_[HEAP]{xmmsclient} = Audio::XMMSClient->new( 'poe_client' );
      $_[HEAP]{xmmsclient}->connect;
      $_[HEAP]{lasttitle} = '';
      $_[HEAP]{blanked} = 0;
      $_[KERNEL]->delay(reopen => $REOPEN_INTERVAL);
      $_[KERNEL]->yield("check_title");
    },
    # workaround for memory leak
    reopen => sub {
      kill(15, $_[HEAP]{xsspid});
      close($_[HEAP]{xssin});
      $_[HEAP]{xsspid} = open($_[HEAP]{xssin}, "xscreensaver-command -watch |");
      $_[KERNEL]->delay(reopen => $REOPEN_INTERVAL);
    },
    on_input => sub {
      print "$_[ARG0]\n";
      if ($_[ARG0] =~ /^(BLANK|LOCK)/)
      {
        $_[HEAP]{blanked} = time;
      }
      elsif ($_[ARG0] =~ /^UNBLANK/)
      {
        $_[HEAP]{blanked} = 0;
      }
    },
    check_title => sub {
      my $r;
      $r = $_[HEAP]{xmmsclient}->playback_current_id;
      $r->wait;
      $r = $_[HEAP]{xmmsclient}->medialib_get_info($r->value);
      $r->wait;
      my $h = $r->value;
      #print Dumper $r->value;
      #print "Channel: " . $h->{'channel'}->{'plugin/curl'} . "\n";
      #print "Title:   " . $h->{'title'}->{'plugin/icymetaint'} . "\n";
      my $desc = $h->{'channel'}->{'plugin/curl'} . ' - ' . $h->{'title'}->{'plugin/icymetaint'};
      if ($desc ne $_[HEAP]{lasttitle}) {
        print "$desc\n";
        $_[HEAP]{lasttitle} = $desc;
      }
      if ($_[HEAP]{blanked} && $_[HEAP]{blanked} + 900 < time) {
        print "Screen has been locked for a while - stopping music\n";
        $_[HEAP]{xmmsclient}->playback_stop;
        $_[HEAP]{blanked} = 0;
      }
      sleep 1;
      $_[KERNEL]->yield("check_title");
    },
  },
);

POE::Kernel->run();
exit;

__END__
while (<IN>)
{
  if (m/^(BLANK|LOCK)/)
  {
    if (!$blanked)
    {
      print time."STOP\n";
      $blanked = 1;
    }
  }
  elsif (m/^UNBLANK/)
  {
    print time."PLAY\n";
    $blanked = 0;
  }
}
