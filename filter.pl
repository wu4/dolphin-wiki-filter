#!/usr/bin/env perl
use strict;
use warnings;

use threads;
use threads::shared;
use LWP::Simple;
use LWP::Protocol::https;
use Mojo::DOM;
use experimental 'smartmatch';
use List::Compare;
use HTML::TagTree;
use utf8;
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";
$|++;

my $URL :shared;
$URL = 'https://wiki.dolphin-emu.org';
my @game_urls;

my @cats = (
  '4 (Players supported)',
  # 'GameCube Controller (Input supported)',
  'Co-op (Game mode)',
);
sub underscore ($) {$_[0] =~ s/\s/_/gr}

my $filename = join('_', map {underscore s/ \(.*$//r} @cats) . '.html';

sub linebreak (_) {"<span>$_[0]</span" =~ s|, |</span><span>|gr}

sub eat_arr (&\@\@) {
  my ($thread_code, $arr, $ret) = @_;
  my $arr_size = scalar @$arr;
  my $finished_count = 0;
  do {
    for (threads->list) {
      if ($_->is_joinable) {
        push @$ret, [$_->join];
        print STDERR "\r\e[2K"
                   . (++$finished_count)
                   . '/'
                   . $arr_size;
        #&$join_code($_->join)
      }
    }
    while (threads->list < 8) {
      last unless @$arr;
      threads->create({'context' => 'list'}, $thread_code, pop @$arr);
    }
  } while (threads->list);
  print STDERR "\n";
}

my @cats_depag = do {
  eat_arr {
    my $cat = shift;
    my $nextpage = "$URL/index.php?title=Category:" . underscore $cat;

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

    return @pages;
  } @cats, my @ret;

  List::Compare->new(@ret)->get_intersection;
};

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

  return $title, $platform, $modes, $genres, $inputs, $url;
} @cats_depag, my @games;

my $html = HTML::TagTree->new('html');
my $head = $html->head;
my $body = $html->body;
$head->meta('', 'charset="utf8"');
$head->script('', 'type="text/javascript" src="https://kryogenix.org/code/browser/sorttable/sorttable.js"');

if (defined($ARGV[0]) && $ARGV[0] eq '--embed-css') {
  open my $fh, '<', 'games.css';
  chomp(my @lines = <$fh>);
  $head->style(join("\n", @lines), 'type="text/css"');
  close $fh;
} else {
  $head->link('', 'rel="stylesheet" type="text/css" href="games.css"');
}

my $table = $body->table('', 'class="sortable"');
my $thead_tr = $table->thead->tr;
$thead_tr->th($_) for qw{Platform Mode(s) Genre(s) Input&nbsp;methods Game};

my $tbody = $table->tbody;

for (sort {$a->[0] cmp $b->[0]} @games) {
  my ($title, $platform, $modes, $genres, $inputs, $url) = @$_;
  my $tr = $tbody->tr;
  eval '$tr->td($' . $_ . qq{,'class="$_"')} for qw{platform modes genres inputs};
  $tr->td('', 'class="title"')->a($title, qq{href="$url"});
}

open my $fh, '>', $filename;
binmode $fh, ":utf8";
print $fh $html->get_html_text(0, 1);
close $fh;

print "Saved to $filename\n";
