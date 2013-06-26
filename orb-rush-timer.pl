#!/usr/bin/env perl
use strict;
use warnings;
use Web::Scraper;
use URI;
use Time::Piece;
use Encode;
use LWP::UserAgent;
use Getopt::Long;
use JSON::Syck;
 
use Data::Dumper;
 
my $chan = '';
my $ikachan_url = '';
my $present_time = undef;
 
GetOptions(
    "channel=s" => \$chan,
    "ikachan_url=s" => \$ikachan_url,
    "present_time=i" => \$present_time, 
);
 
# 今日の日付情報を整理
my $t = localtime; 
my $today = $t->mday;
my $ym = decode('utf8', sprintf('%s年%s月', $t->year, $t->mon));
 
# 今日の公演情報を取得
my $act = get_today_act();
 
unless( $act->{title} ) {
    print("no act found.\n");
    exit;
}
 
# 公演があったら、スケジュールを確認して開始時刻を取る
my $time = get_time_table();
 
# wedataから公演時間を取得
$present_time = get_present_time();
debugln("time: $present_time");
 
debugln("$act->{date} @$time : $act->{title} ${present_time}min $act->{url}") if $act->{title};
 
if ( $ikachan_url && $chan ) {
   send_notice();
}
 
# 今日の演目情報を取得する
sub get_today_act {
    my $uri = URI->new("http://theatre-orb.com/lineup/calendar/");
    my $monthly = scraper {
        process "tr.dateBlock", "date[]" => scraper {
            process "th",   date  => 'TEXT';
            process "td a", title => 'TEXT';
            process "td a", url   => '@href';
        }
    };
    my $res = $monthly->scrape( $uri );
    for my $day (@{$res->{date}}) {
        $day->{date} =~ /\d*/;
        #print encode('utf8', "$day->{date} : $day->{title} $day->{url}\n") if $day->{title};
        return $day if $& eq $today;
    }
}
 
sub get_time_table {
    my @time = ();
    my $uri = URI->new($act->{url});
    my $schedule = scraper {
        process "div.eventSchedule table", "tables[]" => scraper {
            process "tr", "rows[]" => scraper {
                process "th", "label[]"  => 'TEXT';
                process "td", "value[]" => 'TEXT';
            }
        }
    };
 
    my $res = $schedule->scrape( $uri );
 
    for my $table (@{$res->{tables}}) {
        # 今月のスケジュール以外は見ない
        my $label = $table->{rows}[0]{label};
        next unless $label;
        next if $label->[0] ne $ym;
 
        # 今月のカレンダーならばさらに処理を進める
        my $count = 0;
        my $index;
        for my $row (@{$table->{rows}}) {
            # 1行目は日付ラベルとして処理
            if ( $count == 0 ) {
                my @label = @{$row->{label}};
                for ( my $i=1; $i<=$#label; $i++) {
                    $label[$i] =~ /\d*/;
                    $index = $i if $& eq $today;
                }
            }
            else {
                next unless $index > 0;
                my $label = $row->{label}[0];
               my $value = $row->{value}[$index - 1];
                push @time, $label if $value 
            }
            $count++;
        }
    }
    return \@time;
}
 
sub send_notice {
    my $ua = LWP::UserAgent->new(
        agent   => 'Project::Ikachan/0.1',
        timeout => 1,
    );
 
    # 開始と終了の時間が近づいたらそれぞれアラート
    foreach my $start (@$time) {
        my $pt = Time::Piece->strptime($t->strftime("%Y-%m-%d $start:00 +0900"), '%Y-%m-%d %T %z'); 
        #debugln($pt. " - " .$t);
        #debugln($pt->epoch. " - " .$t->epoch);
        # 公演開始１時間前にアラート
        my $diff = $pt - $t;
        if ( 55 * 60 < $diff && $diff < 65 * 60 ) {
            my $message = "\x{03}2,9[ORB注意報]".  encode('utf8', $start) ."より演目が上演されます。混雑に注意しましょう all";
            $ua->post($ikachan_url, +{
                channel => $chan,
                message => $message,
            });
            $message = "演目：". encode('utf8', $act->{title});
            $message .= $present_time ? " (上演時間は$present_time分の予定です)":" (上演時間は2~3時間が目安です)";
            $ua->post($ikachan_url, +{
                channel => $chan,
                message => $message,
            });
        }
        # 公演時間が解れば機能する
        next unless $present_time;
        $diff = $t - $pt;
        if ( ($present_time - 31) * 60 < $diff && $diff < ($present_time - 20) * 60 ) {
            my $et = localtime($pt->epoch + $present_time * 60); 
            my $message = "\x{03}2,9[ORB注意報]".  encode('utf8', $et->strftime('%H:%M')) ."に演目が終了予定です。混雑に注意しましょう all";
            $ua->post($ikachan_url, +{
                channel => $chan,
                message => $message,
            });
            $message = "演目：". encode('utf8', $act->{title});
            $ua->post($ikachan_url, +{
                channel => $chan,
                message => $message,
            });
        }
    }
}
 
sub get_present_time {
    my $ua = LWP::UserAgent->new(
        agent   => 'crawl.hakumai.net',
        timeout => 1,
    );
    my $response = $ua->get('http://wedata.net/databases/TheaterOrbSchedule/items_all.json');
    if ($response->is_success) { 
        my $data = JSON::Syck::Load($response->decoded_content);
        $act->{url} =~ m|([\-_a-zA-Z0-9]*)/$|;
        my $key = $1;
        foreach my $item (@$data) {
            next if $key ne $item->{name};
            return $item->{data}{running_time};
        }
    }
    return undef;
}
 
sub debug {
    print encode('utf8', "@_");
} 
sub debugln {
    debug(@_);
    print "\n";
}
