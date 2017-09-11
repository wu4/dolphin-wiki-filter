#!/usr/bin/env perl
use strict;
use warnings;

use threads;
use threads::shared;
use LWP::Simple;
use LWP::Protocol::https;
use Mojo::DOM;
use experimental 'smartmatch';
use utf8;
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";
$|++;

my $URL :shared;
$URL = 'https://wiki.dolphin-emu.org';
my @game_urls;

my @cats = (
  '4 (Players supported)',
  'GameCube Controller (Input supported)',
  # 'Co-op (Game mode)',
);
sub underscore (_) {s/\s/_/gr}

sub eat_arr (&&\@) {
  my ($thread_code, $join_code, $arr) = @_;
  do {
    for (threads->list) {
      &$join_code($_->join) if $_->is_joinable
    }
    while (threads->list < 8) {
      last unless @$arr;
      threads->create({'context' => 'list'}, $thread_code, pop @$arr);
    }
  } while (threads->list);
}

sub linebreak (_) {
  "<span>$_[0]</span" =~ s|, |</span><span>|gr
}

sub children_exist ($@) {
  my $elem = shift;
  my @methods = @_;
  return '' unless defined $elem;
  for (@methods) {
    my $elem = eval('$elem->' . $_);
    return '' unless defined $elem;
  }
  return $elem;
}

my %cats_depag;
eat_arr {
  local $_ = shift;
  my $nextpage = "$URL/index.php?title=Category:" . underscore;
  print STDERR "BEGIN $_\n";

  my @pages;
  while (defined $nextpage) {
    my $content = Mojo::DOM->new(get $nextpage)->at('#mw-pages');

    for ($content->find('.mw-category a')->each) {
      push @pages, $_->attr->{href};
    }

    $nextpage = undef;
    for ($content->find('a')->each) {
      if ($_->text eq 'next page') {
        $nextpage = $URL . $_->attr->{href};
        last;
      }
    }
  }
  print STDERR " END  $_\n";

  return $_, @pages;
} sub {
  my ($cat, @pages) = @_;
  $cats_depag{$cat} = \@pages;
}, @cats;

my @cats_depag_arr = do {
  my %seen;
  $seen{$_}++ for map @$_, values %cats_depag;
  grep {$seen{$_} == keys %cats_depag} keys %seen;
};

my $gamenum = scalar @cats_depag_arr;
my @games;
eat_arr {
  my $url = $URL . shift;
  my $dom = Mojo::DOM->new(get $url);

  my $title = $dom->at('#firstHeading')->text;

  my ($platform, $genres, $modes, $inputs);
  for ($dom->at('.infobox')->find('tr')->each) {
    my ($type, $values) = $_->find('td')->each;
    next unless defined $type;
    next unless defined $type->at('a');

    my $t = $type->at('a')->text;

    if    ($t eq 'Platform(s)')   {$platform = linebreak $values->all_text}
    elsif ($t eq 'Genre(s)')      {$genres   = linebreak $values->all_text}
    elsif ($t eq 'Mode(s)')       {$modes    = linebreak $values->all_text}
    elsif ($t eq 'Input methods') {$inputs   = linebreak $values->all_text}
  }

  return $title, <<~"eoc"
    <tr>
      <td class="platform">$platform</td>
      <td class="modes">$modes</td>
      <td class="genres">$genres</td>
      <td class="inputs">$inputs</td>
      <td class="title"><a href="$url">$title</a></td>
    </tr>
  eoc
} sub {
  print STDERR "\r\e[2K"
             . ($gamenum - scalar @cats_depag_arr)
             . '/'
             . $gamenum;
  push @games, [@_];
}, @cats_depag_arr;

print <<~"eoh";
<html><head>
  <meta charset="utf8">
  <script
    type="text/javascript"
    src="https://kryogenix.org/code/browser/sorttable/sorttable.js"></script>
eoh

if ($ARGV[0] eq '--embed-css') {
  print qq{<style type="text/css">};
  open my $fh, '<', 'games.css';
  chomp(my @lines = <$fh>);
  print join("\n", @lines);
  close $fh;
  print qq{</style>};
} else {
  print qq{<link rel="stylesheet" type="text/css" href="games.css" />};
}

print <<~"eoh";
  </head>
  <table class="sortable">
    <thead>
      <tr>
        <th>Platform</th>
        <th>Mode(s)</th>
        <th>Genre(s)</th>
        <th>Input methods</th>
        <th>Game</th>
      </tr>
    </thead>
    <tbody>
eoh
print join('', map {$_->[1]} sort {$a->[0] cmp $b->[0]} @games) . "\n";
print "</tbody></table></html>\n";
